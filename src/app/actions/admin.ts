// Summary: admin actions: inviting staff, cancelling invitations, confirming
// parent links, recording checks, assigning tutors, unlocking accounts,
// tutor work state, record holds and deletion, retention periods and more.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { ADMIN_LEVEL_NAMES, requireAdmin, requireAdminLevel } from "@/lib/auth"; // Admin level names, and the admin checks.
import { checkDates } from "@/lib/check-dates"; // Works out check expiry dates and spots mistakes.
import { CHECK_KINDS, STATES } from "@/lib/checks"; // The check kinds and Australian states.
import { siteUrl } from "@/lib/env"; // The app's web address, for invitation links.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { emailIsSetUp, sendEmails } from "@/lib/email/send"; // Checks email is set up, and sends emails.
import { emailSignInLink } from "@/lib/email/sign-in-link"; // Emails a sign-in link to someone who already has an account.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Every action re-checks admin access here, and the database checks again.

// The rules for inviting staff:
const inviteSchema = z.object({
  email: z.email("Enter a valid email address.").trim().toLowerCase(), // their email (tidied to lower case),
  role: z.enum(["tutor", "admin"]), // tutor or admin,
  // Only used for admins. The database refuses anyone but the owner.
  level: z.enum(["operations", "support", "finance"]).optional(), // the admin level (optional).
}); // End of the rules.

// Invites a tutor or admin (or gives the role straight away if they already have an account).
export async function inviteStaff(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  const parsed = inviteSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const { email, role } = parsed.data; // The checked values.
  const level = role === "admin" ? (parsed.data.level ?? "operations") : null; // The admin level (operations by default), only for admins.

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
} // End of inviteStaff.

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

const cancelSchema = z.object({ id: z.uuid() }); // The rules: one invitation id.

// Cancels an invitation nobody has used yet. Its link stops working.
export async function cancelInvitation(formData: FormData) {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = cancelSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return; // Problem with the form: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.from("invitations").delete().eq("id", parsed.data.id).is("accepted_at", null); // Deletes the invitation, only if not yet used.
  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  revalidatePath("/admin/staff"); // Refreshes the staff page.
} // End of cancelInvitation.

// Confirms a parent's link to a student.
export async function verifyParentLink(formData: FormData) {
  await requireAdmin(); // Makes sure the person is a full admin.
  const ids = z // Checks the form has:
    .object({ parent_id: z.uuid(), student_id: z.uuid() }) // a parent id and a student id,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!ids.success) return; // Problem: does nothing.

  const supabase = await createClient(); // Connects to the database.
  await supabase // Saves:
    .from("parent_student_links") // in the parent links table,
    .update({ verified_at: new Date().toISOString() }) // the time it was confirmed,
    .eq("parent_id", ids.data.parent_id) // for this parent,
    .eq("student_id", ids.data.student_id) // and this student,
    // Only the first press counts: a second press leaves the original
    // confirmation time alone.
    .is("verified_at", null); // only if not already confirmed.
  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
} // End of verifyParentLink.

// The rules for recording a tutor's check:
const checkSchema = z.object({
  tutor_id: z.uuid("Choose a tutor."), // which tutor,
  kind: z.enum(CHECK_KINDS), // which kind of check,
  reference: z.string().trim().max(100).optional(), // card or registration number (optional),
  completed_on: z.union([z.iso.date(), z.literal("")]).optional(), // date done (optional),
  expires_on: z.union([z.iso.date(), z.literal("")]).optional(), // expiry date (optional).
}); // End of the rules.

// An admin records a tutor's check (marked as verified by them).
export async function recordCheck(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = checkSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // A short name for the checked values.
  const dates = checkDates(v.kind, v.reference, v.completed_on || undefined, v.expires_on || undefined); // Works out the expiry and checks for mistakes.
  if ("error" in dates) return dates; // Problem: shows it.
  const expiresOn = dates.expiresOn; // The expiry date.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("tutor_checks").insert({ // Saves the check:
    tutor_id: v.tutor_id, // for this tutor,
    kind: v.kind, // this kind,
    reference: v.reference || null, // card number (or none),
    completed_on: v.completed_on || null, // date done (or none),
    expires_on: expiresOn, // expiry date.
  }); // End of the save.
  if (error) return { error: "Couldn't save the check. Please try again." }; // Failed: plain message.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: "Check saved and marked as verified by you." }; // Confirms it.
} // End of recordCheck.

// The rules for assigning a tutor:
const assignSchema = z.object({
  tutor_id: z.uuid("Choose a tutor and subject."), // which tutor,
  student_id: z.uuid("Choose a student."), // which student,
  subject: z.string().trim().min(1, "Enter the subject.").max(100), // which subject.
}); // End of the rules.

// Assigns a tutor to a student for a subject.
export async function assignTutor(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const [tutor_id, ...rest] = String(formData.get("pick") ?? "").split("|"); // Splits the picked "tutor|subject" choice.
  const parsed = assignSchema.safeParse({ // Checks against the rules:
    tutor_id, // the tutor,
    subject: rest.join("|"), // the subject (rejoined in case it contained "|"),
    student_id: formData.get("student_id"), // and the student.
  }); // End of the check.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("tutor_assignments").insert(parsed.data); // Saves the assignment.
  // The database explains why an assignment isn't allowed (checks missing,
  // parent link not yet verified).
  if (error) return { error: error.code === "23514" ? error.message : "Couldn't assign the tutor." }; // Shows the database's reason, or a general message.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: "Tutor assigned." }; // Confirms it.
} // End of assignTutor.

// Unlocks an account locked after too many sign-in tries.
export async function unlockAccount(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = z.email().trim().toLowerCase().safeParse(formData.get("email")); // Reads and checks the email.
  if (!parsed.success) return { error: "Enter a valid email address." }; // Problem: asks for a valid email.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const account = await supabase // Finds the account:
    .from("account_private") // in the private account details table,
    .select("account_id") // (its id)
    .eq("email", parsed.data) // by email,
    .maybeSingle(); // (one at most).
  if (!account.data) return { error: "No account with that email." }; // Not found: says so.

  const { error } = await supabase.rpc("admin_unlock_account", { p_account: account.data.account_id }); // Asks the database to unlock it.
  if (error) return { error: "Couldn't unlock the account." }; // Failed: plain message.
  // Unlocking sends no email, so the admin is told to let the person know
  // themselves, and where to send a password link if they've forgotten it.
  return { message: "Account unlocked. No email is sent for this: let them know they can sign in now with their usual password. If they've forgotten it, use \"Send a password link\" on the Staff page, or they can use \"Forgot your password?\" on the sign-in page." }; // Confirms it and explains what happens next.
} // End of unlockAccount.

// The rules for a tutor's work state:
const workStateSchema = z.object({
  tutor_id: z.uuid("Choose a tutor."), // which tutor,
  work_state: z.union([z.enum(STATES), z.literal("")]), // a state, or blank for none.
}); // End of the rules.

// The state a tutor works from adds that state's check to what they need.
export async function setTutorWorkState(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = workStateSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase // Saves:
    .from("tutor_work_settings") // in the tutor work settings table,
    .update({ work_state: parsed.data.work_state || null }) // the state (or none),
    .eq("tutor_id", parsed.data.tutor_id); // for this tutor.
  if (error) return { error: "Couldn't save the tutor's work state." }; // Failed: plain message.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: "Work state saved." }; // Confirms it.
} // End of setTutorWorkState.

// ---------------------------------------------------------------------------
// Keeping and deleting records (see supabase/migrations/*_retention.sql)
// ---------------------------------------------------------------------------

// The rules for a hold:
const holdSchema = z.object({
  target: z.string().regex(/^(student|account):[0-9a-f-]{36}$/, "Choose what to hold."), // what to hold, as "student:id" or "account:id",
  reason: z.string().trim().min(3, "Give a short reason.").max(300), // a short reason.
}); // End of the rules.

// Stops a student or account being deleted automatically, for example while
// a complaint or child safety matter is open.
export async function placeHold(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = holdSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const [kind, id] = parsed.data.target.split(":"); // Splits into kind and id.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase // Saves the hold:
    .from("retention_holds") // in the holds table,
    .insert({ [kind === "student" ? "student_id" : "account_id"]: id, reason: parsed.data.reason }); // on the student or account, with the reason.
  if (error) return { error: "Couldn't place the hold." }; // Failed: plain message.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: "Hold placed. These records won't be deleted until it is released." }; // Confirms it.
} // End of placeHold.

// Releases a hold, so normal deletion rules apply again.
export async function releaseHold(formData: FormData) {
  await requireAdmin(); // Makes sure the person is a full admin.
  const id = z.uuid().safeParse(formData.get("hold_id")); // Reads and checks the hold id.
  if (!id.success) return; // Bad id: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.from("retention_holds").update({ released_at: new Date().toISOString() }).eq("id", id.data); // Marks the hold as released now.
  revalidatePath("/admin"); // Refreshes the admin pages.
} // End of releaseHold.

// The rules for marking a tutor as finished:
const tutorLeftSchema = z.object({
  tutor_id: z.uuid("Choose a tutor."), // which tutor,
  ended_on: z.iso.date("Enter the date they finished."), // the date they finished.
}); // End of the rules.

// Marks a tutor as no longer working with CLG. This stops new assignments
// and starts the 7-year clock for their records.
export async function markTutorLeft(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = tutorLeftSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase // Saves:
    .from("tutor_profiles") // in the tutor profiles table,
    .update({ active: false, ended_on: parsed.data.ended_on }) // not active, with the end date,
    .eq("account_id", parsed.data.tutor_id); // for this tutor.
  if (error) return { error: "Couldn't update the tutor." }; // Failed: plain message.

  revalidatePath("/admin"); // Refreshes the admin pages.
  return { message: "Tutor marked as finished." }; // Confirms it.
} // End of markTutorLeft.

// The rules for erasing a student:
const eraseSchema = z.object({
  student_id: z.uuid("Choose a student."), // which student,
  confirm_name: z.string().trim().min(1, "Type the student's full name to confirm."), // their full name typed to confirm.
}); // End of the rules.

// Deletes a student's records straight away when the family asks. Owner only.
export async function eraseStudent(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (the database checks for the owner).
  const parsed = eraseSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("erase_student", { // Asks the database to erase the student:
    p_student: parsed.data.student_id, // this student,
    p_confirm_name: parsed.data.confirm_name, // with the typed name as a check.
  }); // End of the request.
  if (error) { // It failed:
    // The database gives a plain reason: wrong name, a hold, or not the owner.
    return { error: error.message || "Couldn't erase the student." }; // shows the database's reason, or a general message.
  } // End of the failure case.

  revalidatePath("/admin"); // Refreshes the admin pages.
  return { message: "The student's records have been deleted." }; // Confirms it.
} // End of eraseStudent.

// The rules for a keeping period:
const periodSchema = z.object({
  kind: z.enum(["student_records", "unused_accounts", "former_tutors", "activity_log"]), // which kind of record,
  months: z.coerce.number().int().min(1, "At least 1 month.").max(600), // how many months (1 to 600).
}); // End of the rules.

// Changes how long a kind of record is kept. Owner only; the database
// enforces this and logs the change.
export async function setRetentionPeriod(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = periodSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase // Saves:
    .from("retention_rules") // in the keeping rules table,
    .update({ keep_for: `${parsed.data.months} months` }) // the new period in months,
    .eq("kind", parsed.data.kind) // for this kind,
    .select("kind"); // and reads back the row to be sure it saved.
  if (error || !data?.length) return { error: "Couldn't change the period. Only the owner can do this." }; // Failed or nothing saved: only the owner can do this.

  revalidatePath("/admin"); // Refreshes the admin pages.
  return { message: "Period saved. It applies from tonight's run." }; // Confirms it.
} // End of setRetentionPeriod.

// A tutor's own check entry: confirm it after checking the official record,
// or send it back with a reason the tutor will see.
export async function confirmCheck(formData: FormData) {
  await requireAdmin(); // Makes sure the person is a full admin.
  const id = z.uuid().safeParse(formData.get("check_id")); // Reads and checks the check's id.
  if (!id.success) return; // Bad id: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("confirm_tutor_check", { p_check: id.data }); // Asks the database to confirm the check.
  revalidatePath("/admin"); // Refreshes the admin pages.
} // End of confirmCheck.

// Sends a tutor's check back with a reason.
export async function declineCheck(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = z // Checks the form:
    .object({ check_id: z.uuid(), reason: z.string().trim().min(3, "Give the tutor a short reason.").max(300) }) // a check id and a reason (3 to 300 characters),
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("decline_tutor_check", { p_check: parsed.data.check_id, p_reason: parsed.data.reason }); // Asks the database to send it back with the reason.
  if (error) return { error: "Couldn't send it back. Please try again." }; // Failed: plain message.
  revalidatePath("/admin"); // Refreshes the admin pages.
  return { message: "Sent back to the tutor with your reason." }; // Confirms it.
} // End of declineCheck.

// ---------------------------------------------------------------------------
// Admin levels
// ---------------------------------------------------------------------------

// The rules for changing an admin's level:
const levelSchema = z.object({
  account_id: z.uuid(), // which admin,
  level: z.enum(["operations", "support", "finance"], "Choose a level."), // the new level (not owner).
}); // End of the rules.

// The owner changes another admin's level. The database checks it's the
// owner, and that nobody changes the owner's own level.
export async function setAdminLevel(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is an admin (the database checks for the owner).
  const parsed = levelSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("set_admin_level", { // Asks the database to change the level:
    p_account: parsed.data.account_id, // for this admin,
    p_level: parsed.data.level, // to this level.
  }); // End of the request.
  if (error) { // It failed:
    const plain = ["42501", "22023"].includes(error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? `${error.message}.` : "Couldn't change the level. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  revalidatePath("/admin"); // Refreshes the admin pages.
  return { message: `Level changed to ${ADMIN_LEVEL_NAMES[parsed.data.level]}. It applies the next time they open a page.` }; // Confirms the new level and when it applies.
} // End of setAdminLevel.

// The owner's (or another admin's) name and email, read with the admin's
// own access, which the database allows for the owner and operations.
async function nameAndEmail(accountId: string) {
  const supabase = await createClient(); // Connects to the database.
  const [account, contact] = await Promise.all([ // Reads two things at once:
    supabase.from("accounts").select("full_name").eq("id", accountId).maybeSingle(), // their name,
    supabase.from("account_private").select("email").eq("account_id", accountId).maybeSingle(), // and their email.
  ]); // End of the reads.
  return { name: account.data?.full_name ?? "", email: contact.data?.email ?? null }; // Gives back the name (or blank) and email (or nothing).
} // End of nameAndEmail.

// Writes a time as Adelaide time, e.g. "Monday 3 November, 9:00 am".
function adelaideTime(iso: string) {
  return new Date(iso).toLocaleString("en-AU", { // Turns the time into words:
    timeZone: "Australia/Adelaide", // in Adelaide's time zone,
    weekday: "long", // the full day name,
    day: "numeric", // the day number,
    month: "long", // the full month name,
    hour: "numeric", // the hour,
    minute: "2-digit", // and minutes with two digits.
  }); // End of the settings.
} // End of adelaideTime.

// The rules for an emergency access request:
const requestSchema = z.object({
  reason: z // the reason must be:
    .string() // text,
    .trim() // (tidied of extra spaces)
    .min(10, "Please write why you need owner access (at least 10 characters).") // at least 10 characters,
    .max(1000, "Please keep the reason under 1000 characters."), // and under 1000.
}); // End of the rules.

// An Operations admin asks for emergency owner access. The owner is emailed
// straight away with the reason, and can cancel or approve within 24 hours.
export async function requestEmergencyAccess(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireAdmin(); // Makes sure the person is an admin, and gets who they are.
  const parsed = requestSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database.
  const { data: id, error } = await supabase.rpc("request_emergency_owner_access", { p_reason: parsed.data.reason }); // Asks the database to record the request (it checks the level).
  if (error || typeof id !== "string") { // It failed:
    const plain = ["42501", "22023", "23505"].includes(error?.code ?? ""); // true for the database's own plain refusals,
    return { error: plain && error ? `${error.message}.` : "Couldn't send the request. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  revalidatePath("/admin"); // Refreshes the admin pages.

  const { data: row } = await supabase.from("emergency_owner_access").select("starts_at").eq("id", id).maybeSingle(); // Reads when the access would start.
  const startsAt = row?.starts_at ? adelaideTime(row.starts_at) : "in 24 hours"; // That time in words, or "in 24 hours".
  const { data: owners } = await supabase.from("admin_profiles").select("account_id").eq("level", "owner"); // Finds the owner (or owners).
  const ownerContacts = await Promise.all((owners ?? []).map((o) => nameAndEmail(o.account_id))); // Gets each owner's name and email.
  const emails = ownerContacts // Builds the emails:
    .filter((o) => o.email) // only for owners with an email,
    .map((o) => ({ // each one:
      id: `emergency-access-${id}-${o.email}`, // an id for it,
      email: o.email as string, // their address,
      first_name: o.name.split(" ")[0] || null, // their first name (or none),
      subject: `${viewer.fullName || "An admin"} has asked for emergency owner access`, // the subject line, naming who asked,
      body: `${viewer.fullName || "An Operations admin"} has asked for owner access to the CLG app because you may be unreachable. Their reason: "${parsed.data.reason}". If you do nothing, they get owner powers from ${startsAt} (Adelaide time) for 7 days. Open the app under Admin > Staff and accounts to cancel it, or to approve it so it starts now.`, // the message: who asked, why, and when access starts unless cancelled,
      link: "/admin?section=staff", // the button opens the staff section,
      button: "Review the request", // the button's words,
      footer: "You get this email because you are the owner of the CLG app.", // and small print saying why they got it.
    })); // End of the emails.
  const problem = emails.length === 0 ? "No owner email found." : emailIsSetUp() ? await sendEmails(emails) : "Email isn't set up yet."; // Sends them, or notes why they couldn't be sent.
  if (problem) { // Something went wrong with the email:
    console.error("Emergency access email failed:", problem); // notes why in the server log,
    return { // and tells the admin:
      message: `Request sent. The owner will see it in the app, but the email to them couldn't be sent, so please also try to reach them another way. Your access starts ${startsAt} unless they cancel.`, // the request went in, but to reach the owner another way too.
    }; // End of the message.
  } // End of that case.
  return { message: `Request sent and the owner has been emailed. Your access starts ${startsAt} unless they cancel, and lasts 7 days.` }; // All sent: confirms it, and when access starts.
} // End of requestEmergencyAccess.

const cancelRequestSchema = z.object({ id: z.uuid() }); // The rules: one request id.

// The owner approves a waiting request, so owner access starts now
// instead of after 24 hours. It still ends by itself after 7 days.
export async function approveEmergencyAccess(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner"]); // Owner only.
  const parsed = cancelRequestSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: "Something went wrong. Please refresh the page." }; // Problem: asks them to refresh.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("approve_emergency_owner_access", { p_id: parsed.data.id }); // Asks the database to approve the request.
  if (error) { // It failed:
    const plain = ["42501", "22023"].includes(error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? `${error.message}.` : "Couldn't approve it. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  revalidatePath("/admin"); // Refreshes the admin pages.
  return { message: "Approved. Owner access has started and ends by itself in 7 days." }; // Confirms it.
} // End of approveEmergencyAccess.

// The owner cancels emergency access (or the person who asked withdraws it).
// The person who asked is emailed when someone else cancels it.
export async function cancelEmergencyAccess(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireAdminLevel(["owner", "operations"]); // Owner or operations admins only, and gets who they are.
  const parsed = cancelRequestSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: "Something went wrong. Please refresh the page." }; // Problem: asks them to refresh.
  const supabase = await createClient(); // Connects to the database.
  const { data: askedBy, error } = await supabase.rpc("cancel_emergency_owner_access", { p_id: parsed.data.id }); // Asks the database to cancel it, and gets who asked for it.
  if (error) { // It failed:
    const plain = ["42501", "22023"].includes(error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? `${error.message}.` : "Couldn't cancel it. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  revalidatePath("/admin"); // Refreshes the admin pages.
  if (typeof askedBy === "string" && askedBy !== viewer.id) { // Someone else asked for it:
    const who = await nameAndEmail(askedBy); // gets their name and email,
    if (who.email && emailIsSetUp()) { // if they have an email and email is set up:
      const problem = await sendEmails([ // sends one email:
        { // (the email:)
          id: `emergency-access-cancelled-${parsed.data.id}`, // an id for it,
          email: who.email, // their address,
          first_name: who.name.split(" ")[0] || null, // their first name (or none),
          subject: "Your emergency owner access was cancelled", // the subject line,
          body: `${viewer.fullName || "The owner"} has cancelled your request for emergency owner access in the CLG app. Your own admin access hasn't changed.`, // the message: who cancelled it, and that their own access is unchanged,
          link: "/admin", // the button opens the admin page,
          button: "Open the app", // the button's words.
        }, // (end of the email)
      ]); // (end of the list)
      if (problem) console.error("Emergency access cancel email failed:", problem); // Notes any problem in the server log.
    } // End of the email case.
  } // End of the "someone else" case.
  return { message: "Emergency owner access cancelled." }; // Confirms it.
} // End of cancelEmergencyAccess.
