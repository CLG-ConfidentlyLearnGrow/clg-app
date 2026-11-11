// Summary: shared labels and date formats for the privacy pages: the kinds of
// privacy request people can make, their statuses, and who to tell about a
// data breach in each region. See docs/features/privacy-laws-baseline.md.

// The kinds of privacy request, each with its label and a hint shown under it.
export const PRIVACY_REQUEST_KINDS = [
  { id: "access", label: "See the information CLG holds", hint: "Most of it is in the download above. Ask here for anything else." }, // Asking to see their data.
  { id: "correction", label: "Fix something that's wrong", hint: "Say what is wrong and what it should be." }, // Asking to correct data.
  { id: "deletion", label: "Delete information", hint: "Say whose information. Some records must be kept by law, such as invoices (kept 7 years)." }, // Asking to delete data.
  { id: "restriction", label: "Stop or limit a use of information", hint: "Say which use you object to." }, // Objecting to a use.
  { id: "consent", label: "Withdraw a consent", hint: "Withdrawing consent for a child means CLG can no longer support them." }, // Taking back consent.
  { id: "complaint", label: "Make a privacy complaint", hint: "CLG will acknowledge it and reply within 28 days." }, // A complaint.
  { id: "other", label: "Something else about privacy", hint: "" }, // Anything else.
] as const; // "as const" keeps the exact ids so they can be type checked.

// The allowed request ids ("access", "correction" and so on), for type checking.
export type PrivacyRequestKind = (typeof PRIVACY_REQUEST_KINDS)[number]["id"];

// Turns a request id into its plain label, or shows the id if unknown.
export function requestKindLabel(kind: string): string {
  return PRIVACY_REQUEST_KINDS.find((k) => k.id === kind)?.label ?? kind; // Looks up the label; falls back to the id.
} // End of requestKindLabel.

// Plain words for each stage a privacy request can be at.
export const REQUEST_STATUS_LABELS: Record<string, string> = {
  received: "Received", // Just arrived.
  in_progress: "Being worked on", // Someone is handling it.
  done: "Done", // Finished.
  refused: "Refused", // Turned down (with a reason given elsewhere).
}; // End of the status labels.

// Where the people affected by a breach live, and who to tell there.
export const REGIONS = [
  { id: "AU", label: "Australia", regulator: "OAIC (Notifiable Data Breaches form)", url: "https://www.oaic.gov.au/privacy/notifiable-data-breaches" }, // Australia's privacy regulator.
  { id: "NZ", label: "New Zealand", regulator: "Office of the Privacy Commissioner (NotifyUs)", url: "https://privacy.org.nz/responsibilities/privacy-breaches/notify-us/" }, // New Zealand's regulator.
  { id: "UK", label: "United Kingdom", regulator: "ICO, within 72 hr", url: "https://ico.org.uk/for-organisations/report-a-breach/" }, // The UK's regulator.
  { id: "EU", label: "European Union", regulator: "The data protection authority of the country, within 72 hr", url: "https://www.edpb.europa.eu/about-edpb/about-edpb/members_en" }, // EU country regulators.
  { id: "CA", label: "Canada", regulator: "Office of the Privacy Commissioner of Canada (and Quebec CAI)", url: "https://www.priv.gc.ca/en/report-a-concern/report-a-privacy-breach-at-your-organization/" }, // Canada's regulator.
  { id: "US", label: "United States", regulator: "State attorney general where the law requires; FTC for children under 13", url: "https://www.ftc.gov/business-guidance/privacy-security" }, // US regulators.
] as const; // "as const" keeps the exact values fixed.

// A date as "Mon 3 Nov 2026", Adelaide time.
export function plainDate(iso: string): string {
  // A bare date (YYYY-MM-DD) is read as midday Adelaide time so it never slips a day; a full timestamp is read as-is.
  const d = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(`${iso}T12:00:00+10:30`) : new Date(iso);
  // Writes it the Australian way, e.g. "Mon 3 Nov 2026", in Adelaide's time zone.
  return d.toLocaleDateString("en-AU", { timeZone: "Australia/Adelaide", weekday: "short", day: "numeric", month: "short", year: "numeric" });
} // End of plainDate.

// A date and time as "Mon 3 Nov, 4:30 pm", Adelaide time.
export function plainDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-AU", { // Writes it the Australian way:
    timeZone: "Australia/Adelaide", // in Adelaide's time zone,
    weekday: "short", // with a short day name ("Mon"),
    day: "numeric", // the day number,
    month: "short", // a short month name ("Nov"),
    hour: "numeric", // the hour,
    minute: "2-digit", // and two-digit minutes.
  }); // End of the format settings.
} // End of plainDateTime.
