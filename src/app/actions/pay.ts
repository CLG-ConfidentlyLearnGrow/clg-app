// Summary: tutor and staff pay: pay details, admin hours, working out pay,
// sending timesheets to Xero, the pay period, and staff logging their own
// hours for approval.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { PAY, requireAdminLevel, requireViewer } from "@/lib/auth"; // The pay admin group, and the sign-in and admin-level checks.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { xeroConfig } from "@/lib/billing/config"; // Checks whether Xero is set up.
import { parseDollars } from "@/lib/billing/money"; // Turns a typed price into cents.
import { WORK_CATEGORIES } from "@/lib/billing/work-categories"; // The kinds of work outside sessions (Carla, 18 Nov 2026).
import { listXeroEmployees, sendTimesheets } from "@/lib/billing/payroll"; // Reads Xero's employees, and sends draft timesheets to Xero Payroll.
import { xeroConnection } from "@/lib/billing/xero"; // Reads the stored Xero connection.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Tutor and staff pay. Every action re-checks admin access here, and the
// database checks again.

const PAGE = "/admin/billing"; // The billing admin page, refreshed after changes.
const uuid = z.uuid(); // The rule for a proper id.
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Choose a date."); // The rule for a date (YYYY-MM-DD).

// Turns a database error into a reply: its own plain message, or a general one.
function plain(error: { code?: string; message: string } | null, fallback: string): FormState {
  if (!error) return {}; // No error: nothing to report.
  const ours = ["42501", "22023", "23505", "23514"].includes(error.code ?? ""); // True for the database's own plain refusals.
  return { error: ours ? `${error.message}.` : fallback }; // Shows that message, or the general one.
} // End of plain.

// "" means not entered; otherwise dollars to cents. Undefined means invalid.
function rate(text: FormDataEntryValue | null): number | null | undefined {
  const t = String(text ?? "").trim(); // The typed text, without spaces at the ends.
  if (t === "") return null; // Blank: not entered.
  return parseDollars(t) ?? undefined; // Otherwise cents, or "invalid" if it isn't a price.
} // End of rate.

// Saves a staff member's pay details: employment type, rates, agreed hours and Xero links.
export async function saveStaffPay(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY); // Only owner and finance admins.
  const parsed = z // Checks the form has:
    .object({ // (the rules:)
      account_id: uuid, // whose pay,
      employment: z.enum(["casual", "part_time", "full_time"]), // casual, part-time or full-time,
      xero_employee_id: z.string().max(100).optional(), // their Xero employee id (optional),
      xero_school_rate_id: z.string().max(100).optional(), // their Xero school rate (optional),
      xero_tertiary_rate_id: z.string().max(100).optional(), // their Xero tertiary rate (optional),
      xero_admin_rate_id: z.string().max(100).optional(), // their Xero admin rate (optional).
    }) // (end of the rules)
    .safeParse(Object.fromEntries(formData)); // (from the form's fields)
  if (!parsed.success) return { error: "Please check the details." }; // Problem: plain message.
  const rates = { // The hourly rates, in cents:
    school_rate_cents: rate(formData.get("school_rate")), // school tutoring,
    tertiary_rate_cents: rate(formData.get("tertiary_rate")), // tertiary tutoring,
    admin_rate_cents: rate(formData.get("admin_rate")), // office admin.
  }; // End of the rates.
  if (Object.values(rates).some((r) => r === undefined)) { // Any rate typed wrongly:
    return { error: "Enter hourly rates in dollars, for example 34 or 62.88. Leave a rate empty if it does not apply." }; // shows an example.
  } // End of that check.
  // Agreed weekly hours, for part-time and full-time staff only.
  const agreed = String(formData.get("guaranteed_hours") ?? "").trim(); // The typed agreed hours.
  let guaranteed: number | null = null; // Agreed weekly minutes (none by default).
  if (parsed.data.employment !== "casual" && agreed !== "") { // Only for non-casual staff who typed hours:
    const h = Number(agreed.replace(",", ".")); // reads the number (allowing a comma as the decimal point),
    if (!Number.isFinite(h) || h < 0.25 || h > 60) return { error: "Enter agreed hours per week between 0.25 and 60, or leave it empty." }; // must be between 0.25 and 60 hours.
    guaranteed = Math.round(h * 60); // Stores it as minutes.
  } // End of agreed hours.
  const xero = (v?: string) => (v && v.trim() ? v.trim() : null); // Helper: a Xero id, or none if blank.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("billing_staff_pay").upsert({ // Saves (or replaces) the pay details:
    account_id: parsed.data.account_id, // whose pay,
    employment: parsed.data.employment, // employment type,
    ...rates, // the three rates,
    guaranteed_weekly_minutes: guaranteed, // agreed weekly minutes,
    ...(formData.has("xero_employee_id") // and, only if the Xero fields were on the form:
      ? { // (the Xero links)
          xero_employee_id: xero(parsed.data.xero_employee_id), // employee id,
          xero_school_rate_id: xero(parsed.data.xero_school_rate_id), // school rate,
          xero_tertiary_rate_id: xero(parsed.data.xero_tertiary_rate_id), // tertiary rate,
          xero_admin_rate_id: xero(parsed.data.xero_admin_rate_id), // admin rate.
        } // (end of the Xero links)
      : {}), // otherwise nothing.
  }); // End of the save.
  if (error) return plain(error, "Could not save the pay details."); // Failed: plain message.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  return { message: "Pay details saved. Pay already sent to Xero does not change. If you changed their employment type, agreed hours or a rate, make the same change to their employee record in Xero; it is on the Xero to-do list below." }; // Confirms, and reminds them to update Xero.
} // End of saveStaffPay.

// Ticks off a line on the Xero to-do list once Xero matches the app.
export async function markXeroTaskDone(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY); // Only owner and finance admins.
  const id = uuid.safeParse(formData.get("task_id")); // Checks the to-do's id.
  if (!id.success) return { error: "Please try again." }; // Problem: plain message.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("billing_xero_task_done", { p_task: id.data, p_how: "by_hand" }); // Asks the database to tick it off.
  if (error) return plain(error, "Could not tick it off. Please try again."); // Failed: plain message.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  return { message: "Ticked off." }; // Confirms.
} // End of markXeroTaskDone.

// Links every staff member who isn't linked yet to the Xero employee with
// the same email. Links someone already chose are never changed.
export async function linkXeroByEmail(): Promise<FormState> { // (The form sends nothing this needs.)
  await requireAdminLevel(PAY); // Only owner and finance admins.
  if (!xeroConfig() || !(await xeroConnection().catch(() => null))) return { error: "Connect Xero first (Stripe and Xero, above)." }; // Xero must be connected.
  let employees; // Xero's employee list.
  try { // Tries:
    employees = await listXeroEmployees(); // to read it.
  } catch (e) { // If Xero refused:
    return { error: `Could not read Xero's employees: ${(e as Error).message}` }; // says why.
  } // End of the try.
  const xeroByEmail = new Map(employees.filter((e) => e.Email).map((e) => [e.Email!.trim().toLowerCase(), e.EmployeeID])); // Each Xero employee's id, by email in lower case.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const [roles, emails] = await Promise.all([ // Reads two things at once:
    supabase.from("account_roles").select("account_id").in("role", ["tutor", "admin"]), // everyone who is a tutor or admin,
    supabase.from("account_private").select("account_id, email"), // and everyone's email.
  ]); // End of the reads.
  const staffIds = new Set((roles.data ?? []).map((r) => r.account_id)); // The staff, by id.
  const links = (emails.data ?? []) // Goes through the emails:
    .filter((e) => staffIds.has(e.account_id) && e.email) // keeps staff with an email,
    .map((e) => ({ account_id: e.account_id, xero_employee_id: xeroByEmail.get(e.email.trim().toLowerCase()) })) // finds their Xero employee by email,
    .filter((l) => l.xero_employee_id); // and keeps those with a match.
  if (links.length === 0) return { message: "Nobody new matched. Check their email is the same in the app and in Xero, or choose their Xero employee by hand." }; // Nothing matched: says what to check.
  const { data, error } = await supabase.rpc("billing_link_xero_employees", { p_links: links }); // Asks the database to save the links.
  if (error) return plain(error, "Could not link them. Please try again."); // Failed: plain message.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  return { message: `Linked ${data} ${data === 1 ? "person" : "people"} to Xero by email. Now choose their Xero earnings rates in Pay rates.` }; // Confirms, with the next step.
} // End of linkXeroByEmail.

// An admin records office admin hours for a staff member.
export async function addAdminTime(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY); // Only owner and finance admins.
  const parsed = z // Checks the form has:
    .object({ account_id: uuid, day, hours: z.string(), note: z.string().max(300).optional() }) // a person, a day, hours and an optional note,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: "Choose the person, the day and the hours." }; // Problem: asks for them.
  const hours = Number(parsed.data.hours.replace(",", ".")); // Reads the hours (allowing a comma).
  if (!Number.isFinite(hours) || hours <= 0) return { error: "Enter the hours, for example 1.5." }; // Not a positive number: shows an example.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("billing_add_admin_time", { // Asks the database to record:
    p_account: parsed.data.account_id, // for this person,
    p_day: parsed.data.day, // on this day,
    p_minutes: Math.round(hours * 60), // this many minutes,
    p_note: parsed.data.note ?? "", // with this note.
  }); // End of the request.
  if (error) return plain(error, "Could not record the admin hours."); // Failed: plain message.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  return { message: "Admin hours recorded." }; // Confirms it.
} // End of addAdminTime.

// Removes one pay line that hasn't gone to Xero.
export async function removePayLine(formData: FormData) {
  await requireAdminLevel(PAY); // Only owner and finance admins.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the line's id.
  if (!id.success) return; // Not a proper id: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("billing_remove_pay_line", { p_line: id.data }); // Asks the database to remove it.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
} // End of removePayLine.

// Works out pay lines for a period from confirmed session times.
export async function workOutPay(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY); // Only owner and finance admins.
  const parsed = z.object({ from: day, to: day }).safeParse(Object.fromEntries(formData)); // Checks the form has a start and end date.
  if (!parsed.success) return { error: "Choose the pay period." }; // Problem: asks for the period.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("billing_build_pay", { p_from: parsed.data.from, p_to: parsed.data.to }); // Asks the database to build the pay lines.
  if (error) return plain(error, "Could not work out pay."); // Failed: plain message.
  // Add summary-writing time for each completed session (before the agreed-hours check, so it counts).
  const summaries = await supabase.rpc("billing_build_summary_pay", { p_from: parsed.data.from, p_to: parsed.data.to }); // Builds the session summary pay lines.
  if (summaries.error) return plain(summaries.error, "Could not work out session summary pay."); // Failed: plain message.
  // Add compulsory training as hours waiting for approval (before the agreed-hours check, so it counts).
  const training = await supabase.rpc("billing_build_training_hours", { p_from: parsed.data.from, p_to: parsed.data.to }); // Adds training hours for the period.
  if (training.error) return plain(training.error, "Could not add training hours."); // Failed: plain message.
  // Add 1 hour at the tutor's rate for each term review CLG approved (Carla, 19 Nov 2026), before the agreed-hours check so it counts.
  const reviews = await supabase.rpc("billing_build_term_review_pay", { p_from: parsed.data.from, p_to: parsed.data.to }); // Builds the term review pay lines.
  if (reviews.error) return plain(reviews.error, "Could not work out term review pay."); // Failed: plain message.
  // Then check agreed hours for part-time and full-time staff (only once the pay period has ended).
  const topUps = await supabase.rpc("billing_check_guaranteed_hours", { p_day: parsed.data.to }); // Adds any guaranteed-hours top-ups for the period.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  const added = topUps.data ?? 0; // How many top-ups were added.
  return { // Tells the admin:
    message: `Pay worked out: ${data ?? 0} line(s) waiting to go to Xero.${added > 0 ? ` ${added} guaranteed hours top-up(s) are waiting for approval above.` : ""}`, // how many lines are waiting, and any top-ups to approve.
  }; // End of the message.
} // End of workOutPay.

// Sends draft timesheets for a pay period to Xero Payroll.
export async function sendTimesheetsNow(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY); // Only owner and finance admins.
  const start = day.safeParse(formData.get("period_start")); // Reads and checks the period's start date.
  if (!start.success) return { error: "Choose the pay period." }; // Problem: asks for the period.
  if (!xeroConfig() || !(await xeroConnection())) { // Xero not set up or connected:
    return { error: "Connect Xero first (Billing, Stripe and Xero tab). Wages are paid only through Xero Payroll, never Stripe. Until Xero is connected, use these lines to enter pay in Xero by hand." }; // explains pay goes only through Xero Payroll.
  } // End of that check.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  // Work it out again first so the latest confirmed times are used.
  const { data: period } = await supabase.rpc("billing_pay_period", { p_day: start.data }).single<{ period_start: string; period_end: string }>(); // Reads the pay period's first and last day.
  if (period) await supabase.rpc("billing_build_pay", { p_from: period.period_start, p_to: period.period_end }); // Works out pay again for that period.
  if (period) await supabase.rpc("billing_build_summary_pay", { p_from: period.period_start, p_to: period.period_end }); // And the session summary time for that period.
  if (period) await supabase.rpc("billing_build_term_review_pay", { p_from: period.period_start, p_to: period.period_end }); // And term reviews approved in that period.
  const result = await sendTimesheets(start.data); // Sends the timesheets.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  const done = `Sent ${result.sent} draft timesheet(s) to Xero Payroll. Check and approve them in Xero before the pay run.`; // What was done.
  return result.problems.length ? { error: `${done} Not sent: ${result.problems.join(" ")}` } : { message: done }; // Shows that with any problems, or just what was done.
} // End of sendTimesheetsNow.

// Saves the pay period settings.
export async function savePayPeriod(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY); // Only owner and finance admins.
  const parsed = z // Checks the form has:
    .object({ pay_period_days: z.enum(["7", "14"]), pay_period_anchor: day, casual_min_enabled: z.string().optional() }) // weekly or fortnightly, a start day, and the casual minimum tick box,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: "Choose weekly or fortnightly, and a day a pay period starts." }; // Problem: asks for them.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase // Saves:
    .from("billing_settings") // in the billing settings table,
    .update({ // the changes:
      pay_period_days: Number(parsed.data.pay_period_days), // days per period,
      pay_period_anchor: parsed.data.pay_period_anchor, // a day a period starts,
      casual_min_enabled: parsed.data.casual_min_enabled === "on", // whether the casual 2-hr minimum applies.
    }) // End of the changes.
    .eq("id", true) // (there's only one settings row)
    .select("id"); // and reports which row changed.
  if (error || !data?.length) return { error: "Only the owner can change the pay period." }; // Nothing saved: only the owner can change it.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  return { message: "Pay settings saved. The pay period must match the pay calendar in Xero. Use \"Work out pay again\" to apply a change to this period." }; // Confirms, with a reminder to match Xero's pay calendar.
} // End of savePayPeriod.

// ---------------------------------------------------------------------------
// Staff log their own admin hours; an admin approves or declines them.
// ---------------------------------------------------------------------------

// A staff member logs their own hours for approval, with the kind of work,
// what they did and what they finished or achieved (Carla, 18 Nov 2026).
export async function logMyHours(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const parsed = z // Checks the form has:
    .object({ // these fields:
      day, // a day,
      hours: z.string(), // the hours,
      note: z.string().max(300), // what they did,
      achieved: z.string().max(1000), // what they finished or achieved,
      category: z.string(), // the kind of work,
      session_id: z.union([uuid, z.literal("")]).optional(), // and the session (only for no-show time).
    }) // (end of the fields)
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: "Choose the kind of work, the day and the hours, and say what you did and achieved." }; // Problem: asks for them.
  const category = WORK_CATEGORIES.find((c) => c.id === parsed.data.category); // The kind of work chosen.
  if (!category) return { error: "Choose what kind of work it was." }; // None chosen: asks for it.
  if (category.type === "admin" && !viewer.roles.includes("admin")) return { error: "Only CLG admin staff can log office admin. Choose a kind of tutoring work instead." }; // Office admin is for admin staff only.
  if (parsed.data.note.trim().length < 10) return { error: "Please write what you did (at least a short sentence)." }; // Needs a description.
  if (parsed.data.achieved.trim().length < 10) return { error: "Please write what you finished or achieved in this time (at least a short sentence)." }; // Needs what was achieved.
  const session = parsed.data.session_id || null; // The session chosen (if any).
  if (category.id === "no_show_time" && !session) return { error: "Choose which session did not go ahead." }; // No-show time needs its session.
  const hours = Number(parsed.data.hours.replace(",", ".")); // Reads the hours (allowing a comma).
  if (!Number.isFinite(hours) || hours <= 0) return { error: "Enter the hours, for example 1.5." }; // Not a positive number: shows an example.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("billing_log_my_hours", { // Asks the database to log:
    p_day: parsed.data.day, // the day,
    p_minutes: Math.round(hours * 60), // the minutes,
    p_note: parsed.data.note, // what they did,
    p_category: category.id, // the kind of work,
    p_achieved: parsed.data.achieved, // what they achieved,
    p_session: category.id === "no_show_time" ? session : null, // and the session (only for no-show time).
  }); // End of the request.
  if (error) return plain(error, "Could not log the hours. Please try again."); // Failed: plain message.
  revalidatePath("/pay"); // Refreshes the staff pay page.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  return { // Confirms:
    message: category.id === "no_show_time" // for no-show time,
      ? "Saved. That time is already paid with the session, so CLG checks the work without paying it again." // that it is a record only,
      : "Hours logged. They are paid once CLG approves them.", // otherwise that they are paid once approved.
  }; // End of the confirmation.
} // End of logMyHours.

// A staff member takes back hours they logged (before approval).
export async function withdrawMyHours(formData: FormData) {
  await requireViewer(); // Makes sure someone is signed in.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the log's id.
  if (!id.success) return; // Not a proper id: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("billing_withdraw_my_hours", { p_log: id.data }); // Asks the database to withdraw it.
  revalidatePath("/pay"); // Refreshes the staff pay page.
  revalidatePath(PAGE); // Refreshes the billing page.
} // End of withdrawMyHours.

// An admin approves logged hours.
export async function approveHours(formData: FormData) {
  await requireAdminLevel(PAY); // Only owner and finance admins.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the log's id.
  if (!id.success) return; // Not a proper id: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("billing_review_hours", { p_log: id.data, p_approve: true }); // Asks the database to approve it.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  revalidatePath("/pay"); // Refreshes the staff pay page.
} // End of approveHours.

// An admin declines logged hours, with a reason.
export async function declineHours(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY); // Only owner and finance admins.
  const parsed = z.object({ id: uuid, reason: z.string().max(300) }).safeParse(Object.fromEntries(formData)); // Checks the form has an id and a reason.
  if (!parsed.success) return { error: "Please say why." }; // Problem: asks why.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("billing_review_hours", { p_log: parsed.data.id, p_approve: false, p_note: parsed.data.reason }); // Asks the database to decline it with the reason.
  if (error) return plain(error, "Could not decline the hours."); // Failed: plain message.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  revalidatePath("/pay"); // Refreshes the staff pay page.
  return { message: "Declined. They can see your reason on their pay page." }; // Confirms, noting the reason is shown to them.
} // End of declineHours.

// Saves a year's award minimum rates from an uploaded file (or pasted text).
// Each line: work, employment, hourly rate, award name. For example:
//   school,casual,33.50,Miscellaneous Award MA000104 Level 1 casual
// Staff below the new minimum are raised on the start date.
export async function uploadAwardRates(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY); // Only the owner and Finance admins.
  const effective = day.safeParse(formData.get("effective_from")); // Reads and checks the start date.
  if (!effective.success) return { error: "Choose the date the new rates start (usually 1 July)." }; // Problem: asks for the date.
  const file = formData.get("file"); // The uploaded file, if any.
  const pasted = String(formData.get("csv") ?? ""); // Any pasted text.
  const text = file instanceof File && file.size > 0 ? await file.text() : pasted; // Uses the file if there is one, otherwise the pasted text.
  if (text.length > 20000) return { error: "That file is too big. It should be a short list of rates." }; // Guards against the wrong file.
  const rows: { work_kind: string; employment: string; rate_cents: number; award: string }[] = []; // The rates found.
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean); // Each non-empty line.
  for (const [i, line] of lines.entries()) { // Goes through the lines one by one.
    const parts = line.split(",").map((p) => p.trim().replace(/^"|"$/g, "")); // Splits on commas and drops any quote marks.
    if (i === 0 && /work/i.test(parts[0] ?? "")) continue; // Skips the heading line.
    const [work, employment, amount, ...award] = parts; // The four columns (the award name may contain commas).
    const cents = parseDollars((amount ?? "").replace("$", "")); // Turns the rate into cents.
    if (!work || !employment || cents === null) { // A line that doesn't make sense:
      return { error: `Line ${i + 1} is not right: "${line}". Each line needs work, employment, hourly rate and award name.` }; // says which line.
    } // End of that check.
    rows.push({ work_kind: work.toLowerCase(), employment: employment.toLowerCase().replace("-", "_").replace(" ", "_"), rate_cents: cents, award: award.join(", ") }); // Adds the rate.
  } // End of the lines.
  if (rows.length === 0) return { error: "The file has no rates in it." }; // Nothing found.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("billing_upload_award_rates", { p_effective: effective.data, p_rows: rows }); // Saves the rates (and raises staff now if the date has come).
  if (error) return plain(error, "Could not save the award rates."); // Failed: plain message.
  revalidatePath(PAGE); // Refreshes the page so it shows the change.
  const raised = data ?? 0; // How many staff rates went up now.
  return { message: `${rows.length} award rate(s) saved from ${effective.data}.${raised > 0 ? ` ${raised} staff rate(s) raised to the new minimum.` : " Staff below the new minimum are raised on that date."}` }; // Tells the admin what happened.
} // End of uploadAwardRates.
