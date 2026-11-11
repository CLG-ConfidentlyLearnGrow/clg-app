// Summary: small shared pieces used by the app's forms: the shape of a form's
// reply, the current policy version, and a safety check on "go to" links.

// Shape returned by every form action, shown back on the form.
export type FormState = { error?: string; message?: string };

// What a form shows before it has been sent: no error and no message.
export const initialFormState: FormState = {};

// The version of the privacy policy and terms people agree to at sign-up.
// Changing it asks everyone to agree again.
export const POLICY_VERSION = "2026-11-draft";

// Only allow redirects to paths on this site, so a link can't send someone
// to another website after they sign in.
export function safeNextPath(next: string | null | undefined, fallback = "/dashboard"): string {
  // Refuses empty paths, paths not starting with "/", "//" (another site) and backslashes (tricks).
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.includes("\\")) {
    return fallback; // Goes to the safe default page instead.
  } // End of the safety check.
  return next; // The path is on this site, so it is used as asked.
} // End of safeNextPath.
