// Summary: money helpers and labels shared by the billing pages: showing cents
// as dollars, reading a typed price, and the plain names for payment plans,
// payment methods and invoice statuses. Amounts are whole cents throughout.

// The version of the family billing terms families accept in the app.
export const FAMILY_TERMS_VERSION = "2026-10-draft";

// Money helpers shared by the billing pages. Amounts are whole cents.

// Shows an amount in cents as Australian dollars, e.g. 9550 becomes "$95.50".
export function dollars(cents: number | null | undefined): string {
  const value = (cents ?? 0) / 100; // Turns cents into dollars (treating "none" as 0).
  return value.toLocaleString("en-AU", { style: "currency", currency: "AUD" }); // Formats it the Australian way.
} // End of dollars.

// "$95.50" or "95.5" typed by an admin, to cents. Null if it isn't a price.
export function parseDollars(text: string): number | null {
  const clean = text.replace(/[$,\s]/g, ""); // Removes dollar signs, commas and spaces.
  if (!/^\d+(\.\d{1,2})?$/.test(clean)) return null; // Must be a number with at most 2 decimal places.
  return Math.round(Number(clean) * 100); // Turns dollars into whole cents.
} // End of parseDollars.

// The plain name of each payment plan.
export const PLAN_LABELS = {
  weekly: "Weekly", // Paid each week.
  monthly: "Monthly", // Paid each month.
  term: "Per term", // Paid each school term.
  upfront: "Per year (upfront)", // Paid for the year in advance.
} as const; // "as const" keeps these names fixed.

// Payment plans are for ongoing tutoring only. One-off sessions, drafting and
// other single services are invoiced on their own.
export const PLAN_SCOPE_NOTE = "Payment plans (per year, term, month or week) are for ongoing tutoring only. One-off sessions and other single services are invoiced separately.";
// The allowed plan codes ("weekly", "monthly" and so on), for type checking.
export type BillingPlan = keyof typeof PLAN_LABELS;

// The plain name of each way of paying.
export const METHOD_LABELS = {
  none: "Not set up", // No payment method saved yet.
  card: "Card", // Pays by card.
  bank_debit: "Bank debit", // Pays by direct debit from a bank account.
} as const; // "as const" keeps these names fixed.
// The allowed method codes, for type checking.
export type BillingMethod = keyof typeof METHOD_LABELS;

// The plain name of each invoice stage.
export const STATUS_LABELS = {
  draft: "Draft", // Being prepared.
  awaiting_approval: "Waiting for approval in Xero", // In Xero, waiting for CLG to approve it.
  open: "Sent, waiting for payment", // Sent to the family, not yet paid.
  paid: "Paid", // Paid in full.
  void: "Cancelled", // Cancelled.
} as const; // "as const" keeps these names fixed.

// "2026-11-09" to "Mon 9 Nov 2026".
export function plainDate(day: string | null | undefined): string {
  if (!day) return ""; // No date gives blank text.
  const d = new Date(`${day}T00:00:00`); // Reads the date as the start of that day.
  return d.toLocaleDateString("en-AU", { weekday: "short", day: "numeric", month: "short", year: "numeric" }); // Writes it as "Mon 9 Nov 2026".
} // End of plainDate.
