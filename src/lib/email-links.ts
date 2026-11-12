// Summary: checks whether a word in an email link is one of the link kinds
// Supabase sends (sign-up, invite, password reset and so on), so the app only
// acts on links it knows how to handle.

// Brings in the list of link kinds Supabase defines, for type checking only.
import type { EmailOtpType } from "@supabase/supabase-js";

// The kinds of one-time link Supabase puts in its emails.
const EMAIL_LINK_TYPES: EmailOtpType[] = ["signup", "invite", "magiclink", "recovery", "email_change", "email"];

// Answers "is this one of the link kinds above?" so odd or tampered links are ignored.
export function isEmailLinkType(type: unknown): type is EmailOtpType {
  // True only for text that exactly matches one of the known link kinds.
  return typeof type === "string" && (EMAIL_LINK_TYPES as string[]).includes(type);
} // End of isEmailLinkType.
