// Summary: the server actions for personal and team learnings (Carla, 22 Nov
// 2026). Staff write, change, remove and suggest their own learnings; the
// owner and Operations admins adapt suggestions into team learnings, decline
// them, and change or remove team learnings. The database checks every rule
// again. See docs/features/learnings.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in (the database checks the rest).
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message. Messages the database wrote
// for people (codes 42501, 22023 and P0002) are shown as they are; anything
// else gets the general message given.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the database error and a general message.
  return ["42501", "22023", "P0002"].includes(error.code ?? "") ? error.message : fallback; // The database's own words, or the general message.
} // End of plainError.

// The rules for a learning's words.
const wordsSchema = z.object({ // The form's fields:
  id: z.union([z.literal(""), z.uuid()]).default(""), // which learning (blank for a new one),
  title: z.string().trim().min(3, "Please give the learning a short title.").max(200, "Please keep the title under 200 characters."), // the title,
  body: z.string().trim().min(2, "Please write what you learned.").max(3000, "Please keep it under 3000 characters."), // the learning.
}); // End of the rules.

// Runs one database request and gives back the form reply.
async function run(name: string, args: Record<string, unknown>, done: string): Promise<FormState> { // Takes the function, its inputs, and the thank you message.
  await requireViewer(); // Makes sure someone is signed in.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc(name, args); // Asks the database.
  if (error) return { error: plainError(error, "We could not save this. Please try again.") }; // Failed: plain message.
  revalidatePath("/learnings"); // Refreshes the page.
  return { message: done }; // Confirms.
} // End of run.

// Adds or changes one of the person's own learnings.
export async function saveLearning(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = wordsSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!p.success) return { error: p.error.issues[0].message }; // Shows the first rule that failed.
  return run("learning_save", { p_id: p.data.id || null, p_title: p.data.title, p_body: p.data.body }, "Saved."); // Saves it.
} // End of saveLearning.

// Removes one of the person's own learnings.
export async function removeLearning(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const id = z.uuid().safeParse(formData.get("id")); // Reads and checks the id.
  if (!id.success) return { error: "Could not read which learning this is." }; // Bad id: plain message.
  return run("learning_remove", { p_id: id.data }, "Removed."); // Removes it.
} // End of removeLearning.

// Suggests one of the person's own learnings for the team.
export async function suggestLearning(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const id = z.uuid().safeParse(formData.get("id")); // Reads and checks the id.
  if (!id.success) return { error: "Could not read which learning this is." }; // Bad id: plain message.
  return run("learning_suggest", { p_id: id.data }, "Thank you. Carla and Emma have been told."); // Suggests it.
} // End of suggestLearning.

// Adapts a suggestion into a team learning (or adds a team learning with no suggestion).
export async function adoptLearning(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = wordsSchema.safeParse(Object.fromEntries(formData)); // Checks the form (id is the suggestion, if any).
  if (!p.success) return { error: p.error.issues[0].message }; // Shows the first rule that failed.
  return run("learning_adopt", { p_source: p.data.id || null, p_title: p.data.title, p_body: p.data.body }, "Added to the team learnings."); // Adds it.
} // End of adoptLearning.

// Declines a suggestion with a note.
export async function declineLearning(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = z.object({ id: z.uuid(), note: z.string().trim().max(1000, "Please keep the note under 1000 characters.").optional() }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!p.success) return { error: p.error.issues[0].message }; // Shows the first rule that failed.
  return run("learning_decline", { p_source: p.data.id, p_note: p.data.note || null }, "Declined. They have been told kindly."); // Declines it.
} // End of declineLearning.

// Changes a team learning.
export async function saveTeamLearning(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = wordsSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!p.success || !p.data.id) return { error: p.success ? "Could not read which learning this is." : p.error.issues[0].message }; // Shows the problem.
  return run("team_learning_save", { p_id: p.data.id, p_title: p.data.title, p_body: p.data.body }, "Saved."); // Saves it.
} // End of saveTeamLearning.

// Removes a team learning.
export async function removeTeamLearning(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const id = z.uuid().safeParse(formData.get("id")); // Reads and checks the id.
  if (!id.success) return { error: "Could not read which learning this is." }; // Bad id: plain message.
  return run("team_learning_remove", { p_id: id.data }, "Removed from the team learnings."); // Removes it.
} // End of removeTeamLearning.
