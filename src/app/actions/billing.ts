"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requireAdmin, requireViewer } from "@/lib/auth";
import { siteUrl } from "@/lib/env";
import type { FormState } from "@/lib/forms";
import { stripeKey } from "@/lib/billing/config";
import { FAMILY_TERMS_VERSION, parseDollars } from "@/lib/billing/money";
import { runBilling } from "@/lib/billing/run";
import { createCustomer, createPayNowPage, createSetupPage } from "@/lib/billing/stripe";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

// Every action re-checks who is asking here, and the database checks again.

const ADMIN_PAGE = "/admin/billing";

// Database messages written for people (raised by the billing functions)
// are shown as they are; anything else gets a general message.
function plain(error: { code?: string; message: string } | null, fallback: string): FormState {
  if (!error) return {};
  const ours = ["42501", "22023", "23505", "23514"].includes(error.code ?? "");
  return { error: ours ? `${error.message}.` : fallback };
}

const uuid = z.uuid();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Choose a date.");

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

export async function saveFamilyBilling(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z
    .object({
      family_id: uuid,
      plan: z.enum(["weekly", "monthly", "term", "upfront"]),
      bill_payer_id: z.union([uuid, z.literal("")]),
    })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please choose a plan." };
  const { family_id, plan, bill_payer_id } = parsed.data;
  const supabase = await createClient();
  const existing = await supabase.from("billing_accounts").select("family_id, method").eq("family_id", family_id).maybeSingle();
  if (plan === "weekly" && existing.data?.method === "bank_debit") {
    return { error: "Weekly families pay by card. Ask the family to save a card first, or choose monthly or per term." };
  }
  const values = { plan, bill_payer_id: bill_payer_id || null };
  const result = existing.data
    ? await supabase.from("billing_accounts").update(values).eq("family_id", family_id)
    : await supabase.from("billing_accounts").insert({ family_id, ...values });
  if (result.error) return plain(result.error, "Couldn't save the billing plan.");
  revalidatePath(ADMIN_PAGE);
  return { message: "Billing plan saved." };
}

export async function saveKeptRate(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z
    .object({ family_id: uuid, price_item_id: uuid, amount: z.string(), note: z.string().max(500).optional() })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please fill in the rate." };
  const supabase = await createClient();
  if (parsed.data.amount.trim() === "") {
    const { error } = await supabase
      .from("billing_family_rates")
      .delete()
      .eq("family_id", parsed.data.family_id)
      .eq("price_item_id", parsed.data.price_item_id);
    if (error) return plain(error, "Couldn't remove the kept rate.");
    revalidatePath(ADMIN_PAGE);
    return { message: "Kept rate removed. This family now pays the price list." };
  }
  const cents = parseDollars(parsed.data.amount);
  if (cents === null) return { error: "Enter the hourly rate in dollars, for example 80 or 85.50." };
  const { error } = await supabase.from("billing_family_rates").upsert({
    family_id: parsed.data.family_id,
    price_item_id: parsed.data.price_item_id,
    amount_cents: cents,
    note: parsed.data.note?.trim() || null,
  });
  if (error) return plain(error, "Couldn't save the kept rate.");
  revalidatePath(ADMIN_PAGE);
  return { message: "Kept rate saved." };
}

export async function savePrice(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z
    .object({ id: uuid, amount: z.string(), gst_applies: z.string().optional(), active: z.string().optional() })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please fill in the price." };
  const cents = parseDollars(parsed.data.amount);
  if (cents === null) return { error: "Enter the price in dollars, for example 95." };
  const supabase = await createClient();
  const { error } = await supabase
    .from("billing_price_items")
    .update({ amount_cents: cents, gst_applies: parsed.data.gst_applies === "on", active: parsed.data.active === "on" })
    .eq("id", parsed.data.id);
  if (error) return plain(error, "Couldn't save the price. Only one price can be on for each session level.");
  revalidatePath(ADMIN_PAGE);
  return { message: "Price saved. New invoices use it; invoices already made don't change." };
}

export async function addSchoolPeriod(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z
    .object({
      name: z.string().trim().min(1, "Give it a name, for example Term 1 2027.").max(100),
      kind: z.enum(["term", "holidays"]),
      state: z.enum(["SA", "NSW", "VIC", "QLD", "WA", "TAS", "ACT", "NT"]),
      starts_on: day,
      ends_on: day,
    })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  if (parsed.data.ends_on < parsed.data.starts_on) return { error: "The end date is before the start date." };
  const supabase = await createClient();
  const { error } = await supabase.from("billing_school_periods").insert(parsed.data);
  if (error) return plain(error, "Couldn't add it. A term or holiday may already start on that date.");
  revalidatePath(ADMIN_PAGE);
  return { message: `${parsed.data.name} added.` };
}

export async function buildInvoice(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z.object({ family_id: uuid, from: day, to: day }).safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Choose the family and both dates." };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("billing_build_invoice", {
    p_family: parsed.data.family_id,
    p_from: parsed.data.from,
    p_to: parsed.data.to,
  });
  if (error) return plain(error, "Couldn't build the invoice.");
  revalidatePath(ADMIN_PAGE);
  return data
    ? { message: "Invoice built as a draft. It goes to Xero on its send date, or approve it below." }
    : { message: "Nothing to bill: there are no unbilled sessions in those dates." };
}

export async function runBillingNow(): Promise<FormState> {
  await requireAdmin();
  const s = await runBilling();
  revalidatePath(ADMIN_PAGE);
  const done = `Built ${s.invoicesBuilt} invoice(s), gave ${s.creditsGiven} cancellation credit(s), sent ${s.sentToXero} to Xero, charged ${s.charged}, ${s.pausesChanged} pause change(s).`;
  return s.problems.length ? { error: `${done} Problems: ${s.problems.join(" ")}` } : { message: done };
}

export async function approveInvoice(formData: FormData) {
  await requireAdmin();
  const id = uuid.safeParse(formData.get("id"));
  if (!id.success) return;
  const supabase = await createClient();
  await supabase.rpc("billing_approve_invoice", { p_invoice: id.data });
  revalidatePath(ADMIN_PAGE);
}

export async function voidInvoice(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z.object({ id: uuid, reason: z.string() }).safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please give a reason." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("billing_void_invoice", { p_invoice: parsed.data.id, p_reason: parsed.data.reason });
  if (error) return plain(error, "Couldn't cancel the invoice.");
  revalidatePath(ADMIN_PAGE);
  return { message: "Invoice cancelled. Its sessions can be billed again and any credit it used was returned. If it was already in Xero, void it there too." };
}

export async function addCredit(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z.object({ family_id: uuid, amount: z.string(), note: z.string() }).safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please fill in the amount and the reason." };
  const cents = parseDollars(parsed.data.amount);
  if (cents === null) return { error: "Enter the amount in dollars, for example 40." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("billing_add_credit", { p_family: parsed.data.family_id, p_amount_cents: cents, p_note: parsed.data.note });
  if (error) return plain(error, "Couldn't add the credit.");
  revalidatePath(ADMIN_PAGE);
  return { message: "Credit added. It comes off the family's next invoice." };
}

export async function overridePause(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z
    .object({ family_id: uuid, reason: z.string(), until: day, payment_plan: z.string().max(1000).optional() })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please give a reason and a date." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("billing_override_pause", {
    p_family: parsed.data.family_id,
    p_reason: parsed.data.reason,
    p_until: parsed.data.until,
    p_payment_plan: parsed.data.payment_plan ?? null,
  });
  if (error) return plain(error, "Couldn't lift the pause.");
  revalidatePath(ADMIN_PAGE);
  return { message: "Pause lifted until that date. If the family hasn't paid by then, it comes back on its own." };
}

export async function saveBillingSettings(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z
    .object({
      invoice_mode: z.enum(["awaiting_approval", "send"]),
      override_by: z.enum(["owner", "admin"]),
      show_tutor_on_invoice: z.string().optional(),
    })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please choose each setting." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("billing_settings")
    .update({ ...parsed.data, show_tutor_on_invoice: parsed.data.show_tutor_on_invoice === "on" })
    .eq("id", true)
    .select("id");
  if (error || !data?.length) return { error: "Only the owner can change billing settings." };
  revalidatePath(ADMIN_PAGE);
  return { message: "Settings saved." };
}

// ---------------------------------------------------------------------------
// Families
// ---------------------------------------------------------------------------

// The family's billing account, if the signed-in person may see it. Read
// through their own login, so the database decides.
async function myFamilyAccount(familyId: string) {
  const supabase = await createClient();
  const { data } = await supabase
    .from("billing_accounts")
    .select("family_id, plan, bill_payer_id")
    .eq("family_id", familyId)
    .maybeSingle();
  return data;
}

export async function acceptBillingTerms(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const familyId = uuid.safeParse(formData.get("family_id"));
  if (!familyId.success || formData.get("agree") !== "on") return { error: "Please tick the box to agree." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("billing_accept_terms", { p_family: familyId.data, p_version: FAMILY_TERMS_VERSION });
  if (error) return plain(error, "Couldn't save your agreement. Please try again.");
  revalidatePath("/billing");
  return { message: "Thanks, your agreement is saved." };
}

export async function setUpAutomaticPayment(formData: FormData) {
  const viewer = await requireViewer();
  const familyId = uuid.safeParse(formData.get("family_id"));
  if (!familyId.success) return;
  const account = await myFamilyAccount(familyId.data);
  if (!account) redirect("/billing?setup=missing");
  if (!stripeKey()) redirect("/billing?setup=not-connected");

  // Stripe's references are kept away from the browser, so they are read
  // and saved with the server's own access, after the check above.
  const db = createAdminClient();
  const { data: full } = await db
    .from("billing_accounts")
    .select("stripe_customer_id")
    .eq("family_id", familyId.data)
    .single();
  let customer = full?.stripe_customer_id as string | null;
  if (!customer) {
    const made = await createCustomer(viewer.fullName || "CLG family", viewer.email, familyId.data);
    customer = made.id;
    await db.from("billing_accounts").update({ stripe_customer_id: customer }).eq("family_id", familyId.data);
  }
  const page = await createSetupPage({
    customer,
    familyId: familyId.data,
    allowBankDebit: account.plan !== "weekly",
    returnUrl: `${siteUrl()}/billing`,
  });
  redirect(page.url);
}

export async function payInvoiceNow(formData: FormData) {
  await requireViewer();
  const id = uuid.safeParse(formData.get("id"));
  if (!id.success) return;
  if (!stripeKey()) redirect("/billing?setup=not-connected");
  const supabase = await createClient();
  // Only an invoice this person can see, and only while it's unpaid.
  const { data: inv } = await supabase
    .from("billing_invoices")
    .select("id, number, family_id, total_cents, status")
    .eq("id", id.data)
    .eq("status", "open")
    .maybeSingle();
  if (!inv?.family_id) redirect("/billing");
  const { data: pending } = await supabase
    .from("billing_payments")
    .select("id")
    .eq("invoice_id", inv.id)
    .in("status", ["processing", "succeeded"]);
  if (pending?.length) redirect("/billing?paid=processing");
  const db = createAdminClient();
  const { data: acct } = await db.from("billing_accounts").select("stripe_customer_id").eq("family_id", inv.family_id).single();
  const page = await createPayNowPage({
    customer: (acct?.stripe_customer_id as string | null) ?? null,
    invoiceId: inv.id,
    invoiceNumber: inv.number,
    familyId: inv.family_id,
    amountCents: inv.total_cents,
    returnUrl: `${siteUrl()}/billing`,
  });
  redirect(page.url);
}
