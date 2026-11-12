// Summary: the staff directory module: job titles, adding and removing
// roles, and sending staff sign-in or invitation links.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { inviteStaff } from "@/app/actions/admin"; // Sends staff invitation links.
import { requireAdmin, requireAdminLevel } from "@/lib/auth"; // Makes sure the person is a full admin, or an admin at the right level.
import { siteUrl } from "@/lib/env"; // The app's web address, for links in emails.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createAdminClient } from "@/lib/supabase/admin"; // The all-powerful database helper (secret key).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Staff directory module: job titles, roles and links. Every action checks
// the admin's level here, and the database checks again.

// The rules for the job title form:
const titleSchema = z.object({
  account_id: z.uuid(), // whose title,
  job_title: z.string().trim().max(80, "Keep the job title to 80 characters or fewer."), // the title (up to 80 letters; blank removes it).
}); // End of the rules.

// Saves (or removes) a staff member's job title.
export async function setJobTitle(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  const parsed = titleSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const { account_id, job_title } = parsed.data; // The checked values.
  if (job_title.length === 1) return { error: "A job title needs at least 2 characters." }; // One letter isn't a title.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("set_staff_job_title", { p_account: account_id, p_title: job_title }); // Asks the database to save it.
  if (error) { // It failed:
    const plain = ["42501", "22023"].includes(error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? `${error.message}.` : "Couldn't save the job title. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  revalidatePath("/admin/staff"); // Refreshes the staff page.
  return { message: job_title ? "Saved" : "Removed" }; // Confirms saved or removed.
} // End of setJobTitle.

// ---------------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------------

const ROLE_WORDS: Record<string, string> = { tutor: "tutor", admin: "admin", parent: "parent", student: "student" }; // The word for each role in messages.

// The rules for adding a role:
const addSchema = z.object({
  account_id: z.uuid(), // whose account,
  role: z.enum(["tutor", "admin", "parent"], "Choose a role to add."), // tutor, admin or parent,
  level: z.enum(["operations", "support", "finance"]).optional(), // and the admin level (only for admins).
}); // End of the rules.

// Owner or operations gives a staff member another role. Only the owner can
// add admins; the database checks this again.
export async function addRole(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  const parsed = addSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const { account_id, role } = parsed.data; // The checked values.
  const level = role === "admin" ? (parsed.data.level ?? "operations") : null; // The admin level (operations by default), only for admins.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("admin_add_role", { p_account: account_id, p_role: role, p_level: level }); // Asks the database to add the role.
  if (error) { // It failed:
    const plain = ["42501", "22023", "23505"].includes(error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? `${error.message}.` : "Couldn't add the role. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  revalidatePath("/admin/staff"); // Refreshes the staff page.
  revalidatePath("/admin"); // Refreshes the admin pages.
  const extra = // An extra note for the message:
    role === "tutor" // for tutors,
      ? " They'll need confirmed checks before they're matched with students." // checks are needed before matching,
      : role === "admin" // for admins,
        ? " They'll see the admin tools next time they open a page (two-step login needed)." // two-step login is needed,
        : " Any child they add needs an admin to confirm the link."; // for parents, children need confirming.
  return { message: `Added the ${ROLE_WORDS[role]} role.${extra}` }; // Confirms the role was added, with the note.
} // End of addRole.

// The rules for removing a role:
const removeSchema = z.object({
  account_id: z.uuid(), // whose account,
  role: z.enum(["tutor", "admin", "parent", "student"], "Choose a role to remove."), // which role,
  confirm_name: z.string().trim().min(1, "Type the person's full name to confirm."), // their full name typed to confirm.
}); // End of the rules.

// The owner takes away one role. Records are kept under the usual keeping
// rules (see docs/features/remove-roles-delete-accounts.md).
export async function removeRole(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner"]); // Owner only.
  const parsed = removeSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const { account_id, role, confirm_name } = parsed.data; // The checked values.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("admin_remove_role", { // Asks the database to remove the role:
    p_account: account_id, // from this account,
    p_role: role, // this role,
    p_confirm_name: confirm_name, // with the typed name as a check.
  }); // End of the request.
  if (error) { // It failed:
    const plain = ["42501", "22023", "23514"].includes(error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? `${error.message}.` : "Couldn't remove the role. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  revalidatePath("/admin/staff"); // Refreshes the staff page.
  revalidatePath("/admin"); // Refreshes the admin pages.
  return { message: `Removed the ${ROLE_WORDS[role]} role. Their records are kept under the usual keeping rules.` }; // Confirms, noting records are kept.
} // End of removeRole.

// ---------------------------------------------------------------------------
// Links
// ---------------------------------------------------------------------------

const accountSchema = z.object({ account_id: z.uuid() }); // The rules: one account id.

// Emails a staff member a link to sign in: a link to choose their password
// if they've never signed in, otherwise a password reset link. If the email
// can't be sent, the admin gets the link to pass on themselves.
export async function sendStaffLoginLink(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  const parsed = accountSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: "Something went wrong. Please refresh the page and try again." }; // Problem: asks to refresh.

  // Checked with the admin's own access first: only staff in the directory.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data } = await supabase.rpc("staff_directory"); // Reads the staff directory (only staff the admin can see).
  const person = ((data ?? []) as { account_id: string; full_name: string; email: string | null }[]).find( // Finds this person in it:
    (p) => p.account_id === parsed.data.account_id, // by account id.
  ); // End of the search.
  if (!person) return { error: "That person isn't in the staff directory." }; // Not found: says so.
  if (!person.email) return { error: `We don't have an email for ${person.full_name}.` }; // No email: says so.
  const email = person.email; // Their email.

  const admin = createAdminClient(); // Connects with full access.
  const user = await admin.auth.admin.getUserById(person.account_id); // Reads their sign-in account.
  if (user.error || !user.data.user) return { error: "We couldn't check that account. Please try again." }; // Couldn't read it: plain message.
  const confirmed = Boolean(user.data.user.email_confirmed_at); // True once they've confirmed their email.
  const neverSignedIn = !user.data.user.last_sign_in_at; // True if they've never signed in.
  const redirectTo = `${siteUrl()}/login`; // After choosing a password, they land on the login page.

  const sent = confirmed // Sends the right email:
    ? await admin.auth.resetPasswordForEmail(email, { redirectTo }) // a password reset if confirmed,
    : await admin.auth.admin.inviteUserByEmail(email, { redirectTo }); // otherwise a fresh invitation.
  if (!sent.error) { // It sent:
    return { // tells the admin:
      message: neverSignedIn // if never signed in,
        ? `We've emailed ${email} a new link to choose a password and sign in.` // a new link to choose a password,
        : `We've emailed ${email} a link to set a new password.`, // otherwise a link to set a new password.
    }; // End of the message.
  } // End of the sent case.
  console.error("Staff login link email failed:", sent.error.code ?? sent.error.name, sent.error.message); // Notes the email failure in the server log.

  const made = await admin.auth.admin.generateLink( // Makes the link without emailing it:
    confirmed ? { type: "recovery", email, options: { redirectTo } } : { type: "invite", email, options: { redirectTo } }, // a reset link if confirmed, otherwise an invitation link.
  ); // End of making the link.
  if (made.error || !made.data.properties?.action_link) { // That failed too:
    console.error("Staff login link failed:", made.error?.code, made.error?.message); // notes it in the server log,
    return { error: "We couldn't make a new link. Please try again." }; // and tells the admin plainly.
  } // End of the failure case.
  return { // Gives the admin the link to send themselves:
    message: `The email couldn't be sent. Copy this link and send it to ${email} yourself (for example by Teams). It works once, for a short time: ${made.data.properties.action_link}`, // (the message, with the link)
  }; // End of the message.
} // End of sendStaffLoginLink.

const inviteIdSchema = z.object({ id: z.uuid() }); // The rules: one invitation id.

// Sends a new invitation link to someone who hasn't joined yet. Same as
// adding them again under "Add staff": the old link stops working.
export async function resendStaffInvite(prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = inviteIdSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: "Something went wrong. Please refresh the page and try again." }; // Problem: asks to refresh.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: inv } = await supabase // Reads the invitation:
    .from("invitations") // from the invitations table,
    .select("email, role, admin_level") // its email, role and admin level,
    .eq("id", parsed.data.id) // this invitation,
    .is("accepted_at", null) // only if not yet used,
    .maybeSingle(); // (one at most).
  if (!inv) return { error: "That invitation has been used or cancelled. Refresh the page." }; // Used or cancelled: says so.

  const again = new FormData(); // Builds a fresh form:
  again.set("email", inv.email as string); // with the email,
  again.set("role", inv.role as string); // the role,
  if (inv.role === "admin" && inv.admin_level) again.set("level", inv.admin_level as string); // and the admin level, for admins.
  const result = await inviteStaff(prev, again); // Sends it through the normal "Add staff" step (the old link stops working).
  revalidatePath("/admin/staff"); // Refreshes the staff page.
  return result; // Passes on the result.
} // End of resendStaffInvite.
