// Summary: billing actions. Admins set plans, kept rates, prices, school
// terms, invoices, credits, pauses, settings and split payments; families
// choose a plan, agree to terms, set up automatic payment and pay invoices.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { redirect } from "next/navigation"; // Lets the code send someone to another page.
import { z } from "zod"; // The form-checking library.
import { FINANCE, requireAdminLevel, requireViewer } from "@/lib/auth"; // The finance admin group, and the sign-in and admin-level checks.
import { siteUrl } from "@/lib/env"; // The app's web address, for links back from Stripe.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { stripeKey } from "@/lib/billing/config"; // Checks whether Stripe is set up.
import { FAMILY_TERMS_VERSION, parseDollars } from "@/lib/billing/money"; // The family terms version, and turning a typed price into cents.
import { runBilling } from "@/lib/billing/run"; // The daily billing run.
import { createCustomer, createPayNowPage, createSetupPage } from "@/lib/billing/stripe"; // Stripe helpers: make a customer, a pay-now page, a setup page.
import { createAdminClient } from "@/lib/supabase/admin"; // The all-powerful database helper (secret key).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Every action re-checks who is asking here, and the database checks again.

const ADMIN_PAGE = "/admin/billing"; // The billing admin page, refreshed after changes.

// Database messages written for people (raised by the billing functions)
// are shown as they are; anything else gets a general message.
// Turns a database error into a reply.
function plain(error: { code?: string; message: string } | null, fallback: string): FormState {
  if (!error) return {}; // No error: nothing to report.
  const ours = ["42501", "22023", "23505", "23514"].includes(error.code ?? ""); // True for the database's own plain refusals.
  return { error: ours ? `${error.message}.` : fallback }; // Shows that message, or the general one.
} // End of plain.

const uuid = z.uuid(); // The rule for a proper id.
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Choose a date."); // The rule for a date (YYYY-MM-DD).

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

// Saves a family's payment plan and bill payer.
export async function saveFamilyBilling(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const parsed = z // Checks the form has:
    .object({ // (the rules:)
      family_id: uuid, // which family,
      plan: z.enum(["weekly", "monthly", "term", "upfront"]), // weekly, monthly, per term or upfront,
      bill_payer_id: z.union([uuid, z.literal("")]), // the bill payer (or blank).
    }) // (end of the rules)
    .safeParse(Object.fromEntries(formData)); // (from the form's fields)
  if (!parsed.success) return { error: "Please choose a plan." }; // Problem: asks for a plan.
  const { family_id, plan, bill_payer_id } = parsed.data; // The checked values.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const existing = await supabase.from("billing_accounts").select("family_id, method").eq("family_id", family_id).maybeSingle(); // Reads the family's billing account, if any.
  if (plan === "weekly" && existing.data?.method === "bank_debit") { // Weekly but paying by bank debit:
    return { error: "Weekly families pay by card. Ask the family to save a card first, or choose monthly or per term." }; // explains weekly families pay by card.
  } // End of that check.
  const viewer = await requireViewer(); // Gets the admin's details.
  const values = { plan, bill_payer_id: bill_payer_id || null, plan_chosen_at: new Date().toISOString(), plan_chosen_by: viewer.id }; // What to save: plan, bill payer (or none), and when and by whom it was chosen.
  const result = existing.data // Saves it:
    ? await supabase.from("billing_accounts").update(values).eq("family_id", family_id) // updating the existing account,
    : await supabase.from("billing_accounts").insert({ family_id, ...values }); // or making a new one.
  if (result.error) return plain(result.error, "Couldn't save the billing plan."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  return { message: "Billing plan saved." }; // Confirms it.
} // End of saveFamilyBilling.

// Saves (or removes) a family's kept older hourly rate for one price item.
export async function saveKeptRate(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const parsed = z // Checks the form has:
    .object({ family_id: uuid, price_item_id: uuid, amount: z.string(), note: z.string().max(500).optional() }) // a family, a price item, an amount and an optional note,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: "Please fill in the rate." }; // Problem: asks for the rate.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  if (parsed.data.amount.trim() === "") { // Blank amount means remove it:
    const { error } = await supabase // deletes:
      .from("billing_family_rates") // from the kept rates table,
      .delete() // (removing the row)
      .eq("family_id", parsed.data.family_id) // for this family,
      .eq("price_item_id", parsed.data.price_item_id); // and this price item.
    if (error) return plain(error, "Couldn't remove the kept rate."); // Failed: plain message.
    revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
    return { message: "Kept rate removed. This family now pays the price list." }; // Confirms the family now pays the price list.
  } // End of the remove case.
  const cents = parseDollars(parsed.data.amount); // Turns the amount into cents.
  if (cents === null) return { error: "Enter the hourly rate in dollars, for example 80 or 85.50." }; // Not a price: shows an example.
  const { error } = await supabase.from("billing_family_rates").upsert({ // Saves (or replaces) the kept rate:
    family_id: parsed.data.family_id, // family,
    price_item_id: parsed.data.price_item_id, // price item,
    amount_cents: cents, // amount in cents,
    note: parsed.data.note?.trim() || null, // note (or none).
  }); // End of the save.
  if (error) return plain(error, "Couldn't save the kept rate."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  return { message: "Kept rate saved." }; // Confirms it.
} // End of saveKeptRate.

// Saves a price item's amount, GST and whether it's in use.
export async function savePrice(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const parsed = z // Checks the form has:
    .object({ id: uuid, amount: z.string(), gst_applies: z.string().optional(), active: z.string().optional() }) // an id, an amount, and the GST and in-use tick boxes,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: "Please fill in the price." }; // Problem: asks for the price.
  const cents = parseDollars(parsed.data.amount); // Turns the amount into cents.
  if (cents === null) return { error: "Enter the price in dollars, for example 95." }; // Not a price: shows an example.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase // Saves:
    .from("billing_price_items") // in the price items table,
    .update({ amount_cents: cents, gst_applies: parsed.data.gst_applies === "on", active: parsed.data.active === "on" }) // the amount, GST and in-use settings,
    .eq("id", parsed.data.id); // for this price item.
  if (error) return plain(error, "Couldn't save the price. Only one price can be on for each session level."); // Failed: explains only one price can be on per session level.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  return { message: "Price saved. New invoices use it; invoices already made don't change." }; // Confirms, noting old invoices don't change.
} // End of savePrice.

// Adds a school term or holiday period.
export async function addSchoolPeriod(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const parsed = z // Checks the form has:
    .object({ // (the rules:)
      name: z.string().trim().min(1, "Give it a name, for example Term 1 2027.").max(100), // a name,
      kind: z.enum(["term", "holidays"]), // term or holidays,
      state: z.enum(["SA", "NSW", "VIC", "QLD", "WA", "TAS", "ACT", "NT"]), // the state,
      starts_on: day, // the start date,
      ends_on: day, // the end date.
    }) // (end of the rules)
    .safeParse(Object.fromEntries(formData)); // (from the form's fields)
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  if (parsed.data.ends_on < parsed.data.starts_on) return { error: "The end date is before the start date." }; // End can't be before start.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("billing_school_periods").insert(parsed.data); // Saves it.
  if (error) return plain(error, "Couldn't add it. A term or holiday may already start on that date."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  return { message: `${parsed.data.name} added.` }; // Confirms it.
} // End of addSchoolPeriod.

// Builds a draft invoice for a family's unbilled sessions between two dates.
export async function buildInvoice(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const parsed = z.object({ family_id: uuid, from: day, to: day }).safeParse(Object.fromEntries(formData)); // Checks the form has a family and two dates.
  if (!parsed.success) return { error: "Choose the family and both dates." }; // Problem: asks for them.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("billing_build_invoice", { // Asks the database to build the invoice:
    p_family: parsed.data.family_id, // for this family,
    p_from: parsed.data.from, // from this date,
    p_to: parsed.data.to, // to this date.
  }); // End of the request.
  if (error) return plain(error, "Couldn't build the invoice."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  return data // Tells the admin:
    ? { message: "Invoice built as a draft. It goes to Xero on its send date, or approve it below." } // a draft was built and what happens next,
    : { message: "Nothing to bill: there are no unbilled sessions in those dates." }; // or there was nothing to bill.
} // End of buildInvoice.

// Runs the daily billing run straight away (the admin button).
export async function runBillingNow(): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const s = await runBilling(); // Runs it.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  const done = `Built ${s.invoicesBuilt} invoice(s), ${s.payLines} pay line(s) waiting to send, gave ${s.creditsGiven} cancellation credit(s), sent ${s.sentToXero} to Xero, charged ${s.charged}, ${s.pausesChanged} pause change(s).`; // What was done.
  return s.problems.length ? { error: `${done} Problems: ${s.problems.join(" ")}` } : { message: done }; // Shows that with any problems, or just what was done.
} // End of runBillingNow.

// Approves a draft invoice.
export async function approveInvoice(formData: FormData) {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the invoice id.
  if (!id.success) return; // Not a proper id: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("billing_approve_invoice", { p_invoice: id.data }); // Asks the database to approve it.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
} // End of approveInvoice.

// Cancels an invoice, with a reason.
export async function voidInvoice(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const parsed = z.object({ id: uuid, reason: z.string() }).safeParse(Object.fromEntries(formData)); // Checks the form has an id and a reason.
  if (!parsed.success) return { error: "Please give a reason." }; // Problem: asks for a reason.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("billing_void_invoice", { p_invoice: parsed.data.id, p_reason: parsed.data.reason }); // Asks the database to cancel it.
  if (error) return plain(error, "Couldn't cancel the invoice."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  return { message: "Invoice cancelled. Its sessions can be billed again and any credit it used was returned. If it was already in Xero, void it there too." }; // Confirms, with a reminder to void it in Xero too.
} // End of voidInvoice.

// Gives a family a credit.
export async function addCredit(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const parsed = z.object({ family_id: uuid, amount: z.string(), note: z.string() }).safeParse(Object.fromEntries(formData)); // Checks the form has a family, an amount and a reason.
  if (!parsed.success) return { error: "Please fill in the amount and the reason." }; // Problem: asks for them.
  const cents = parseDollars(parsed.data.amount); // Turns the amount into cents.
  if (cents === null) return { error: "Enter the amount in dollars, for example 40." }; // Not a price: shows an example.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("billing_add_credit", { p_family: parsed.data.family_id, p_amount_cents: cents, p_note: parsed.data.note }); // Asks the database to add the credit.
  if (error) return plain(error, "Couldn't add the credit."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  return { message: "Credit added. It comes off the family's next invoice." }; // Confirms it comes off the next invoice.
} // End of addCredit.

// Lifts an overdue family's pause until a date (or with a payment plan).
export async function overridePause(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const parsed = z // Checks the form has:
    .object({ family_id: uuid, reason: z.string(), until: day, payment_plan: z.string().max(1000).optional() }) // a family, a reason, a date and an optional payment plan,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: "Please give a reason and a date." }; // Problem: asks for them.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("billing_override_pause", { // Asks the database to lift the pause:
    p_family: parsed.data.family_id, // for this family,
    p_reason: parsed.data.reason, // with this reason,
    p_until: parsed.data.until, // until this date,
    p_payment_plan: parsed.data.payment_plan ?? null, // with this payment plan (or none).
  }); // End of the request.
  if (error) return plain(error, "Couldn't lift the pause."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  return { message: "Pause lifted until that date. If the family hasn't paid by then, it comes back on its own." }; // Confirms, noting the pause returns if still unpaid.
} // End of overridePause.

// Saves the billing settings (owner only).
export async function saveBillingSettings(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const parsed = z // Checks the form has:
    .object({ // (the rules:)
      invoice_mode: z.enum(["awaiting_approval", "send"]), // invoices wait for approval, or are sent,
      override_by: z.enum(["owner", "admin"]), // who can lift pauses: owner or any admin,
      show_tutor_on_invoice: z.string().optional(), // whether the tutor's name shows on invoices.
    }) // (end of the rules)
    .safeParse(Object.fromEntries(formData)); // (from the form's fields)
  if (!parsed.success) return { error: "Please choose each setting." }; // Problem: asks for each setting.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase // Saves:
    .from("billing_settings") // in the billing settings table,
    .update({ ...parsed.data, show_tutor_on_invoice: parsed.data.show_tutor_on_invoice === "on" }) // the settings, with the tick box as yes or no,
    .eq("id", true) // (there's only one settings row)
    .select("id"); // and reports which row changed.
  if (error || !data?.length) return { error: "Only the owner can change billing settings." }; // Nothing saved: only the owner can change them.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  return { message: "Settings saved." }; // Confirms it.
} // End of saveBillingSettings.

// ---------------------------------------------------------------------------
// Families
// ---------------------------------------------------------------------------

// The family's billing account, if the signed-in person may see it. Read
// through their own login, so the database decides.
async function myFamilyAccount(familyId: string) {
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data } = await supabase // Reads:
    .from("billing_accounts") // from the billing accounts table,
    .select("family_id, plan, bill_payer_id") // the family, plan and bill payer,
    .eq("family_id", familyId) // for this family,
    .maybeSingle(); // (one at most; none if not allowed to see it).
  return data; // Hands it back.
} // End of myFamilyAccount.

// A parent or adult learner chooses how often the family pays. Allowed
// until CLG sends the first invoice; the database checks this too.
export async function chooseBillingPlan(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z // Checks the form has:
    .object({ family_id: uuid, plan: z.enum(["weekly", "monthly", "term", "upfront"]) }) // a family and a plan,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: "Please choose how often you'd like to pay." }; // Problem: asks them to choose.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("billing_choose_plan", { p_family: parsed.data.family_id, p_plan: parsed.data.plan }); // Asks the database to save the choice.
  if (error) return plain(error, "Couldn't save your choice. Please try again."); // Failed: plain message.
  revalidatePath("/billing"); // Refreshes the family billing page.
  return { message: "Thanks, your choice is saved." }; // Thanks them.
} // End of chooseBillingPlan.

// A family agrees to the billing terms.
export async function acceptBillingTerms(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const familyId = uuid.safeParse(formData.get("family_id")); // Reads and checks the family id.
  if (!familyId.success || formData.get("agree") !== "on") return { error: "Please tick the box to agree." }; // Bad id or box not ticked: asks them to tick it.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("billing_accept_terms", { p_family: familyId.data, p_version: FAMILY_TERMS_VERSION }); // Asks the database to save the agreement with the terms version.
  if (error) return plain(error, "Couldn't save your agreement. Please try again."); // Failed: plain message.
  revalidatePath("/billing"); // Refreshes the family billing page.
  return { message: "Thanks, your agreement is saved." }; // Thanks them.
} // End of acceptBillingTerms.

// Sends a family to Stripe's page to save a card or bank debit.
export async function setUpAutomaticPayment(formData: FormData) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const familyId = uuid.safeParse(formData.get("family_id")); // Reads and checks the family id.
  if (!familyId.success) return; // Bad id: does nothing.
  const account = await myFamilyAccount(familyId.data); // Reads the family's account (if they may see it).
  if (!account) redirect("/billing?setup=missing"); // None: back to billing saying so.
  if (!stripeKey()) redirect("/billing?setup=not-connected"); // Stripe not set up: back to billing saying so.

  // A second payer sharing the invoices saves their own card or bank debit.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: share } = await supabase // Checks whether this person is a second payer:
    .from("billing_payers") // in the payers table,
    .select("account_id") // (their account id)
    .eq("family_id", familyId.data) // for this family,
    .eq("account_id", viewer.id) // and this person,
    .maybeSingle(); // (one at most).

  // Stripe's references are kept away from the browser, so they are read
  // and saved with the server's own access, after the checks above.
  const db = createAdminClient(); // Connects with full access.
  let customer: string | null; // The Stripe customer to use.
  if (share) { // For a second payer:
    const { data: full } = await db // reads their Stripe customer:
      .from("billing_payers") // from the payers table,
      .select("stripe_customer_id") // (the customer id)
      .eq("family_id", familyId.data) // for this family,
      .eq("account_id", viewer.id) // and this person,
      .single(); // (one row).
    customer = (full?.stripe_customer_id as string | null) ?? null; // Their customer (or none).
    if (!customer) { // None yet:
      customer = (await createCustomer(viewer.fullName || "CLG family", viewer.email, familyId.data, viewer.id)).id; // makes one in Stripe,
      await db.from("billing_payers").update({ stripe_customer_id: customer }).eq("family_id", familyId.data).eq("account_id", viewer.id); // and saves it.
    } // End of making one.
  } else { // For the main bill payer:
    const { data: full } = await db // reads the family's Stripe customer:
      .from("billing_accounts") // from the billing accounts table,
      .select("stripe_customer_id") // (the customer id)
      .eq("family_id", familyId.data) // for this family,
      .single(); // (one row).
    customer = (full?.stripe_customer_id as string | null) ?? null; // Their customer (or none).
    if (!customer) { // None yet:
      customer = (await createCustomer(viewer.fullName || "CLG family", viewer.email, familyId.data)).id; // makes one in Stripe,
      await db.from("billing_accounts").update({ stripe_customer_id: customer }).eq("family_id", familyId.data); // and saves it.
    } // End of making one.
  } // End of the payer cases.
  const page = await createSetupPage({ // Makes Stripe's setup page:
    customer, // for this customer,
    familyId: familyId.data, // this family,
    payerId: share ? viewer.id : undefined, // this payer (second payers only),
    allowBankDebit: account.plan !== "weekly", // allowing bank debit except for weekly plans,
    returnUrl: `${siteUrl()}/billing`, // and coming back to the billing page.
  }); // End of the page.
  redirect(page.url); // Sends the family to it.
} // End of setUpAutomaticPayment.

// Sends a family to Stripe's page to pay one invoice now.
export async function payInvoiceNow(formData: FormData) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the invoice id.
  if (!id.success) return; // Bad id: does nothing.
  if (!stripeKey()) redirect("/billing?setup=not-connected"); // Stripe not set up: back to billing saying so.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  // Only an invoice this person can see, and only while it's unpaid.
  const { data: inv } = await supabase // Reads the invoice:
    .from("billing_invoices") // from the invoices table,
    .select("id, number, family_id, total_cents, status") // its id, number, family, total and stage,
    .eq("id", id.data) // this invoice,
    .eq("status", "open") // only if unpaid,
    .maybeSingle(); // (one at most).
  if (!inv?.family_id) redirect("/billing"); // Not found: back to billing.
  // What this person owes: the whole invoice, or their share of a split
  // one. The database only returns what they may see.
  const { data: owed } = await supabase.rpc("billing_invoice_payers", { p_invoice: inv.id }); // Reads what each payer owes on this invoice.
  const { data: shareRows } = await supabase.from("billing_invoice_shares").select("payer_id").eq("invoice_id", inv.id).limit(1); // Checks whether the invoice is split.
  const split = Boolean(shareRows?.length); // True if it is.
  const mine = (owed ?? []).find((o: { payer_id: string | null }) => !split || o.payer_id === viewer.id) as // This person's part (the whole invoice if not split):
    | { amount_cents: number; paid_cents: number; pending_cents: number } // (its shape)
    | undefined; // (or nothing).
  if (!mine) redirect("/billing"); // Nothing owed: back to billing.
  const left = mine.amount_cents - mine.paid_cents - mine.pending_cents; // What's left to pay.
  if (left <= 0) redirect("/billing?paid=processing"); // Nothing left (paid or in progress): back to billing saying so.

  const db = createAdminClient(); // Connects with full access.
  let customer: string | null = null; // The Stripe customer to use (none yet).
  if (split) { // Split invoices:
    const { data: p } = await db // reads this payer's Stripe customer:
      .from("billing_payers") // from the payers table,
      .select("stripe_customer_id") // (the customer id)
      .eq("family_id", inv.family_id) // for this family,
      .eq("account_id", viewer.id) // and this person,
      .maybeSingle(); // (one at most).
    customer = (p?.stripe_customer_id as string | null) ?? null; // Their customer (or none).
  } // End of the split case.
  if (!customer) { // No customer yet:
    const { data: acct } = await db.from("billing_accounts").select("stripe_customer_id, bill_payer_id").eq("family_id", inv.family_id).single(); // reads the family's account,
    if (!split || acct?.bill_payer_id === viewer.id) customer = (acct?.stripe_customer_id as string | null) ?? null; // uses the family's customer if not split or this is the bill payer.
  } // End of that case.
  const page = await createPayNowPage({ // Makes Stripe's pay-now page:
    customer, // for this customer,
    invoiceId: inv.id, // this invoice,
    invoiceNumber: inv.number, // its number,
    familyId: inv.family_id, // this family,
    payerId: split ? viewer.id : undefined, // this payer (split only),
    amountCents: left, // for what's left,
    returnUrl: `${siteUrl()}/billing`, // coming back to the billing page.
  }); // End of the page.
  redirect(page.url); // Sends them to it.
} // End of payInvoiceNow.

// ---------------------------------------------------------------------------
// Admin: split payments
// ---------------------------------------------------------------------------

// Sets up a split: another payer pays a share of a family's invoices.
export async function saveSplit(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const parsed = z // Checks the form has:
    .object({ family_id: uuid, payer_id: uuid, share: z.string() }) // a family, a payer and a share,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: "Choose who shares the payments and their share." }; // Problem: asks for them.
  const share = Number(parsed.data.share.replace("%", "").trim()); // Reads the share as a number (allowing a % sign).
  if (!Number.isInteger(share) || share < 1 || share > 99) return { error: "Enter the share as a whole number from 1 to 99, for example 50." }; // Must be a whole number from 1 to 99.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("billing_set_split", { // Asks the database to save the split:
    p_family: parsed.data.family_id, // for this family,
    p_payer: parsed.data.payer_id, // this payer,
    p_share: share, // this share.
  }); // End of the request.
  if (error) return plain(error, "Couldn't save the split."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
  return { message: "Split saved. It applies to invoices made from now on. Ask the other parent to set up their own automatic payment in the app." }; // Confirms, and says the other parent sets up their own payment.
} // End of saveSplit.

// Removes a split.
export async function removeSplit(formData: FormData) {
  await requireAdminLevel(FINANCE); // Owner, operations and finance admins.
  const family = uuid.safeParse(formData.get("family_id")); // Reads and checks the family id.
  const payer = uuid.safeParse(formData.get("payer_id")); // Reads and checks the payer id.
  if (!family.success || !payer.success) return; // Either bad: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("billing_remove_split", { p_family: family.data, p_payer: payer.data }); // Asks the database to remove the split.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page so it shows the change.
} // End of removeSplit.
