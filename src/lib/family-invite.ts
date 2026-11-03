import "server-only";
import { siteUrl } from "@/lib/env";
import { createAdminClient } from "@/lib/supabase/admin";

// Making a family account for someone and sending their invitation. Used by
// "Set up a family" and "Link another parent". Server only: never call it
// without first checking the person is CLG staff.

export type Made = { userId: string; link: string | null } | { error: string };

// Makes the account and sends the invitation email. Until CLG's own email
// sender is set up, Supabase can't email families, so the admin gets the
// link to send themselves instead.
export async function makeAccount(email: string, data: Record<string, string>): Promise<Made> {
  const admin = createAdminClient();
  const redirectTo = `${siteUrl()}/login`;
  const sent = await admin.auth.admin.inviteUserByEmail(email, { data, redirectTo });
  if (!sent.error && sent.data.user) return { userId: sent.data.user.id, link: null };
  if (sent.error) console.error("Family invitation email failed:", sent.error.code ?? sent.error.name, sent.error.message);

  const made = await admin.auth.admin.generateLink({ type: "invite", email, options: { data, redirectTo } });
  if (made.error || !made.data.user || !made.data.properties?.action_link) {
    console.error("Family invitation link failed:", made.error?.code, made.error?.message);
    return { error: "We couldn't make the account. Please check the details and try again." };
  }
  return { userId: made.data.user.id, link: made.data.properties.action_link };
}

export function sentText(email: string, link: string | null): string {
  return link
    ? ` The email couldn't be sent, because CLG's own email sender isn't set up yet. Copy this link and send it to ${email} yourself (for example by text or email). It works once, for a short time: ${link}`
    : ` We've emailed ${email} a link to choose a password.`;
}

