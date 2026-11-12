// Summary: makes a family account for someone and sends their invitation.
// Used by "Set up a family" and "Link another parent". Server only: never
// call it without first checking the person is CLG staff.

// Stops this file ever being sent to the browser, because it uses the secret key.
import "server-only";
// Reads the app's own web address, for the link in the email.
import { siteUrl } from "@/lib/env";
// The all-powerful database helper, needed to create accounts for others.
import { createAdminClient } from "@/lib/supabase/admin";

// The result: the new account's id and (if the email failed) a link to send by hand, or an error message.
export type Made = { userId: string; link: string | null } | { error: string };

// Makes the account and sends the invitation email. Until CLG's own email
// sender is set up, Supabase can't email families, so the admin gets the
// link to send themselves instead.
export async function makeAccount(email: string, data: Record<string, string>): Promise<Made> {
  const admin = createAdminClient(); // Connects with the secret key so accounts can be made.
  const redirectTo = `${siteUrl()}/login`; // After choosing a password, the person lands on the login page.
  const sent = await admin.auth.admin.inviteUserByEmail(email, { data, redirectTo }); // Tries to make the account and email the invite.
  if (!sent.error && sent.data.user) return { userId: sent.data.user.id, link: null }; // Worked: no link needed.
  if (sent.error) console.error("Family invitation email failed:", sent.error.code ?? sent.error.name, sent.error.message); // Notes the failure in the server log.

  // Second try: make the account and get the invite link without emailing it.
  const made = await admin.auth.admin.generateLink({ type: "invite", email, options: { data, redirectTo } });
  if (made.error || !made.data.user || !made.data.properties?.action_link) { // That failed too.
    console.error("Family invitation link failed:", made.error?.code, made.error?.message); // Notes it in the server log.
    return { error: "We couldn't make the account. Please check the details and try again." }; // Plain message for the admin.
  } // End of the failure case.
  return { userId: made.data.user.id, link: made.data.properties.action_link }; // Account made; admin sends this link themselves.
} // End of makeAccount.

// The sentence shown to the admin afterwards, depending on whether the email went.
export function sentText(email: string, link: string | null): string {
  return link // If there's a link, the email didn't go.
    ? ` The email couldn't be sent, because CLG's own email sender isn't set up yet. Copy this link and send it to ${email} yourself (for example by text or email). It works once, for a short time: ${link}` // Tells the admin to send the link.
    : ` We've emailed ${email} a link to choose a password.`; // Otherwise confirms the email went.
} // End of sentText.

