// Summary: the server actions for "What's new" (Carla, 15 Nov 2026).
// Anyone signed in can close the pop-up on their own dashboards. Full admins
// (owner and operations) write updates, add changes tagged by dashboard,
// publish them (now or from a chosen day) and take them back. The database
// checks every one of these rules again.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message. Messages the database wrote
// for people (codes 42501 and 22023) are shown as they are; anything else
// gets the general message.
function plainError(error: { code?: string; message: string }): string { // Takes the database error.
  return ["42501", "22023"].includes(error.code ?? "") ? error.message : "We couldn't save that. Please try again."; // The database's own words, or the general message.
} // End of plainError.

// The four dashboards, for checking form answers.
const roleSchema = z.enum(["admin", "tutor", "parent", "student"]); // only these four.

// Refreshes the pages that show updates.
function refresh() { // No inputs.
  revalidatePath("/admin/whats-new"); // The admin page.
  revalidatePath("/whats-new"); // The "What's new" page.
} // End of refresh.

// Notes that the signed-in person closed the pop-up on one dashboard, so it
// doesn't show again until there's another update. Called by the pop-up.
export async function markWhatsNewSeen(role: string): Promise<void> { // Takes the dashboard.
  const parsed = roleSchema.safeParse(role); // Checks it's a real dashboard.
  if (!parsed.success) return; // Not one: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("whats_new_mark_seen", { p_role: parsed.data }); // Saves the time (the database checks it's their dashboard).
} // End of markWhatsNewSeen.

// Starts a new draft update, or renames a draft.
export async function saveWhatsNewNote(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ // The rules:
    id: z.union([z.uuid(), z.literal("")]).optional(), // which update (empty for a new one),
    title: z.string().trim().min(2, "Please give the update a short title.").max(120, "Please keep the title under 120 characters."), // its title.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("whats_new_save_note", { p_id: parsed.data.id || null, p_title: parsed.data.title }); // Saves it.
  if (error) return { error: plainError(error) }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: parsed.data.id ? "Saved." : "Draft started. Add its changes below." }; // Confirms.
} // End of saveWhatsNewNote.

// Adds a change to a draft, or edits one.
export async function saveWhatsNewItem(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ // The rules:
    note: z.uuid(), // which update,
    id: z.union([z.uuid(), z.literal("")]).optional(), // which change (empty for a new one),
    kind: z.enum(["added", "updated", "removed"], { message: "Please choose New, Updated or Removed." }), // the kind,
    body: z.string().trim().min(3, "Please say what changed.").max(500, "Please keep each change under 500 characters."), // what changed.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const roles = z.array(roleSchema).safeParse(formData.getAll("roles")); // The ticked dashboards (a form can send several).
  if (!roles.success || roles.data.length === 0) return { error: "Please tick at least one dashboard this change is for." }; // None ticked.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("whats_new_save_item", { p_note: d.note, p_id: d.id || null, p_kind: d.kind, p_roles: roles.data, p_body: d.body }); // Saves it.
  if (error) return { error: plainError(error) }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: d.id ? "Saved." : "Change added." }; // Confirms.
} // End of saveWhatsNewItem.

// Removes a change from a draft.
export async function deleteWhatsNewItem(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("id")); // Which change.
  if (!id.success) return { error: "That change can't be found." }; // No valid id.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("whats_new_delete_item", { p_id: id.data }); // Removes it.
  if (error) return { error: plainError(error) }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Change removed." }; // Confirms.
} // End of deleteWhatsNewItem.

// Deletes a draft update.
export async function deleteWhatsNewNote(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("id")); // Which update.
  if (!id.success) return { error: "That update can't be found." }; // No valid id.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("whats_new_delete_note", { p_id: id.data }); // Deletes it.
  if (error) return { error: plainError(error) }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Draft deleted." }; // Confirms.
} // End of deleteWhatsNewNote.

// Publishes a draft, now or from a chosen day (Adelaide time).
export async function publishWhatsNewNote(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ // The rules:
    id: z.uuid(), // which update,
    showOn: z.union([z.iso.date({ message: "Please choose a real date, or leave it empty to publish now." }), z.literal("")]).optional(), // the optional start day.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("whats_new_publish", { p_id: parsed.data.id, p_show_on: parsed.data.showOn || null }); // Publishes it.
  if (error) return { error: plainError(error) }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: parsed.data.showOn ? "Published. It starts showing on the day you chose." : "Published. People will see it next time they open that dashboard." }; // Confirms.
} // End of publishWhatsNewNote.

// Takes a published update back to a draft (it stops showing).
export async function unpublishWhatsNewNote(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("id")); // Which update.
  if (!id.success) return { error: "That update can't be found." }; // No valid id.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("whats_new_unpublish", { p_id: id.data }); // Takes it back.
  if (error) return { error: plainError(error) }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Back to a draft. It's hidden until you publish it again." }; // Confirms.
} // End of unpublishWhatsNewNote.
