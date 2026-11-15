// Summary: the server actions for changing a student's tutor on booked
// sessions (scheduling module, Carla 15 Nov 2026). A matching admin sends a
// change (new tutor, and optionally a new day and time) for confirmation;
// the new tutor and the family each confirm or decline it; nothing moves
// until both have said yes. The admin can withdraw a waiting change. The
// database checks every rule again and gives plain messages.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message: the database's own words
// when it wrote them for people, otherwise the general message given.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the error and a general message.
  return ["42501", "22023", "23514"].includes(error.code ?? "") ? error.message : fallback; // Its words, or the general message.
} // End of plainError.

// Refreshes the pages that show tutor changes.
function refresh() { // No inputs.
  revalidatePath("/schedule"); // The Sessions pages (and the Change tutor page under them).
  revalidatePath("/matching"); // The Matching page (its urgent box).
} // End of refresh.

// The rules for the admin's form:
const proposeSchema = z.object({ // Each field and its rule:
  student: z.uuid({ message: "Please choose the student again." }), // the student,
  from_tutor: z.uuid({ message: "Please choose the current tutor again." }), // the tutor the sessions are with now,
  subject: z.string().trim().min(1, "Please choose the subject again.").max(100, "Please choose the subject again."), // the subject,
  to_tutor: z.uuid({ message: "Please choose the new tutor." }), // the new tutor,
  from: z.iso.date({ message: "Please choose the change date." }), // the first date to move,
  weekday: z.union([z.literal(""), z.coerce.number().int().min(1).max(7)]).optional(), // the new weekday (1 = Monday), if the page offers it,
  start: z.union([z.literal(""), z.string().regex(/^\d{2}:\d{2}$/, "Please choose a start time.")]).optional(), // the new start time, if the page offers it,
  reason: z.string().trim().min(2, "Please give a short reason.").max(500, "Please keep the reason under 500 characters."), // a short reason,
  tell_old_tutor: z.literal("on").optional(), // the "tell the old tutor" tick.
}); // End of the rules.

// The admin sends a change to the new tutor and the family to confirm.
export async function proposeTutorChange(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message or an error.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = proposeSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("propose_tutor_change", { // Asks the database to check and save the change:
    p_student: d.student, // the student,
    p_from_tutor: d.from_tutor, // the current tutor,
    p_subject: d.subject, // the subject,
    p_to_tutor: d.to_tutor, // the new tutor,
    p_from: d.from, // from this date,
    p_reason: d.reason, // why,
    p_tell_old_tutor: d.tell_old_tutor === "on", // whether to tell the old tutor once it's confirmed,
    p_weekday: typeof d.weekday === "number" ? d.weekday : null, // the new weekday (or none),
    p_start: d.start ? d.start : null, // and the new start time (or none).
  }); // End of the request.
  if (error) return { error: plainError(error, "Sorry, the change couldn't be sent. Please try again, or contact Carla.") }; // The database said no.
  refresh(); // Refreshes the pages.
  return { message: "Sent. The new tutor and the family have been asked to confirm. Nothing moves until both say yes, and you'll see their answers under \"Waiting for confirmation\"." }; // Says it worked and what happens next.
} // End of proposeTutorChange.

// The admin withdraws a waiting change.
export async function withdrawTutorChange(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message or an error.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ id: z.uuid(), note: z.string().trim().max(1000).optional() }).safeParse(Object.fromEntries(formData)); // Checks the change's id and the optional note.
  if (!parsed.success) return { error: "Please try again." }; // Something's wrong with the form.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("withdraw_tutor_change", { p_offer: parsed.data.id, p_note: parsed.data.note || null }); // Asks the database to withdraw it.
  if (error) return { error: plainError(error, "Sorry, the change couldn't be withdrawn. Please try again.") }; // The database said no.
  refresh(); // Refreshes the pages.
  return { message: "Withdrawn. The new tutor and the family have been told nothing is changing." }; // Says it worked.
} // End of withdrawTutorChange.

// The new tutor or the family confirms or declines a waiting change.
export async function answerTutorChange(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message or an error.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z // Checks the form:
    .object({ id: z.uuid(), answer: z.enum(["yes", "no"]), note: z.string().trim().max(500, "Please keep it under 500 characters.").optional() }) // the change, yes or no, and a reason for no,
    .safeParse(Object.fromEntries(formData)); // from the form values.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const { id, answer, note } = parsed.data; // The checked answers.
  if (answer === "no" && !note) return { error: "Please say briefly why, so CLG can find something that suits." }; // A no needs a reason.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("answer_tutor_change", { p_offer: id, p_accept: answer === "yes", p_note: note || null }); // Sends the answer.
  if (error) return { error: plainError(error, "Sorry, your answer couldn't be saved. Please try again.") }; // The database said no.
  refresh(); // Refreshes the pages.
  if (answer === "no") return { message: "Thanks. CLG has been told and will be in touch." }; // A no: says so.
  if (data === "confirmed") return { message: "Thanks, everyone has confirmed. The sessions have been changed." }; // The last yes: it's done.
  if (data === "failed") return { message: "Thanks. The change couldn't be finished automatically, so CLG has been told and will be in touch." }; // It couldn't be made: CLG will sort it.
  return { message: "Thanks, confirmed. We're waiting for the others before anything changes." }; // Still waiting for the others.
} // End of answerTutorChange.
