// Summary: the server actions for end-of-day updates (Carla, 22 Nov 2026).
// Admin staff send or correct their update for a day; CLG's owner marks
// updates as read. The database checks every rule again.
// See docs/features/end-of-day-updates.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireAdminLevel, requireViewer } from "@/lib/auth"; // The admin level check, and the signed-in check.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message. Messages the database wrote
// for people (codes 42501 and 22023) are shown as they are; anything else
// gets the general message given.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the database error and a general message.
  return ["42501", "22023"].includes(error.code ?? "") ? error.message : fallback; // The database's own words, or the general message.
} // End of plainError.

// Sends or corrects the signed-in admin's update for a day.
export async function saveDayUpdate(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in (the database checks they are admin staff).
  const parsed = z.object({ // The rules:
    work_date: z.iso.date("Please choose the day."), // the day,
    did: z.string().trim().min(2, "Please write what you did, one dot point per line.").max(3000, "Please keep what you did under 3000 characters."), // what they did,
    went_well: z.string().trim().max(2000, "Please keep what went well under 2000 characters.").optional(), // what went well,
    not_well: z.string().trim().max(2000, "Please keep what did not go well under 2000 characters.").optional(), // and what did not.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("admin_day_update_save", { p_date: d.work_date, p_did: d.did, p_went_well: d.went_well || null, p_not_well: d.not_well || null }); // Asks the database to save it.
  if (error) return { error: plainError(error, "We could not send your update. Please try again.") }; // Failed: plain message.
  revalidatePath("/updates"); // Refreshes the page.
  return { message: "Sent. Thank you." }; // Confirms.
} // End of saveDayUpdate.

// The owner marks updates as read.
export async function markDayUpdatesRead(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(["owner"]); // Must be the owner, with two-step sign-in.
  const ids = z.array(z.uuid()).safeParse(formData.getAll("id")); // Reads and checks the updates' ids.
  if (!ids.success || ids.data.length === 0) return { error: "There is nothing to mark as read." }; // Nothing to do: plain message.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("admin_day_updates_mark_read", { p_ids: ids.data }); // Asks the database to mark them.
  if (error) return { error: plainError(error, "We could not save this. Please try again.") }; // Failed: plain message.
  revalidatePath("/updates"); // Refreshes the page.
  return { message: "Marked as read." }; // Confirms.
} // End of markDayUpdatesRead.
