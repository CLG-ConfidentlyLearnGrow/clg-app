// The version of the family billing terms families accept in the app.
export const FAMILY_TERMS_VERSION = "2026-10-draft";

// Money helpers shared by the billing pages. Amounts are whole cents.

export function dollars(cents: number | null | undefined): string {
  const value = (cents ?? 0) / 100;
  return value.toLocaleString("en-AU", { style: "currency", currency: "AUD" });
}

// "$95.50" or "95.5" typed by an admin, to cents. Null if it isn't a price.
export function parseDollars(text: string): number | null {
  const clean = text.replace(/[$,\s]/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(clean)) return null;
  return Math.round(Number(clean) * 100);
}

export const PLAN_LABELS = {
  weekly: "Weekly",
  monthly: "Monthly",
  term: "Per term",
  upfront: "Upfront",
} as const;
export type BillingPlan = keyof typeof PLAN_LABELS;

export const METHOD_LABELS = {
  none: "Not set up",
  card: "Card",
  bank_debit: "Bank debit",
} as const;
export type BillingMethod = keyof typeof METHOD_LABELS;

export const STATUS_LABELS = {
  draft: "Draft",
  awaiting_approval: "Waiting for approval in Xero",
  open: "Sent, waiting for payment",
  paid: "Paid",
  void: "Cancelled",
} as const;

// "2026-11-09" to "Mon 9 Nov 2026".
export function plainDate(day: string | null | undefined): string {
  if (!day) return "";
  const d = new Date(`${day}T00:00:00`);
  return d.toLocaleDateString("en-AU", { weekday: "short", day: "numeric", month: "short", year: "numeric" });
}
