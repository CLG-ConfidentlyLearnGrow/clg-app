import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { stripeKey, xeroConfig } from "./config";
import { StripeError, chargeSaved, getSetupIntent, type PaymentIntent } from "./stripe";
import { findOrCreateContact, recordXeroPayment, sendInvoiceToXero, xeroConnection } from "./xero";

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
        creditCents: inv.credit_applied_cents,
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
// try per invoice; after a failure the family pays by link.
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
      .select("method, stripe_customer_id, stripe_payment_method_id, stripe_mandate_id")
      .eq("family_id", inv.family_id)
      .single();
    if (!acct?.stripe_payment_method_id || !acct.stripe_customer_id || acct.method === "none") continue;

    // Mark the try first, so two runs at once can't both charge.
    const claimed = await db
      .from("billing_invoices")
      .update({ auto_charge_attempted_at: new Date().toISOString() })
      .eq("id", inv.id)
      .is("auto_charge_attempted_at", null)
      .select("id");
    if (!claimed.data?.length) continue;

    try {
      const pi = await chargeSaved({
        customer: acct.stripe_customer_id,
        paymentMethod: acct.stripe_payment_method_id,
        mandate: acct.stripe_mandate_id,
        bankDebit: acct.method === "bank_debit",
        amountCents: inv.total_cents,
        invoiceId: inv.id,
        familyId: inv.family_id,
        invoiceNumber: inv.number,
        idempotencyKey: inv.idempotency_key,
      });
      await recordPaymentIntent(pi, inv.id);
      summary.charged++;
    } catch (e) {
      const pi = e instanceof StripeError ? e.body.error?.payment_intent : undefined;
      await db.rpc("billing_record_payment", {
        p_invoice: inv.id,
        p_provider: "stripe",
        p_ref: pi?.id ?? `failed-${inv.idempotency_key}`,
        p_method: acct.method,
        p_amount_cents: inv.total_cents,
        p_status: "failed",
        p_message: (e as Error).message,
      });
      summary.problems.push(`Payment for ${inv.number} failed: ${(e as Error).message}`);
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
  const { error } = await db.rpc("billing_record_payment", {
    p_invoice: invoiceId,
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
