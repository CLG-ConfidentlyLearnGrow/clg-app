import type { EmailOtpType } from "@supabase/supabase-js";

// The kinds of one-time link Supabase puts in its emails.
const EMAIL_LINK_TYPES: EmailOtpType[] = ["signup", "invite", "magiclink", "recovery", "email_change", "email"];

export function isEmailLinkType(type: unknown): type is EmailOtpType {
  return typeof type === "string" && (EMAIL_LINK_TYPES as string[]).includes(type);
}
