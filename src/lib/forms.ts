// Shape returned by every form action, shown back on the form.
export type FormState = { error?: string; message?: string };

export const initialFormState: FormState = {};

// The version of the privacy policy and terms people agree to at sign-up.
export const POLICY_VERSION = "2026-10-draft";

// Only allow redirects to paths on this site.
export function safeNextPath(next: string | null | undefined, fallback = "/dashboard"): string {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.includes("\\")) {
    return fallback;
  }
  return next;
}
