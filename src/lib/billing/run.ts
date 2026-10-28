import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { stripeKey, xeroConfig } from "./config";
import { StripeError, chargeSaved, getSetupIntent, type PaymentIntent } from "./stripe";
import {
  allocateCreditNote,
  createCreditNote,
  findOrCreateContact,
  getXeroInvoice,
  openCreditNotes,
  recordXeroPayment,
  sendInvoiceToXero,
  xeroConnection,
} from "./xero";

// The daily billing run and the handling of Stripe's messages. Uses the
// server's own database access, so it is only ever called from the server
// (the scheduled run, signed webhooks, or an admin action that has already
// checked the admin).

export function adelaideToday(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Australia/Adelaide" }).format(new Date());
}

type Summary = {
  invoicesBuilt: number;
  creditsGiven: number;
  sentToXero: number;
  charged: number;
  pausesChanged: number;
  payLines: number;
  problems: string[];
};

export async function runBilling(): Promise<Summary> {
  const db = createAdminClient();
  const today = adelaideToday();
  const summary: Summary = { invoicesBuilt: 0, creditsGiven: 0, sentToXero: 0, charged: 0, pausesChanged: 0, payLines: 0, problems: [] };

  const built = await db.rpc("billing_build_due_invoices", { p_today: today });
  if (built.error) summary.problems.push(`Building invoices: ${built.error.message}`);
  else summary.invoicesBuilt = built.data ?? 0;

  const credits = await db.rpc("billing_credit_cancellations");
  if (credits.error) summary.problems.push(`Cancellation credits: ${credits.error.message}`);
  else summary.creditsGiven = credits.data ?? 0;

  await sendDraftsToXero(today, summary);
  await sendCreditNotesToXero(today, summary);
  await applyCreditsInXero(today, summary);
  await chargeDueInvoices(today, summary);
  await syncPaymentsToXero(summary);

  const pauses = await db.rpc("billing_refresh_all_pauses", { p_today: today });
  if (pauses.error) summary.problems.push(`Pauses: ${pauses.error.message}`);
  else summary.pausesChanged = pauses.data ?? 0;

  // Tutor pay for the last two weeks, from confirmed worked times. Lines
  // already sent to Xero stay as they are.
  const from = new Date(Date.parse(`${today}T00:00:00Z`) - 14 * 86400000).toISOString().slice(0, 10);
  const yesterday = new Date(Date.parse(`${today}T00:00:00Z`) - 86400000).toISOString().slice(0, 10);
  const pay = await db.rpc("billing_build_pay", { p_from: from, p_to: yesterday });
  if (pay.error) summary.problems.push(`Tutor pay: ${pay.error.message}`);
  else summary.payLines = pay.data ?? 0;

  return summary;
}

// Drafts whose send date has come go to Xero. A $0 invoice (all paid by
// credit) is simply marked paid.
async function sendDraftsToXero(today: string, summary: Summary) {
  const db = createAdminClient();
  const { data: drafts } = await db
    .from("billing_invoices")
    .select("id, number, family_id, total_cents, send_on, due_on, period_start, period_end, discount_cents, credit_applied_cents, idempotency_key")
    .eq("status", "draft")
    .lte("send_on", today);
  if (!drafts?.length) return;

  for (const inv of drafts.filter((d) => d.total_cents === 0)) {
    await db.rpc("billing_approve_invoice", { p_invoice: inv.id });
  }
  const toSend = drafts.filter((d) => d.total_cents > 0);
  if (!toSend.length || !xeroConfig() || !(await xeroConnection())) return;

  const { data: settings } = await db.from("billing_settings").select("invoice_mode").single();
  const awaitingApproval = settings?.invoice_mode !== "send";

  for (const inv of toSend) {
    try {
      const contactId = await familyContact(inv.family_id);
      const { data: lines } = await db
        .from("billing_invoice_lines")
        .select("description, billed_minutes, hourly_cents, gst_cents")
        .eq("invoice_id", inv.id)
        .eq("active", true)
        .order("line_date");
      const xeroId = await sendInvoiceToXero({
        id: inv.id,
        number: inv.number,
        contactId,
        date: inv.send_on,
        dueDate: inv.due_on,
        reference: `Sessions ${inv.period_start} to ${inv.period_end}`,
        awaitingApproval,
        lines: (lines ?? []).map((l) => ({
          description: l.description,
          hours: l.billed_minutes / 60,
          hourlyCents: l.hourly_cents,
          gst: l.gst_cents > 0,
        })),
        discountCents: inv.discount_cents,
        idempotencyKey: inv.idempotency_key,
      });
      await db
        .from("billing_invoices")
        .update({ xero_invoice_id: xeroId, status: awaitingApproval ? "awaiting_approval" : "draft" })
        .eq("id", inv.id);
      if (!awaitingApproval) await db.rpc("billing_approve_invoice", { p_invoice: inv.id });
      summary.sentToXero++;
    } catch (e) {
      summary.problems.push(`Invoice ${inv.number} to Xero: ${(e as Error).message}`);
    }
  }
}

// The family's Xero contact, made the first time it's needed.
async function familyContact(familyId: string): Promise<string> {
  const db = createAdminClient();
  const { data: acct } = await db
    .from("billing_accounts")
    .select("xero_contact_id, bill_payer_id")
    .eq("family_id", familyId)
    .single();
  if (acct?.xero_contact_id) return acct.xero_contact_id;
  if (!acct?.bill_payer_id) throw new Error("No bill payer is set for this family.");
  const [{ data: person }, { data: contact }] = await Promise.all([
    db.from("accounts").select("full_name").eq("id", acct.bill_payer_id).single(),
    db.from("account_private").select("email").eq("account_id", acct.bill_payer_id).single(),
  ]);
  if (!person || !contact) throw new Error("The bill payer's name or email is missing.");
  const id = await findOrCreateContact(person.full_name, contact.email);
  await db.from("billing_accounts").update({ xero_contact_id: id }).eq("family_id", familyId);
  return id;
}

// Charges saved cards and bank debits on their charge date. One automatic
// try per invoice; after a failure the family pays by link. When the
// family splits its invoices, each payer is charged their own share from
// their own saved card or bank debit.
type SavedMethod = {
  method: "none" | "card" | "bank_debit";
  stripe_customer_id: string | null;
  stripe_payment_method_id: string | null;
  stripe_mandate_id: string | null;
};

async function chargeDueInvoices(today: string, summary: Summary) {
  if (!stripeKey()) return;
  const db = createAdminClient();
  const { data: due } = await db
    .from("billing_invoices")
    .select("id, number, family_id, total_cents, idempotency_key")
    .eq("status", "open")
    .lte("charge_on", today)
    .is("auto_charge_attempted_at", null)
    .gt("total_cents", 0);
  for (const inv of due ?? []) {
    const { data: acct } = await db
      .from("billing_accounts")
      .select("bill_payer_id, method, stripe_customer_id, stripe_payment_method_id, stripe_mandate_id")
      .eq("family_id", inv.family_id)
      .single();
    const { data: shares } = await db.from("billing_invoice_shares").select("payer_id, amount_cents").eq("invoice_id", inv.id);

    // Who to charge: the family's saved method for the whole invoice, or
    // each payer's own saved method for their share.
    const charges: { payerId?: string; amountCents: number; saved: SavedMethod }[] = [];
    if (!shares?.length) {
      if (acct) charges.push({ amountCents: inv.total_cents, saved: acct as SavedMethod });
    } else {
      const { data: others } = await db
        .from("billing_payers")
        .select("account_id, method, stripe_customer_id, stripe_payment_method_id, stripe_mandate_id")
        .eq("family_id", inv.family_id);
      for (const sh of shares) {
        if (!sh.payer_id || sh.amount_cents <= 0) continue;
        const saved = sh.payer_id === acct?.bill_payer_id ? acct : others?.find((o) => o.account_id === sh.payer_id);
        if (saved) charges.push({ payerId: sh.payer_id, amountCents: sh.amount_cents, saved: saved as SavedMethod });
      }
    }
    const ready = charges.filter((c) => c.saved.stripe_payment_method_id && c.saved.stripe_customer_id && c.saved.method !== "none");
    if (!ready.length) continue;

    // Mark the try first, so two runs at once can't both charge.
    const claimed = await db
      .from("billing_invoices")
      .update({ auto_charge_attempted_at: new Date().toISOString() })
      .eq("id", inv.id)
      .is("auto_charge_attempted_at", null)
      .select("id");
    if (!claimed.data?.length) continue;

    for (const c of ready) {
      try {
        const pi = await chargeSaved({
          customer: c.saved.stripe_customer_id!,
          paymentMethod: c.saved.stripe_payment_method_id!,
          mandate: c.saved.stripe_mandate_id,
          bankDebit: c.saved.method === "bank_debit",
          amountCents: c.amountCents,
          invoiceId: inv.id,
          familyId: inv.family_id,
          payerId: c.payerId,
          invoiceNumber: inv.number,
          idempotencyKey: inv.idempotency_key,
        });
        await recordPaymentIntent(pi, inv.id);
        summary.charged++;
      } catch (e) {
        const pi = e instanceof StripeError ? e.body.error?.payment_intent : undefined;
        const suffix = c.payerId ? `-${c.payerId}` : "";
        await db.rpc("billing_record_payer_payment", {
          p_invoice: inv.id,
          p_payer: c.payerId ?? null,
          p_provider: "stripe",
          p_ref: pi?.id ?? `failed-${inv.idempotency_key}${suffix}`,
          p_method: c.saved.method,
          p_amount_cents: c.amountCents,
          p_status: "failed",
          p_message: (e as Error).message,
        });
        summary.problems.push(`Payment for ${inv.number} failed: ${(e as Error).message}`);
      }
    }
  }
}

// Stripe payment result to the database.
export async function recordPaymentIntent(pi: PaymentIntent, invoiceId = pi.metadata?.invoice_id) {
  if (!invoiceId) return;
  const status =
    pi.status === "succeeded" ? "succeeded" : pi.status === "processing" ? "processing" : pi.status === "requires_payment_method" || pi.status === "canceled" ? "failed" : null;
  if (!status) return;
  const db = createAdminClient();
  const { error } = await db.rpc("billing_record_payer_payment", {
    p_invoice: invoiceId,
    p_payer: pi.metadata?.payer_id ?? null,
    p_provider: "stripe",
    p_ref: pi.id,
    p_method: pi.payment_method_types.includes("au_becs_debit") ? "bank_debit" : "card",
    p_amount_cents: pi.amount,
    p_status: status,
    p_message: pi.last_payment_error?.message ?? null,
  });
  if (error) throw new Error(`Couldn't record payment ${pi.id}: ${error.message}`);
}

// After a family saves a card or bank debit on Stripe's page.
export async function recordSavedPaymentMethod(setupIntentId: string) {
  const si = await getSetupIntent(setupIntentId);
  const familyId = si.metadata?.family_id;
  if (!familyId || !si.payment_method) return;
  const db = createAdminClient();
  const method = si.payment_method.type === "au_becs_debit" ? "bank_debit" : "card";
  // A second payer sharing the family's invoices saves their own method.
  if (si.metadata?.payer_id) {
    const { error } = await db.rpc("billing_save_payer_method", {
      p_family: familyId,
      p_payer: si.metadata.payer_id,
      p_customer: si.customer,
      p_payment_method: si.payment_method.id,
      p_method: method,
      p_mandate: si.mandate,
    });
    if (error) throw new Error(`Couldn't save the payment method: ${error.message}`);
    return;
  }
  const { error } = await db.rpc("billing_save_payment_method", {
    p_family: familyId,
    p_customer: si.customer,
    p_payment_method: si.payment_method.id,
    p_method: si.payment_method.type === "au_becs_debit" ? "bank_debit" : "card",
    p_mandate: si.mandate,
  });
  if (error) throw new Error(`Couldn't save the payment method: ${error.message}`);
}

// Payments Stripe has confirmed are recorded in Xero against the invoice.
async function syncPaymentsToXero(summary: Summary) {
  if (!xeroConfig() || !(await xeroConnection())) return;
  const db = createAdminClient();
  const { data } = await db
    .from("billing_payments")
    .select("id, provider_ref, amount_cents, updated_at, invoice:billing_invoices(xero_invoice_id)")
    .eq("status", "succeeded")
    .eq("provider", "stripe")
    .is("xero_payment_id", null)
    .limit(50);
  for (const p of (data ?? []) as unknown as {
    id: string;
    provider_ref: string;
    amount_cents: number;
    updated_at: string;
    invoice: { xero_invoice_id: string | null } | null;
  }[]) {
    if (!p.invoice?.xero_invoice_id) continue;
    try {
      const xeroPayment = await recordXeroPayment(p.invoice.xero_invoice_id, p.amount_cents, p.updated_at.slice(0, 10), p.provider_ref);
      await db.from("billing_payments").update({ xero_payment_id: xeroPayment }).eq("id", p.id);
    } catch (e) {
      summary.problems.push(`Payment ${p.provider_ref} to Xero: ${(e as Error).message}`);
    }
  }
}

// Credits given in the app become credit notes on the family's Xero
// contact. Credit put back by a cancelled invoice isn't a new credit note.
async function sendCreditNotesToXero(today: string, summary: Summary) {
  if (!xeroConfig() || !(await xeroConnection())) return;
  const db = createAdminClient();
  const { data: credits } = await db
    .from("billing_credits")
    .select("id, family_id, kind, amount_cents, note, created_at, session_id")
    .gt("amount_cents", 0)
    .in("kind", ["cancellation", "missed_in_pause", "tutor_day_off", "goodwill"])
    .is("xero_credit_note_id", null)
    .limit(50);
  for (const c of credits ?? []) {
    if (!c.family_id) continue;
    const { data: acct } = await db.from("billing_accounts").select("xero_contact_id").eq("family_id", c.family_id).maybeSingle();
    // Families get a Xero contact with their first invoice; until then the
    // credit waits.
    if (!acct?.xero_contact_id) continue;
    let gst = false;
    if (c.session_id) {
      const { data: line } = await db
        .from("billing_invoice_lines")
        .select("gst_cents")
        .eq("session_id", c.session_id)
        .eq("active", true)
        .maybeSingle();
      gst = (line?.gst_cents ?? 0) > 0;
    }
    try {
      const id = await createCreditNote({
        contactId: acct.xero_contact_id,
        date: c.created_at.slice(0, 10) <= today ? c.created_at.slice(0, 10) : today,
        description: c.note ?? "Credit",
        amountCents: c.amount_cents,
        gst,
        reference: c.id,
      });
      await db.from("billing_credits").update({ xero_credit_note_id: id }).eq("id", c.id);
    } catch (e) {
      summary.problems.push(`Credit note to Xero: ${(e as Error).message}`);
    }
  }
}

// An invoice that used credit gets that credit applied in Xero once the
// invoice is approved there.
async function applyCreditsInXero(today: string, summary: Summary) {
  if (!xeroConfig() || !(await xeroConnection())) return;
  const db = createAdminClient();
  const { data: invoices } = await db
    .from("billing_invoices")
    .select("id, number, family_id, xero_invoice_id, credit_applied_cents")
    .in("status", ["open", "paid"])
    .gt("credit_applied_cents", 0)
    .not("xero_invoice_id", "is", null)
    .is("xero_credit_allocated_at", null)
    .limit(50);
  for (const inv of invoices ?? []) {
    if (!inv.family_id || !inv.xero_invoice_id) continue;
    const { data: acct } = await db.from("billing_accounts").select("xero_contact_id").eq("family_id", inv.family_id).maybeSingle();
    if (!acct?.xero_contact_id) continue;
    try {
      // Only what isn't applied yet, so a run that stopped part way never
      // applies credit twice.
      const xinv = await getXeroInvoice(inv.xero_invoice_id);
      if (!["AUTHORISED", "PAID"].includes(xinv.Status)) continue;
      let left = inv.credit_applied_cents - Math.round((xinv.AmountCredited ?? 0) * 100);
      const notes = left > 0 ? await openCreditNotes(acct.xero_contact_id) : [];
      const available = Math.round(notes.reduce((t, n) => t + n.RemainingCredit, 0) * 100);
      if (left > 0 && available < left) {
        // The credit notes haven't all reached Xero yet; try again tomorrow.
        continue;
      }
      for (const n of notes) {
        if (left <= 0) break;
        const take = Math.min(left, Math.round(n.RemainingCredit * 100));
        await allocateCreditNote(n.CreditNoteID, inv.xero_invoice_id, take, today);
        left -= take;
      }
      await db.from("billing_invoices").update({ xero_credit_allocated_at: new Date().toISOString() }).eq("id", inv.id);
    } catch (e) {
      summary.problems.push(`Applying credit to ${inv.number} in Xero: ${(e as Error).message}`);
    }
  }
}
