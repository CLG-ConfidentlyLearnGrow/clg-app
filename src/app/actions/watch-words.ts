// Summary: the server actions for concerning-words flags. The Child Safety
// Officer and the deputy record what they decided about a flag; they and
// the owner add, turn off, turn on and remove words on the list. The
// database checks every one of these rules again (two-step sign-in, and
// never a flag on their own writing).
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { CATEGORY_LABELS } from "@/lib/watch-words"; // The kinds of risk, for checking the one chosen.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The kinds of risk the database accepts, for checking the form.
const CATEGORIES = Object.keys(CATEGORY_LABELS) as [string, ...string[]]; // e.g. self_harm, abuse ...

// Turns a database refusal into a plain message. Messages the database
// wrote for people (refusal codes 42501 and 22023) are shown as they are;
// a repeated phrase (code 23505) and a bad "*" (code 23514) get their own
// message; anything else gets the general message given.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the database error and a general message.
  if (error.code === "23505") return "That word or phrase is already on the list."; // The same phrase twice.
  if (error.code === "23514") return "Please use at least two letters, and only put a * at the end of a word."; // Failed a rule on the phrase.
  return ["42501", "22023"].includes(error.code ?? "") ? error.message : fallback; // The database's own words, or the fallback.
} // End of plainError.

// ---------------------------------------------------------------------------
// Reviewing a flag (officer or deputy)
// ---------------------------------------------------------------------------

// Records what the reviewer decided about a flag, with a note.
export async function reviewWordFlag(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ // The rules for the form:
    id: z.uuid(), // which flag,
    status: z.enum(["new", "following_up", "no_concern", "raised_concern"], { message: "Please choose what you decided." }), // the decision,
    note: z.string().trim().max(2000, "Please keep the note under 2000 characters."), // and the note.
  }).safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("safety_word_flag_review", { p_id: parsed.data.id, p_status: parsed.data.status, p_note: parsed.data.note }); // Saves the decision.
  if (error) return { error: plainError(error, "We couldn't save that. Please try again.") }; // Failed: plain message.
  revalidatePath("/safety/flags"); // Refreshes the flags page.
  revalidatePath("/", "layout"); // Refreshes the top bar's number.
  return { message: "Saved." }; // Confirms.
} // End of reviewWordFlag.

// ---------------------------------------------------------------------------
// The word list (officer, deputy and owner)
// ---------------------------------------------------------------------------

// Adds a word or phrase to the list.
export async function addWatchWord(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ // The rules for the form:
    phrase: z.string().trim().min(2, "Please type a word or phrase (at least two letters).").max(100, "Please keep it under 100 characters."), // the word or phrase,
    category: z.enum(CATEGORIES, { message: "Please choose what kind of risk it may point to." }), // the kind of risk,
    urgent: z.literal("on").optional(), // the "email straight away" tick,
    staff_only: z.literal("on").optional(), // the "only when staff write it" tick,
    note: z.string().trim().max(300, "Please keep the note under 300 characters.").optional(), // and a note.
  }).safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("safety_watch_words").insert({ // Adds the word:
    phrase: d.phrase, // the word or phrase,
    category: d.category, // the kind of risk,
    urgent: d.urgent === "on", // whether to email straight away,
    staff_only: d.staff_only === "on", // whether only staff writing it counts,
    note: d.note || null, // and the note (if any).
  }); // End of the add.
  if (error) return { error: plainError(error, "We couldn't add that. Please check you used two-step sign-in and try again.") }; // Failed: plain message.
  revalidatePath("/safety/flags"); // Refreshes the page with the list.
  return { message: `Added "${d.phrase}". New writing is checked for it from now on.` }; // Confirms.
} // End of addWatchWord.

// Turns a word on or off (kept on the list either way). Used by a plain button, so it gives nothing back.
export async function setWatchWordActive(formData: FormData): Promise<void> { // Takes the button's form.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ id: z.uuid(), active: z.enum(["true", "false"]) }).safeParse(Object.fromEntries(formData)); // Checks the word's id and the new setting.
  if (!parsed.success) return; // A bad request: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.from("safety_watch_words").update({ active: parsed.data.active === "true" }).eq("id", parsed.data.id); // Saves the setting (the database checks who may).
  revalidatePath("/safety/flags"); // Refreshes the page with the list.
} // End of setWatchWordActive.

// Removes a word from the list. Flags it already made are kept. Used by a plain button, so it gives nothing back.
export async function removeWatchWord(formData: FormData): Promise<void> { // Takes the button's form.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ id: z.uuid() }).safeParse(Object.fromEntries(formData)); // Checks the word's id.
  if (!parsed.success) return; // A bad request: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.from("safety_watch_words").delete().eq("id", parsed.data.id); // Removes it (the database checks who may).
  revalidatePath("/safety/flags"); // Refreshes the page with the list.
} // End of removeWatchWord.
