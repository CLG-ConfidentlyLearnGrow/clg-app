// Summary: adds a tutor or admin role to someone, or makes and emails CLG's
// own staff invite link. Used by Admin > Staff > Add staff, and when an
// admin approves a tutor application (docs/features/tutor-applications.md).
//
// Stops this file ever being sent to the browser, because it sends emails and makes invite links.
import "server-only";
import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { ADMIN_LEVEL_NAMES, type AdminLevel } from "@/lib/auth"; // Admin level names (and the level type, for type checking).
import { emailIsSetUp, sendEmails } from "@/lib/email/send"; // Checks email is set up, and sends emails.
import { emailSignInLink } from "@/lib/email/sign-in-link"; // Emails a sign-in link to someone who already has an account.
import { siteUrl } from "@/lib/env"; // The app's web address, for invitation links.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Gives someone the tutor or admin role if they already have an account,
// otherwise makes and emails an invite link. The caller must already have
// checked the person is a full admin; the database checks again. Returns
// the message to show the admin.
export async function sendStaffInvite(email: string, role: "tutor" | "admin", level: Exclude<AdminLevel, "owner"> | null): Promise<FormState> {
  // Done through the admin's own session, so the database decides whether
  // this admin may invite this role.
  const supabase = await createClient(); // Connects to the database as the signed-in person.

  // Someone who already has a CLG account (for example a parent who also
  // tutors) gets the role straight away instead of an invitation.
  const existing = await supabase.rpc("grant_staff_role", { p_email: email, p_role: role, p_level: level }); // Gives the role now if they already have an account.
  const roleNow = role === "admin" ? `an admin (${ADMIN_LEVEL_NAMES[level ?? "operations"]})` : "a tutor"; // Their role in words, e.g. "a tutor".
  // Adding someone who already has this role used to stop with an error and
  // send nothing. Now it always emails them a fresh sign-in link instead, so
  // an admin can send to anyone as often as needed.
  if (existing.error?.code === "23505") { // They already have this role:
    const sent = await emailSignInLink( // emails them a sign-in link:
      email, // to their address,
      "Your CLG app sign-in link", // with this subject,
      `You already have a CLG app account as ${roleNow}. Use the button to choose a new password and sign in. If you remember your password, you can also just sign in as usual.`, // and this message.
    ); // End of sending.
    return signInLinkReply(email, sent, `${email} already has a CLG account as ${roleNow}, so we've emailed them a fresh link to set a password and sign in.`); // Tells the admin what happened.
  } // End of that case.
  if (existing.error) { // It failed:
    const plain = ["42501", "22023", "23505"].includes(existing.error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? `${existing.error.message}.` : "Couldn't add them. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  if (existing.data === true) { // They already had an account:
    revalidatePath("/admin"); // refreshes the admin pages,
    const sent = await emailSignInLink( // emails them so they know (this used to send nothing):
      email, // to their address,
      `You've been added to the CLG app as ${roleNow}`, // with this subject,
      `CLG Tutoring has added you to the CLG app as ${roleNow}. Sign in with your usual password, or use the button to choose a new one. Next you'll set up two-step login if you haven't already.`, // and this message.
    ); // End of sending.
    return signInLinkReply( // and tells the admin:
      email, // who,
      sent, // whether the email went,
      `${email} already had a CLG account, so they are now ${roleNow}. We've emailed them to let them know, with a link to sign in. They'll see the new tools after setting up two-step login.`, // what they now are, and that they've been emailed.
    ); // End of the reply.
  } // End of that case.

  // Everyone else gets CLG's own invite link: for this email and role only,
  // works once, for 7 days. Joining through it gives the role straight away.
  // A new link replaces any earlier one for the same email.
  const made = await supabase.rpc("create_staff_invite_link", { p_email: email, p_role: role, p_level: level }); // Makes the invite link's secret code.
  if (made.error || typeof made.data !== "string") { // It failed:
    const plain = ["42501", "22023", "23505"].includes(made.error?.code ?? ""); // true for the database's own plain refusals,
    if (made.error) console.error("Invite link failed:", made.error.code, made.error.message); // notes the failure in the server log,
    return { error: plain && made.error ? `${made.error.message}.` : "Couldn't make the invitation. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  const link = `${siteUrl()}/join?t=${made.data}`; // The full invite link.
  revalidatePath("/admin"); // Refreshes the admin pages.

  const roleWords = roleNow; // Their role in words, e.g. "a tutor".
  const problem = emailIsSetUp() // Sends the invitation email if email is set up:
    ? await sendEmails([ // sending one email:
        { // (the email:)
          id: `staff-invite-${made.data.slice(0, 16)}`, // an id for it,
          email, // to their address,
          first_name: null, // no first name yet,
          subject: `You're invited to join CLG Tutoring as ${roleWords}`, // the subject line,
          body: // the message:
            role === "tutor" // for tutors,
              ? "CLG Tutoring has invited you to join the CLG app as a tutor. Use the button to choose your name and password. The link works once, for 7 days. Next you'll set up two-step login and add your checks (Working with Children Check, RRHAN-EC and first aid), which CLG confirms before matching you with students." // explains the steps including checks,
              : "CLG Tutoring has invited you to join the CLG app as an admin. Use the button to choose your name and password. The link works once, for 7 days. Next you'll set up two-step login.", // for admins, explains the steps.
          link: `/join?t=${made.data}`, // the button opens the join page,
          button: "Accept invitation", // the button's words,
          footer: `This invitation is only for ${email}. If you weren't expecting it, you can ignore this email.`, // and small print saying it's only for them.
        }, // (end of the email)
      ]) // (end of the list)
    : "Email isn't set up yet."; // Email not set up: notes that as the problem.

  if (problem) { // The email didn't go:
    console.error("Invitation email failed:", problem); // notes why in the server log,
    return { // and gives the admin the link:
      message: `The invitation is ready, but the email couldn't be sent. Copy this link and send it to ${email} yourself (for example by email or Teams). It only works for ${email}, once, for 7 days: ${link}`, // (the message, with the link)
    }; // End of the message.
  } // End of that case.
  return { // The email went:
    message: `Invitation sent to ${email}. The link works once, for 7 days. When they join, they're ${roleWords} straight away. If it gets lost, add them again to send a new link (the old one stops working). It can take a few minutes; ask them to check their junk or spam folder too.`, // confirms it, explains how the link works, and mentions junk mail.
  }; // End of the message.
} // End of sendStaffInvite.

// Turns the result of emailing a sign-in link into the admin's reply: the
// success words if it went, or the link to pass on if it didn't.
function signInLinkReply(email: string, sent: Awaited<ReturnType<typeof emailSignInLink>>, ok: string): FormState {
  if (sent.sent) return { message: `${ok} It can take a few minutes; ask them to check their junk or spam folder too.` }; // It went: the success words, plus a junk-mail tip.
  console.error("Sign-in link email failed:", sent.problem); // Notes why in the server log.
  if (sent.link) { // A link was made, so the admin can pass it on:
    return { message: `The email couldn't be sent. Copy this link and send it to ${email} yourself (for example by Teams). It works once, for one hour: ${sent.link}` }; // (the message, with the link)
  } // End of that case.
  return { error: "We couldn't make a sign-in link. Please try again." }; // No link either: plain message.
} // End of signInLinkReply.
