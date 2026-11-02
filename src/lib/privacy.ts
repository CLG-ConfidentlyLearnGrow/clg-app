// Shared labels for the privacy pages. See docs/features/privacy-laws-baseline.md.

export const PRIVACY_REQUEST_KINDS = [
  { id: "access", label: "See the information CLG holds", hint: "Most of it is in the download above. Ask here for anything else." },
  { id: "correction", label: "Fix something that's wrong", hint: "Say what is wrong and what it should be." },
  { id: "deletion", label: "Delete information", hint: "Say whose information. Some records must be kept by law, such as invoices (kept 7 years)." },
  { id: "restriction", label: "Stop or limit a use of information", hint: "Say which use you object to." },
  { id: "consent", label: "Withdraw a consent", hint: "Withdrawing consent for a child means CLG can no longer support them." },
  { id: "complaint", label: "Make a privacy complaint", hint: "CLG will acknowledge it and reply within 28 days." },
  { id: "other", label: "Something else about privacy", hint: "" },
] as const;

export type PrivacyRequestKind = (typeof PRIVACY_REQUEST_KINDS)[number]["id"];

export function requestKindLabel(kind: string): string {
  return PRIVACY_REQUEST_KINDS.find((k) => k.id === kind)?.label ?? kind;
}

export const REQUEST_STATUS_LABELS: Record<string, string> = {
  received: "Received",
  in_progress: "Being worked on",
  done: "Done",
  refused: "Refused",
};

// Where the people affected by a breach live, and who to tell there.
export const REGIONS = [
  { id: "AU", label: "Australia", regulator: "OAIC (Notifiable Data Breaches form)", url: "https://www.oaic.gov.au/privacy/notifiable-data-breaches" },
  { id: "NZ", label: "New Zealand", regulator: "Office of the Privacy Commissioner (NotifyUs)", url: "https://privacy.org.nz/responsibilities/privacy-breaches/notify-us/" },
  { id: "UK", label: "United Kingdom", regulator: "ICO, within 72 hr", url: "https://ico.org.uk/for-organisations/report-a-breach/" },
  { id: "EU", label: "European Union", regulator: "The data protection authority of the country, within 72 hr", url: "https://www.edpb.europa.eu/about-edpb/about-edpb/members_en" },
  { id: "CA", label: "Canada", regulator: "Office of the Privacy Commissioner of Canada (and Quebec CAI)", url: "https://www.priv.gc.ca/en/report-a-concern/report-a-privacy-breach-at-your-organization/" },
  { id: "US", label: "United States", regulator: "State attorney general where the law requires; FTC for children under 13", url: "https://www.ftc.gov/business-guidance/privacy-security" },
] as const;

// A date as "Mon 3 Nov 2026", Adelaide time.
export function plainDate(iso: string): string {
  const d = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(`${iso}T12:00:00+10:30`) : new Date(iso);
  return d.toLocaleDateString("en-AU", { timeZone: "Australia/Adelaide", weekday: "short", day: "numeric", month: "short", year: "numeric" });
}

export function plainDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-AU", {
    timeZone: "Australia/Adelaide",
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
  });
}
