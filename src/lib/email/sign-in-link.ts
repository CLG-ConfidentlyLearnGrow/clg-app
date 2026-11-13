// Summary: makes a one-time "set a password and sign in" link for someone who
// already has a CLG account, and emails it through Resend (the same way staff
// invitations go). Used when an admin adds or re-sends to existing staff, so
// an email always goes out instead of the app quietly doing nothing.
//
// Stops this file ever being sent to the browser, because it uses secret keys.
import "server-only";
// Makes a random id for each email, so every resend really is sent again.
import { randomUUID } from "node:crypto";
// The app's web address, for the page the link returns to.
import { siteUrl } from "@/lib/env";
// Checks email is set up, and sends the app's own emails through Resend.
import { emailIsSetUp, sendEmails } from "@/lib/email/send";
// The all-powerful database helper (secret key), needed to make sign-in links.
import { createAdminClient } from "@/lib/supabase/admin";

// What happened: "sent" when the email went; otherwise the link (if one was
// made) for the admin to pass on themselves, and the reason for the log.
export type SignInLinkResult =
  | { sent: true } // The email went.
  | { sent: false; link: string | null; problem: string }; // It didn't: the link to share (if any) and why.

// Emails a sign-in link to an existing account. The subject and message are
// chosen by the caller, so the email says why it was sent.
export async function emailSignInLink(email: string, subject: string, body: string): Promise<SignInLinkResult> {
  const admin = createAdminClient(); // Connects with full access (only the server can make links).
  // A password reset link works for everyone with an account: it lets them
  // choose a password and confirms their email if they never did. Making it
  // here doesn't send Supabase's own email, so Supabase's email limits don't
  // apply; we send it ourselves below.
  const made = await admin.auth.admin.generateLink({ // Makes the link:
    type: "recovery", // a password reset link,
    email, // for this email,
    options: { redirectTo: `${siteUrl()}/login` }, // returning to the login page if anything goes wrong.
  }); // End of making the link.
  const tokenHash = made.data?.properties?.hashed_token; // The link's one-time code.
  if (made.error || !tokenHash) { // Couldn't make it:
    return { sent: false, link: null, problem: `Couldn't make a link: ${made.error?.code ?? made.error?.message ?? "no code returned"}` }; // reports why.
  } // End of that case.

  // Our own "one more step" page uses the code when the person presses a
  // button, so email scanners that open links can't use it up first.
  const path = `/auth/continue?token_hash=${encodeURIComponent(tokenHash)}&type=recovery&next=/set-password`; // The page the button opens.
  const fullLink = `${siteUrl()}${path}`; // The full link, for the admin to copy if the email fails.
  if (!emailIsSetUp()) return { sent: false, link: fullLink, problem: "Email isn't set up yet." }; // No email key: hands back the link.

  const problem = await sendEmails([ // Sends one email:
    { // (the email:)
      id: `sign-in-link-${randomUUID()}`, // a fresh id each time, so a resend isn't skipped as a repeat,
      email, // to their address,
      first_name: null, // no greeting name (keeps it simple),
      subject, // the caller's subject line,
      body, // the caller's message,
      link: path, // the button opens the "one more step" page,
      button: "Set my password and sign in", // the button's words,
      footer: `This link is only for ${email}. It works once, for one hour, and only the newest link we've sent works. If you weren't expecting it, you can ignore this email.`, // small print on how the link works.
    }, // (end of the email)
  ]); // (end of the list)
  if (problem) return { sent: false, link: fullLink, problem }; // It didn't go: hands back the link and why.
  return { sent: true }; // It went.
} // End of emailSignInLink.
