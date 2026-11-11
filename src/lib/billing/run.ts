// Summary: the daily billing run and the handling of Stripe's messages.
// Builds invoices, gives cancellation credits, sends invoices and credit
// notes to Xero, charges saved cards and bank debits, records payments,
// refreshes family pauses and builds tutor pay lines.
//
// Stops this file ever being sent to the browser.
import "server-only";
// The all-powerful database helper, used because this runs as a background job.
import { createAdminClient } from "@/lib/supabase/admin";
// Checks whether Stripe and Xero are set up.
import { stripeKey, xeroConfig } from "./config";
// The Stripe helpers: error type, charge a saved method, read a saved method, payment shape.
import { StripeError, chargeSaved, getSetupIntent, type PaymentIntent } from "./stripe";
// The Xero helpers used below.
import { // Brings in:
  allocateCreditNote, // apply a credit note to an invoice,
  createCreditNote, // make a credit note,
  findOrCreateContact, // find or make a family's contact,
  getXeroInvoice, // read an invoice,
  openCreditNotes, // list credit notes with credit left,
  recordXeroPayment, // record a payment,
  sendInvoiceToXero, // send an invoice,
  xeroConnection, // and read the stored connection.
} from "./xero"; // End of the Xero helpers.

// The daily billing run and the handling of Stripe's messages. Uses the
// server's own database access, so it is only ever called from the server
// (the scheduled run, signed webhooks, or an admin action that has already
// checked the admin).

// Today's date in Adelaide, as YYYY-MM-DD.
export function adelaideToday(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Australia/Adelaide" }).format(new Date()); // The Canadian format happens to be YYYY-MM-DD.
} // End of adelaideToday.

// What the run reports back to the admin page.
type Summary = {
  invoicesBuilt: number; // How many invoices were built.
  creditsGiven: number; // How many cancellation credits were given.
  sentToXero: number; // How many invoices went to Xero.
  charged: number; // How many payments were taken.
  pausesChanged: number; // How many family pauses started or ended.
  payLines: number; // How many tutor pay lines were built.
  problems: string[]; // Plain messages about anything that went wrong.
}; // End of the report shape.

// Runs every billing step once, in order, and reports what happened.
export async function runBilling(): Promise<Summary> {
  const db = createAdminClient(); // Connects with full access.
  const today = adelaideToday(); // Today's date in Adelaide.
  const summary: Summary = { invoicesBuilt: 0, creditsGiven: 0, sentToXero: 0, charged: 0, pausesChanged: 0, payLines: 0, problems: [] }; // Starts the report with nothing done.

  const built = await db.rpc("billing_build_due_invoices", { p_today: today }); // Asks the database to build invoices that are due.
  if (built.error) summary.problems.push(`Building invoices: ${built.error.message}`); // Notes any problem,
  else summary.invoicesBuilt = built.data ?? 0; // or records how many were built.

  const credits = await db.rpc("billing_credit_cancellations"); // Asks the database to credit late cancellations.
  if (credits.error) summary.problems.push(`Cancellation credits: ${credits.error.message}`); // Notes any problem,
  else summary.creditsGiven = credits.data ?? 0; // or records how many credits were given.

  await sendDraftsToXero(today, summary); // Sends due invoices to Xero.
  await sendCreditNotesToXero(today, summary); // Sends new credits to Xero as credit notes.
  await applyCreditsInXero(today, summary); // Applies credit to invoices in Xero.
  await chargeDueInvoices(today, summary); // Charges saved cards and bank debits that are due.
  await syncPaymentsToXero(summary); // Records confirmed payments in Xero.

  const pauses = await db.rpc("billing_refresh_all_pauses", { p_today: today }); // Asks the database to start or end pauses for overdue families.
  if (pauses.error) summary.problems.push(`Pauses: ${pauses.error.message}`); // Notes any problem,
  else summary.pausesChanged = pauses.data ?? 0; // or records how many changed.

  // Tutor pay for the last two weeks, from confirmed worked times. Lines
  // already sent to Xero stay as they are.
  const from = new Date(Date.parse(`${today}T00:00:00Z`) - 14 * 86400000).toISOString().slice(0, 10); // The date 14 days ago (86,400,000 ms is one day).
  const yesterday = new Date(Date.parse(`${today}T00:00:00Z`) - 86400000).toISOString().slice(0, 10); // Yesterday's date.
  const pay = await db.rpc("billing_build_pay", { p_from: from, p_to: yesterday }); // Asks the database to build pay lines for that fortnight.
  if (pay.error) summary.problems.push(`Tutor pay: ${pay.error.message}`); // Notes any problem,
  else summary.payLines = pay.data ?? 0; // or records how many lines were built.

  // Part-time and full-time staff: top up to their agreed hours once a pay
  // period ends. Top-ups wait for an admin to approve them.
  const topUps = await db.rpc("billing_check_guaranteed_hours", { p_day: yesterday }); // Asks the database to add any guaranteed-hours top-ups for yesterday's pay period.
  if (topUps.error) summary.problems.push(`Guaranteed hours: ${topUps.error.message}`); // Notes any problem.

  return summary; // Hands back the report.
} // End of runBilling.

// Drafts whose send date has come go to Xero. A $0 invoice (all paid by
// credit) is simply marked paid.
async function sendDraftsToXero(today: string, summary: Summary) { // For each draft whose send date has come:
  const db = createAdminClient(); // Connects with full access.
  const { data: drafts } = await db // Reads the drafts:
    .from("billing_invoices") // from the invoices table,
    .select("id, number, family_id, total_cents, send_on, due_on, period_start, period_end, discount_cents, credit_applied_cents, idempotency_key") // with the details needed to send them,
    .eq("status", "draft") // only drafts,
    .lte("send_on", today); // whose send date is today or earlier.
  if (!drafts?.length) return; // None: nothing to do.

  for (const inv of drafts.filter((d) => d.total_cents === 0)) { // Invoices for $0 (all covered by credit):
    await db.rpc("billing_approve_invoice", { p_invoice: inv.id }); // are approved straight away (which marks them paid).
  } // End of the $0 loop.
  const toSend = drafts.filter((d) => d.total_cents > 0); // The rest need sending to Xero.
  if (!toSend.length || !xeroConfig() || !(await xeroConnection())) return; // Stops if none, or Xero isn't set up or connected.

  const { data: settings } = await db.from("billing_settings").select("invoice_mode").single(); // Reads whether invoices wait for approval or are sent straight away.
  const awaitingApproval = settings?.invoice_mode !== "send"; // Waits for approval unless the setting says "send".

  for (const inv of toSend) { // Goes through each invoice to send.
    try { // Sending could fail.
      const contactId = await familyContact(inv.family_id); // Gets (or makes) the family's Xero contact.
      const { data: lines } = await db // Reads the invoice's lines:
        .from("billing_invoice_lines") // from the invoice lines table,
        .select("description, billed_minutes, hourly_cents, gst_cents") // with words, minutes, hourly price and GST,
        .eq("invoice_id", inv.id) // for this invoice,
        .eq("active", true) // only lines still in use,
        .order("line_date"); // in date order.
      const xeroId = await sendInvoiceToXero({ // Sends the invoice to Xero:
        id: inv.id, // its id,
        number: inv.number, // its number,
        contactId, // the family's contact,
        date: inv.send_on, // dated the send date,
        dueDate: inv.due_on, // due on the due date,
        reference: `Sessions ${inv.period_start} to ${inv.period_end}`, // with the session dates as the reference,
        awaitingApproval, // waiting for approval or not,
        lines: (lines ?? []).map((l) => ({ // and each line:
          description: l.description, // its words,
          hours: l.billed_minutes / 60, // hours (minutes divided by 60),
          hourlyCents: l.hourly_cents, // hourly price,
          gst: l.gst_cents > 0, // and whether it has GST.
        })), // End of the lines.
        discountCents: inv.discount_cents, // Any bank debit discount.
        idempotencyKey: inv.idempotency_key, // The never-twice key.
      }); // End of the invoice.
      await db // Saves Xero's id on the invoice:
        .from("billing_invoices") // in the invoices table,
        .update({ xero_invoice_id: xeroId, status: awaitingApproval ? "awaiting_approval" : "draft" }) // with the new stage,
        .eq("id", inv.id); // for this invoice.
      if (!awaitingApproval) await db.rpc("billing_approve_invoice", { p_invoice: inv.id }); // If sent straight away, approves it in the app too.
      summary.sentToXero++; // Counts it as sent.
    } catch (e) { // Something went wrong:
      summary.problems.push(`Invoice ${inv.number} to Xero: ${(e as Error).message}`); // notes which invoice and why.
    } // End of the error handling.
  } // End of the loop.
} // End of sendDraftsToXero.

// The family's Xero contact, made the first time it's needed.
async function familyContact(familyId: string): Promise<string> { // Looks up (or makes) the contact for one family.
  const db = createAdminClient(); // Connects with full access.
  const { data: acct } = await db // Reads the family's billing account:
    .from("billing_accounts") // from the billing accounts table,
    .select("xero_contact_id, bill_payer_id") // its Xero contact and bill payer,
    .eq("family_id", familyId) // for this family,
    .single(); // (there's exactly one).
  if (acct?.xero_contact_id) return acct.xero_contact_id; // Already has a contact: uses it.
  if (!acct?.bill_payer_id) throw new Error("No bill payer is set for this family."); // No bill payer: can't make a contact.
  const [{ data: person }, { data: contact }] = await Promise.all([ // Reads two things at once:
    db.from("accounts").select("full_name").eq("id", acct.bill_payer_id).single(), // the bill payer's name,
    db.from("account_private").select("email").eq("account_id", acct.bill_payer_id).single(), // and their email.
  ]); // End of the two reads.
  if (!person || !contact) throw new Error("The bill payer's name or email is missing."); // Either missing: plain message.
  const id = await findOrCreateContact(person.full_name, contact.email); // Finds or makes the Xero contact.
  await db.from("billing_accounts").update({ xero_contact_id: id }).eq("family_id", familyId); // Saves it on the family's account for next time.
  return id; // Hands back the contact id.
} // End of familyContact.

// Charges saved cards and bank debits on their charge date. One automatic
// try per invoice; after a failure the family pays by link. When the
// family splits its invoices, each payer is charged their own share from
// their own saved card or bank debit.
type SavedMethod = { // A saved way of paying.
  method: "none" | "card" | "bank_debit"; // Card, bank debit, or none.
  stripe_customer_id: string | null; // The Stripe customer.
  stripe_payment_method_id: string | null; // The saved card or bank account.
  stripe_mandate_id: string | null; // The bank debit agreement, if any.
}; // End of the saved method shape.

// Takes payment for invoices whose charge date has come.
async function chargeDueInvoices(today: string, summary: Summary) {
  if (!stripeKey()) return; // Stripe not set up: nothing to do.
  const db = createAdminClient(); // Connects with full access.
  const { data: due } = await db // Reads invoices to charge:
    .from("billing_invoices") // from the invoices table,
    .select("id, number, family_id, total_cents, idempotency_key") // with id, number, family, total and never-twice key,
    .eq("status", "open") // only sent invoices,
    .lte("charge_on", today) // whose charge date has come,
    .is("auto_charge_attempted_at", null) // not already tried,
    .gt("total_cents", 0); // and for more than $0.
  for (const inv of due ?? []) { // Goes through each one.
    const { data: acct } = await db // Reads the family's saved method:
      .from("billing_accounts") // from the billing accounts table,
      .select("bill_payer_id, method, stripe_customer_id, stripe_payment_method_id, stripe_mandate_id") // the bill payer and their saved method,
      .eq("family_id", inv.family_id) // for this family,
      .single(); // (there's exactly one).
    const { data: shares } = await db.from("billing_invoice_shares").select("payer_id, amount_cents").eq("invoice_id", inv.id); // Reads any split between payers.

    // Who to charge: the family's saved method for the whole invoice, or
    // each payer's own saved method for their share.
    const charges: { payerId?: string; amountCents: number; saved: SavedMethod }[] = []; // The list of charges to make.
    if (!shares?.length) { // No split:
      if (acct) charges.push({ amountCents: inv.total_cents, saved: acct as SavedMethod }); // one charge for the whole amount from the family's method.
    } else { // Split between payers:
      const { data: others } = await db // reads the other payers' saved methods:
        .from("billing_payers") // from the payers table,
        .select("account_id, method, stripe_customer_id, stripe_payment_method_id, stripe_mandate_id") // with each payer's saved method,
        .eq("family_id", inv.family_id); // for this family.
      for (const sh of shares) { // Goes through each share.
        if (!sh.payer_id || sh.amount_cents <= 0) continue; // Skips shares with no payer or no amount.
        const saved = sh.payer_id === acct?.bill_payer_id ? acct : others?.find((o) => o.account_id === sh.payer_id); // Uses the bill payer's method or the other payer's own.
        if (saved) charges.push({ payerId: sh.payer_id, amountCents: sh.amount_cents, saved: saved as SavedMethod }); // Adds a charge for that share.
      } // End of the shares loop.
    } // End of the split case.
    const ready = charges.filter((c) => c.saved.stripe_payment_method_id && c.saved.stripe_customer_id && c.saved.method !== "none"); // Keeps only charges with a complete saved method.
    if (!ready.length) continue; // None ready: the family pays by link instead.

    // Mark the try first, so two runs at once can't both charge.
    const claimed = await db // Marks the try:
      .from("billing_invoices") // in the invoices table,
      .update({ auto_charge_attempted_at: new Date().toISOString() }) // with the time of the try,
      .eq("id", inv.id) // for this invoice,
      .is("auto_charge_attempted_at", null) // only if no one else has tried yet,
      .select("id"); // and reports whether it worked.
    if (!claimed.data?.length) continue; // Another run got there first: skips.

    for (const c of ready) { // Goes through each charge.
      try { // Charging could fail.
        const pi = await chargeSaved({ // Asks Stripe to charge:
          customer: c.saved.stripe_customer_id!, // this customer,
          paymentMethod: c.saved.stripe_payment_method_id!, // from this saved method,
          mandate: c.saved.stripe_mandate_id, // with this debit agreement,
          bankDebit: c.saved.method === "bank_debit", // as bank debit or card,
          amountCents: c.amountCents, // this amount,
          invoiceId: inv.id, // for this invoice,
          familyId: inv.family_id, // this family,
          payerId: c.payerId, // this payer (if split),
          invoiceNumber: inv.number, // with this invoice number,
          idempotencyKey: inv.idempotency_key, // and the never-twice key.
        }); // End of the charge.
        await recordPaymentIntent(pi, inv.id); // Records Stripe's result in the database.
        summary.charged++; // Counts it as charged.
      } catch (e) { // The charge failed:
        const pi = e instanceof StripeError ? e.body.error?.payment_intent : undefined; // finds Stripe's payment id, if Stripe gave one,
        const suffix = c.payerId ? `-${c.payerId}` : ""; // adds the payer's id to the reference when split,
        await db.rpc("billing_record_payer_payment", { // and records the failed payment:
          p_invoice: inv.id, // for this invoice,
          p_payer: c.payerId ?? null, // this payer (if split),
          p_provider: "stripe", // through Stripe,
          p_ref: pi?.id ?? `failed-${inv.idempotency_key}${suffix}`, // with Stripe's id (or a made-up "failed" reference),
          p_method: c.saved.method, // by this method,
          p_amount_cents: c.amountCents, // for this amount,
          p_status: "failed", // as failed,
          p_message: (e as Error).message, // with the reason.
        }); // End of recording the failure.
        summary.problems.push(`Payment for ${inv.number} failed: ${(e as Error).message}`); // Notes the failure for the admin.
      } // End of the error handling.
    } // End of the charges loop.
  } // End of the invoices loop.
} // End of chargeDueInvoices.

// Stripe payment result to the database.
export async function recordPaymentIntent(pi: PaymentIntent, invoiceId = pi.metadata?.invoice_id) {
  if (!invoiceId) return; // No invoice linked: nothing to record.
  const status = // Turns Stripe's stage into ours:
    pi.status === "succeeded" ? "succeeded" : pi.status === "processing" ? "processing" : pi.status === "requires_payment_method" || pi.status === "canceled" ? "failed" : null; // succeeded, processing, failed (needs a new method or cancelled), or nothing to record yet.
  if (!status) return; // Still in progress at Stripe: nothing to record.
  const db = createAdminClient(); // Connects with full access.
  const { error } = await db.rpc("billing_record_payer_payment", { // Records the payment:
    p_invoice: invoiceId, // for this invoice,
    p_payer: pi.metadata?.payer_id ?? null, // this payer (if split),
    p_provider: "stripe", // through Stripe,
    p_ref: pi.id, // with Stripe's id,
    p_method: pi.payment_method_types.includes("au_becs_debit") ? "bank_debit" : "card", // by bank debit or card,
    p_amount_cents: pi.amount, // for this amount,
    p_status: status, // at this stage,
    p_message: pi.last_payment_error?.message ?? null, // with any failure reason.
  }); // End of recording.
  if (error) throw new Error(`Couldn't record payment ${pi.id}: ${error.message}`); // Save failed: plain message.
} // End of recordPaymentIntent.

// After a family saves a card or bank debit on Stripe's page.
export async function recordSavedPaymentMethod(setupIntentId: string) {
  const si = await getSetupIntent(setupIntentId); // Reads the saved method from Stripe.
  const familyId = si.metadata?.family_id; // Which family it's for.
  if (!familyId || !si.payment_method) return; // Missing details: nothing to save.
  const db = createAdminClient(); // Connects with full access.
  const method = si.payment_method.type === "au_becs_debit" ? "bank_debit" : "card"; // Bank debit or card.
  // A second payer sharing the family's invoices saves their own method.
  if (si.metadata?.payer_id) { // Saved by a second payer:
    const { error } = await db.rpc("billing_save_payer_method", { // saves it as that payer's method:
      p_family: familyId, // for this family,
      p_payer: si.metadata.payer_id, // this payer,
      p_customer: si.customer, // their Stripe customer,
      p_payment_method: si.payment_method.id, // the saved method,
      p_method: method, // bank debit or card,
      p_mandate: si.mandate, // and any debit agreement.
    }); // End of the save.
    if (error) throw new Error(`Couldn't save the payment method: ${error.message}`); // Save failed: plain message.
    return; // Done.
  } // End of the second payer case.
  const { error } = await db.rpc("billing_save_payment_method", { // Otherwise saves it as the family's method:
    p_family: familyId, // for this family,
    p_customer: si.customer, // their Stripe customer,
    p_payment_method: si.payment_method.id, // the saved method,
    p_method: si.payment_method.type === "au_becs_debit" ? "bank_debit" : "card", // bank debit or card,
    p_mandate: si.mandate, // and any debit agreement.
  }); // End of the save.
  if (error) throw new Error(`Couldn't save the payment method: ${error.message}`); // Save failed: plain message.
} // End of recordSavedPaymentMethod.

// Payments Stripe has confirmed are recorded in Xero against the invoice.
async function syncPaymentsToXero(summary: Summary) {
  if (!xeroConfig() || !(await xeroConnection())) return; // Xero not set up or connected: nothing to do.
  const db = createAdminClient(); // Connects with full access.
  const { data } = await db // Reads payments to send:
    .from("billing_payments") // from the payments table,
    .select("id, provider_ref, amount_cents, updated_at, invoice:billing_invoices(xero_invoice_id)") // with Stripe's id, amount, date and the invoice's Xero id,
    .eq("status", "succeeded") // only successful ones,
    .eq("provider", "stripe") // taken through Stripe,
    .is("xero_payment_id", null) // not yet in Xero,
    .limit(50); // up to 50 at a time.
  for (const p of (data ?? []) as unknown as { // Goes through each, which has:
    id: string; // its id,
    provider_ref: string; // Stripe's reference,
    amount_cents: number; // the amount,
    updated_at: string; // when it was last updated,
    invoice: { xero_invoice_id: string | null } | null; // and its invoice's Xero id.
  }[]) { // End of the payment shape.
    if (!p.invoice?.xero_invoice_id) continue; // Invoice not in Xero yet: waits.
    try { // Sending could fail.
      const xeroPayment = await recordXeroPayment(p.invoice.xero_invoice_id, p.amount_cents, p.updated_at.slice(0, 10), p.provider_ref); // Records the payment in Xero.
      await db.from("billing_payments").update({ xero_payment_id: xeroPayment }).eq("id", p.id); // Saves Xero's id on the payment so it isn't sent again.
    } catch (e) { // Something went wrong:
      summary.problems.push(`Payment ${p.provider_ref} to Xero: ${(e as Error).message}`); // notes which payment and why.
    } // End of the error handling.
  } // End of the loop.
} // End of syncPaymentsToXero.

// Credits given in the app become credit notes on the family's Xero
// contact. Credit put back by a cancelled invoice isn't a new credit note.
async function sendCreditNotesToXero(today: string, summary: Summary) {
  if (!xeroConfig() || !(await xeroConnection())) return; // Xero not set up or connected: nothing to do.
  const db = createAdminClient(); // Connects with full access.
  const { data: credits } = await db // Reads credits to send:
    .from("billing_credits") // from the credits table,
    .select("id, family_id, kind, amount_cents, note, created_at, session_id") // with family, kind, amount, note, date and session,
    .gt("amount_cents", 0) // only positive credits,
    .in("kind", ["cancellation", "missed_in_pause", "tutor_day_off", "goodwill"]) // of the kinds that become credit notes,
    .is("xero_credit_note_id", null) // not yet in Xero,
    .limit(50); // up to 50 at a time.
  for (const c of credits ?? []) { // Goes through each credit.
    if (!c.family_id) continue; // No family: skips.
    const { data: acct } = await db.from("billing_accounts").select("xero_contact_id").eq("family_id", c.family_id).maybeSingle(); // Reads the family's Xero contact.
    // Families get a Xero contact with their first invoice; until then the
    // credit waits.
    if (!acct?.xero_contact_id) continue; // No contact yet: waits.
    let gst = false; // Whether GST applies (no by default).
    if (c.session_id) { // If the credit is for a session:
      const { data: line } = await db // reads that session's invoice line:
        .from("billing_invoice_lines") // from the invoice lines table,
        .select("gst_cents") // its GST amount,
        .eq("session_id", c.session_id) // for this session,
        .eq("active", true) // still in use,
        .maybeSingle(); // (one at most).
      gst = (line?.gst_cents ?? 0) > 0; // GST applies if the line had GST.
    } // End of the GST check.
    try { // Sending could fail.
      const id = await createCreditNote({ // Makes the credit note in Xero:
        contactId: acct.xero_contact_id, // for the family's contact,
        date: c.created_at.slice(0, 10) <= today ? c.created_at.slice(0, 10) : today, // dated the credit's date (never later than today),
        description: c.note ?? "Credit", // with its note as the words,
        amountCents: c.amount_cents, // for this amount,
        gst, // with or without GST,
        reference: c.id, // using the credit's id as the reference.
      }); // End of the credit note.
      await db.from("billing_credits").update({ xero_credit_note_id: id }).eq("id", c.id); // Saves Xero's id on the credit so it isn't sent again.
    } catch (e) { // Something went wrong:
      summary.problems.push(`Credit note to Xero: ${(e as Error).message}`); // notes it.
    } // End of the error handling.
  } // End of the loop.
} // End of sendCreditNotesToXero.

// An invoice that used credit gets that credit applied in Xero once the
// invoice is approved there.
async function applyCreditsInXero(today: string, summary: Summary) {
  if (!xeroConfig() || !(await xeroConnection())) return; // Xero not set up or connected: nothing to do.
  const db = createAdminClient(); // Connects with full access.
  const { data: invoices } = await db // Reads invoices that used credit:
    .from("billing_invoices") // from the invoices table,
    .select("id, number, family_id, xero_invoice_id, credit_applied_cents") // with number, family, Xero id and credit used,
    .in("status", ["open", "paid"]) // that are sent or paid,
    .gt("credit_applied_cents", 0) // that used some credit,
    .not("xero_invoice_id", "is", null) // that are in Xero,
    .is("xero_credit_allocated_at", null) // whose credit isn't applied there yet,
    .limit(50); // up to 50 at a time.
  for (const inv of invoices ?? []) { // Goes through each invoice.
    if (!inv.family_id || !inv.xero_invoice_id) continue; // Missing family or Xero id: skips.
    const { data: acct } = await db.from("billing_accounts").select("xero_contact_id").eq("family_id", inv.family_id).maybeSingle(); // Reads the family's Xero contact.
    if (!acct?.xero_contact_id) continue; // No contact: skips.
    try { // Talking to Xero could fail.
      // Only what isn't applied yet, so a run that stopped part way never
      // applies credit twice.
      const xinv = await getXeroInvoice(inv.xero_invoice_id); // Reads the invoice from Xero.
      if (!["AUTHORISED", "PAID"].includes(xinv.Status)) continue; // Not approved in Xero yet: waits.
      let left = inv.credit_applied_cents - Math.round((xinv.AmountCredited ?? 0) * 100); // Credit still to apply (in cents), minus what Xero already shows.
      const notes = left > 0 ? await openCreditNotes(acct.xero_contact_id) : []; // Gets the family's credit notes with credit left (if any is needed).
      const available = Math.round(notes.reduce((t, n) => t + n.RemainingCredit, 0) * 100); // Total credit available, in cents.
      if (left > 0 && available < left) { // Not enough credit in Xero yet:
        // The credit notes haven't all reached Xero yet; try again tomorrow.
        continue; // skips for now.
      } // End of the not-enough check.
      for (const n of notes) { // Goes through the credit notes, oldest first.
        if (left <= 0) break; // Stops once all credit is applied.
        const take = Math.min(left, Math.round(n.RemainingCredit * 100)); // Takes as much as needed from this note.
        await allocateCreditNote(n.CreditNoteID, inv.xero_invoice_id, take, today); // Applies it to the invoice in Xero.
        left -= take; // Reduces what's left to apply.
      } // End of the notes loop.
      await db.from("billing_invoices").update({ xero_credit_allocated_at: new Date().toISOString() }).eq("id", inv.id); // Marks the invoice's credit as applied.
    } catch (e) { // Something went wrong:
      summary.problems.push(`Applying credit to ${inv.number} in Xero: ${(e as Error).message}`); // notes which invoice and why.
    } // End of the error handling.
  } // End of the loop.
} // End of applyCreditsInXero.
