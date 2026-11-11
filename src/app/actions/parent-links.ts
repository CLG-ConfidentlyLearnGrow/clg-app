// Summary: CLG links more than one parent or guardian to a student, removes
// a link, and sorts out double-ups (the same child added twice).
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { FRONT_DESK, requireAdminLevel } from "@/lib/auth"; // The front-desk admin group, and the admin-level check.
import { makeAccount, sentText } from "@/lib/family-invite"; // Makes a family account and words the "sent" message.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// CLG links more than one parent or guardian to a student, removes a link,
// and sorts out double-ups (the same child added twice).
// The database checks who may do each of these. See docs/features/link-parents.md.

const RELATIONSHIPS = ["parent", "guardian", "carer", "other"] as const; // The ways someone can be related to a student.

// The rules for the link form:
const linkSchema = z.object({
  student_id: z.uuid("Choose a student."), // which student,
  email: z.email("Enter the parent's email address.").trim().toLowerCase(), // the parent's email (tidied to lower case),
  contact_name: z.string().trim().max(200).optional(), // their name (needed only for a new account),
  relationship: z.enum(RELATIONSHIPS, "Choose how they're related to the student."), // and how they're related.
}); // End of the rules.

type Found = { account_id: string; full_name: string; is_parent: boolean; is_student: boolean }; // One account found by email: id, name, and whether they're a parent or student.

// Plain words for the database's own error messages.
function plain(error: { code?: string; message: string }, fallback: string) {
  return error.code === "22023" ? `${error.message}.` : fallback; // The database's own message, or the general one.
} // End of plain.

// Links a parent to a student, making their account first if needed.
export async function linkParent(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FRONT_DESK); // Front desk admins and above.
  const parsed = linkSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const canManage = formData.get("can_manage") === "on"; // Whether they can manage the student's details (tick box).

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const lookup = await supabase.rpc("admin_find_account", { p_email: v.email }); // Looks up the email.
  if (lookup.error) return { error: "We couldn't check that email. Please try again." }; // Lookup failed: plain message.
  const found = ((lookup.data ?? []) as Found[])[0]; // The first match (if any).

  let parentId: string; // The parent's account id.
  let parentName: string; // The parent's name.
  let link: string | null = null; // The invite link to send by hand, if the email failed.
  let isNew = false; // Whether a new account was made.
  if (found) { // Account already exists:
    parentId = found.account_id; // uses its id,
    parentName = found.full_name; // and name.
  } else { // No account yet:
    if (!v.contact_name) { // no name given:
      return { error: `No one uses ${v.email} for CLG yet. Enter the parent's full name too, and we'll make their account.` }; // asks for the name too.
    } // End of that case.
    const made = await makeAccount(v.email, { signup_as: "parent", full_name: v.contact_name }); // Makes the account and sends the invitation.
    if ("error" in made) return made; // Failed: passes on the message.
    parentId = made.userId; // The new account's id.
    parentName = v.contact_name; // The name typed.
    link = made.link; // Any link to send by hand.
    isNew = true; // Marks it as new.
  } // End of the account step.

  const res = await supabase.rpc("admin_link_parent", { // Asks the database to link them:
    p_parent: parentId, // this parent,
    p_student: v.student_id, // to this student,
    p_relationship: v.relationship, // related this way,
    p_can_manage: canManage, // and whether they can manage details.
  }); // End of the request.
  if (res.error) { // Linking failed:
    console.error("Linking a parent failed:", res.error.code, res.error.message); // notes why in the server log,
    const start = isNew ? `The account for ${v.email} was made, but` : ""; // mentions the account was made, if it was,
    return { error: `${start} we couldn't link them. ${plain(res.error, "Please try again.")}`.trim() }; // and explains plainly.
  } // End of the failure case.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { // Tells the admin:
    message: isNew // if new,
      ? `Account made for ${parentName} and linked to the student.${sentText(v.email, link)}` // the account was made and linked, plus how the invite was sent,
      : `${parentName} is now linked to the student. They'll see them next time they sign in.`, // otherwise that the parent is linked.
  }; // End of the message.
} // End of linkParent.

const pairSchema = z.object({ parent_id: z.uuid(), student_id: z.uuid() }); // The rules for a parent-and-student pair: two ids.

// Removes a parent's link to a student.
export async function unlinkParent(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FRONT_DESK); // Front desk admins and above.
  const parsed = pairSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: "Something went wrong. Please refresh and try again." }; // Problem: asks to refresh.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const res = await supabase.rpc("admin_unlink_parent", { // Asks the database to remove the link:
    p_parent: parsed.data.parent_id, // this parent,
    p_student: parsed.data.student_id, // from this student.
  }); // End of the request.
  if (res.error) return { error: plain(res.error, "We couldn't remove the link. Please try again.") }; // Failed: plain message.
  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: "Link removed. They no longer see this student." }; // Confirms it.
} // End of unlinkParent.

const mergeSchema = z.object({ keep: z.uuid(), remove: z.uuid() }); // The rules for merging: the profile to keep, and the one to remove.

// Merges two profiles of the same child into one.
export async function mergeStudents(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FRONT_DESK); // Front desk admins and above.
  const parsed = mergeSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: "Something went wrong. Please refresh and try again." }; // Problem: asks to refresh.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const res = await supabase.rpc("admin_merge_students", { p_keep: parsed.data.keep, p_remove: parsed.data.remove }); // Asks the database to merge them.
  if (res.error) { // Failed:
    console.error("Merging students failed:", res.error.code, res.error.message); // notes why in the server log,
    return { error: plain(res.error, "We couldn't merge them. Please try again.") }; // and explains plainly.
  } // End of the failure case.
  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: "Merged. Every parent now sees the one profile." }; // Confirms it.
} // End of mergeStudents.

const dismissSchema = z.object({ student_id: z.uuid(), other_id: z.uuid() }); // The rules for "these are different children": two student ids.

// Notes that two look-alike profiles are different children.
export async function dismissDuplicate(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FRONT_DESK); // Front desk admins and above.
  const parsed = dismissSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: "Something went wrong. Please refresh and try again." }; // Problem: asks to refresh.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const res = await supabase.rpc("admin_dismiss_duplicate", { // Asks the database to note it:
    p_student: parsed.data.student_id, // this student,
    p_other: parsed.data.other_id, // and the other one.
  }); // End of the request.
  if (res.error) return { error: "We couldn't save that. Please try again." }; // Failed: plain message.
  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: "Noted as different children. They won't be flagged again." }; // Confirms they won't be flagged again.
} // End of dismissDuplicate.
