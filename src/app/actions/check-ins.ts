// Summary: the server actions for the check-ins after a new match. The
// tutor, parents and learner answer (or skip) a check-in that is waiting for
// them; full admins mark a flagged answer as followed up. The database checks
// every one of these rules again. See docs/features/match-check-ins.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message. Messages the database wrote
// for people (codes 42501 and 22023) are shown as they are; anything else
// gets the general message given.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the database error and a general message.
  return ["42501", "22023"].includes(error.code ?? "") ? error.message : fallback; // The database's own words, or the general message.
} // End of plainError.

// The rules for the check-in form:
const answerSchema = z.object({ // Each field and its rule:
  tutor: z.uuid(), // the tutor in the match,
  student: z.uuid(), // the learner in the match,
  stage: z.enum(["1", "2", "6"]), // which check-in,
  skip: z.enum(["yes"]).optional(), // "yes" when skipping,
  rating: z.union([z.enum(["1", "2", "3", "4", "5"]), z.literal("")]).optional(), // how it is going,
  fit: z.union([z.enum(["yes", "unsure", "no"]), z.literal("")]).optional(), // whether it is a good fit,
  contact: z.enum(["yes"]).optional(), // "yes" when they would like CLG to contact them,
  comment: z.string().trim().max(2000, "Please keep your comment under 2000 characters.").optional(), // anything else.
}); // End of the rules.

// Saves an answer to a check-in, or a skip.
export async function answerCheckIn(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = answerSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const skip = d.skip === "yes"; // True when they chose to skip.
  if (!skip && !d.rating) return { error: "Please choose how it is going, from 1 to 5." }; // No rating chosen.
  if (!skip && !d.fit) return { error: "Please choose yes, not sure yet or no." }; // No fit answer chosen.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("answer_check_in", { // Asks the database to save it:
    p_tutor: d.tutor, // the tutor,
    p_student: d.student, // the learner,
    p_stage: Number(d.stage), // the check-in,
    p_rating: skip ? null : Number(d.rating), // the rating (none when skipping),
    p_fit: skip ? null : d.fit, // the fit (none when skipping),
    p_wants_contact: d.contact === "yes", // whether they would like CLG to contact them,
    p_comment: skip ? null : d.comment || null, // the comment (none when skipping),
    p_skip: skip, // and whether they are skipping.
  }); // End of the request.
  if (error) return { error: plainError(error, "We could not save that. Please try again.") }; // Failed: plain message.
  revalidatePath("/", "layout"); // Refreshes every page, so the card disappears wherever it was showing.
  if (skip) return { message: "Skipped. Thank you." }; // Confirms a skip.
  return { message: d.contact === "yes" ? "Thank you. Someone from CLG will be in touch soon." : "Thank you for letting us know." }; // Thanks them.
} // End of answerCheckIn.

// Marks a flagged answer as followed up (or opens it again), with a private note.
export async function followUpCheckIn(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ // The rules:
    id: z.uuid(), // which answer,
    done: z.enum(["yes", "no"]), // whether it has been followed up,
    note: z.string().trim().max(2000, "Please keep the note under 2000 characters.").optional(), // and the note.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("check_in_follow_up", { p_id: parsed.data.id, p_done: parsed.data.done === "yes", p_note: parsed.data.note ?? null }); // Saves it.
  if (error) return { error: plainError(error, "We could not save that. Please try again.") }; // Failed: plain message.
  revalidatePath("/admin/check-ins"); // Refreshes the admin page.
  return { message: "Saved." }; // Confirms.
} // End of followUpCheckIn.
