// Summary: the server actions for child safety concerns. Anyone signed in
// can raise a concern, and can say it is about someone who works for CLG
// (that person never sees it); only the people handling a concern can add
// notes, change where it's up to, pass it on or share it; only the owner can
// name the Child Safety Officer and deputy. The database checks every one of
// these rules again.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { redirect } from "next/navigation"; // Lets the code send someone to another page.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { REPORTING_LINES } from "@/lib/child-safety"; // The states, for checking the state chosen.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The state codes the database accepts, for checking the form.
const STATES = REPORTING_LINES.map((l) => l.state) as [string, ...string[]]; // e.g. SA, VIC, NSW ...

// Turns a database refusal into a plain message. Messages the database
// wrote for people (refusal codes 42501, 22023 and 54000) are shown as they
// are; anything else gets a general message with the safe fallback.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the database error and a general message.
  return ["42501", "22023", "54000"].includes(error.code ?? "") ? error.message : fallback; // The database's own words, or the fallback.
} // End of plainError.

// ---------------------------------------------------------------------------
// Raising a concern (anyone signed in)
// ---------------------------------------------------------------------------

// The rules for the concern form:
const raiseSchema = z.object({ // Each field and its rule:
  child: z.string().min(1, "Please choose which child this is about."), // which child: a student id, or "other",
  child_name: z.string().trim().max(200, "Please keep the name under 200 characters.").optional(), // the child's name, if not listed,
  child_state: z.union([z.enum(STATES), z.literal("")]).optional(), // the child's state, if not listed,
  send_to: z.enum(["officer", "deputy"], { message: "Please choose who to send this to." }), // officer or deputy,
  immediate_danger: z.enum(["yes", "no"], { message: "Please say whether a child is in immediate danger." }), // the danger answer,
  called_000: z.literal("on").optional(), // the "I have called 000" tick,
  reported_to_line: z.enum(["yes", "no", "not_sure"], { message: "Please say whether you have reported this to the child protection line." }), // the reporting-line answer,
  line_reference: z.string().trim().max(100, "Please keep the reference under 100 characters.").optional(), // the line's reference number,
  happened_on: z.union([z.iso.date(), z.literal("")]).optional(), // when it happened,
  what_happened: z.string().trim().min(10, "Please describe what happened (at least a sentence).").max(8000, "Please keep it under 8000 characters."), // what happened.
}); // End of the rules.

// Sends a concern to the Child Safety Officer or the deputy.
export async function raiseConcern(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back an error, or goes to the "sent" page.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = raiseSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const about = formData.getAll("about").map(String).filter((v) => v !== ""); // The CLG workers it's about (ticked boxes), if any.
  if (about.length > 5) return { error: "Please name at most five people. You can add more detail in \"What happened\"." }; // Too many ticked.
  if (about.some((v) => !z.uuid().safeParse(v).success)) return { error: "Please choose people from the list." }; // A bad value.
  const isOther = d.child === "other"; // True when the child isn't a CLG student listed.
  if (!isOther && !z.uuid().safeParse(d.child).success) return { error: "Please choose which child this is about." }; // A bad choice.
  if (isOther && !d.child_name) return { error: "Please give the child's name, or a description if you don't know it." }; // No name for an unlisted child.
  if (isOther && !d.child_state) return { error: "Please choose the state the child lives in." }; // No state for an unlisted child.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("raise_safety_concern", { // Asks the database to save the concern:
    p_student: isOther ? null : d.child, // the student (if listed),
    p_child_name: isOther ? d.child_name : null, // the typed name (if not),
    p_child_state: isOther ? d.child_state : null, // the chosen state (if not),
    p_send_to: d.send_to, // who it goes to,
    p_immediate_danger: d.immediate_danger === "yes", // the danger answer,
    p_called_000: d.called_000 === "on", // whether they called 000,
    p_reported_to_line: d.reported_to_line, // the reporting-line answer,
    p_line_reference: d.line_reference || null, // the reference number (if any),
    p_happened_on: d.happened_on || null, // when it happened (if given),
    p_what_happened: d.what_happened, // what happened,
    p_about: about.length > 0 ? about : null, // and who it's about (if anyone).
  }); // End of the request.
  if (error) return { error: plainError(error, "We couldn't send that. Please phone CLG directly, and if a child is in danger call 000.") }; // Failed: plain message.
  revalidatePath("/safety"); // Refreshes the concern page (for "Concerns you've raised").
  redirect(`/safety?sent=${encodeURIComponent(String(data))}`); // Shows the "sent" page.
} // End of raiseConcern.

// ---------------------------------------------------------------------------
// Dealing with a concern (the person it was sent to)
// ---------------------------------------------------------------------------

// Adds a follow-up note to a concern.
export async function addConcernNote(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ id: z.uuid(), note: z.string().trim().min(2, "Please write the note first.").max(4000, "Please keep notes under 4000 characters.") }).safeParse(Object.fromEntries(formData)); // Checks the concern id and note.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("safety_concern_add_note", { p_id: parsed.data.id, p_note: parsed.data.note }); // Saves the note.
  if (error) return { error: plainError(error, "We couldn't save that note. Please try again.") }; // Failed: plain message.
  revalidatePath("/safety/concerns"); // Refreshes the concerns page.
  return { message: "Note saved." }; // Confirms.
} // End of addConcernNote.

// Changes where a concern is up to.
export async function setConcernStatus(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ id: z.uuid(), status: z.enum(["new", "in_progress", "closed"], { message: "Please choose where this is up to." }) }).safeParse(Object.fromEntries(formData)); // Checks the concern id and stage.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("safety_concern_set_status", { p_id: parsed.data.id, p_status: parsed.data.status }); // Saves the stage.
  if (error) return { error: plainError(error, "We couldn't save that. Please try again.") }; // Failed: plain message.
  revalidatePath("/safety/concerns"); // Refreshes the concerns page.
  return { message: "Saved." }; // Confirms.
} // End of setConcernStatus.

// Passes a concern to the other child safety contact.
export async function passOnConcern(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ id: z.uuid(), reason: z.string().trim().min(2, "Please say why you are passing this on.").max(1000, "Please keep the reason under 1000 characters.") }).safeParse(Object.fromEntries(formData)); // Checks the concern id and reason.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("safety_concern_pass_on", { p_id: parsed.data.id, p_reason: parsed.data.reason }); // Passes it on.
  if (error) return { error: plainError(error, "We couldn't pass that on. Please try again.") }; // Failed: plain message.
  revalidatePath("/safety/concerns"); // Refreshes the concerns page.
  return { message: "Passed on. You can no longer open this concern." }; // Confirms, and says they've lost access.
} // End of passOnConcern.

// Shares a concern with the other child safety contact (the sharer keeps it too).
// This is how the deputy can choose to show the officer a flag about the officer.
export async function shareConcern(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ id: z.uuid(), reason: z.string().trim().min(2, "Please say why you are sharing this.").max(1000, "Please keep the reason under 1000 characters.") }).safeParse(Object.fromEntries(formData)); // Checks the concern id and reason.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("safety_concern_share", { p_id: parsed.data.id, p_reason: parsed.data.reason }); // Shares it.
  if (error) return { error: plainError(error, "We couldn't share that. Please try again.") }; // Failed: plain message.
  revalidatePath("/safety/concerns"); // Refreshes the concerns page.
  return { message: "Shared. They can now read this concern and its notes, and you still can too." }; // Confirms what happened.
} // End of shareConcern.

// ---------------------------------------------------------------------------
// Quiet steps on a concern about a tutor (the people handling it)
// ---------------------------------------------------------------------------

// The rules shared by both steps: which concern, which tutor, and why.
const stepSchema = z.object({ // Each field and its rule:
  id: z.uuid(), // the concern,
  tutor: z.uuid(), // the tutor,
  reason: z.string().trim().min(2, "Please say why you are taking this step.").max(1000, "Please keep the reason under 1000 characters."), // and why.
}); // End of the rules.

// Stops a tutor from being paired with new students (they keep their current ones).
export async function stopNewStudents(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = stepSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("safety_stop_new_students", { p_concern: parsed.data.id, p_tutor: parsed.data.tutor, p_reason: parsed.data.reason }); // Takes the step.
  if (error) return { error: plainError(error, "We couldn't do that. Please try again.") }; // Failed: plain message.
  revalidatePath("/safety/concerns"); // Refreshes the concerns page.
  return { message: "Done. They won't be matched with any new students. Their current students are unchanged, and they haven't been told." }; // Confirms what happened.
} // End of stopNewStudents.

// Ends a tutor's match with the concern's student.
export async function endMatch(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = stepSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("safety_end_match", { p_concern: parsed.data.id, p_tutor: parsed.data.tutor, p_reason: parsed.data.reason }); // Takes the step.
  if (error) return { error: plainError(error, "We couldn't do that. Please try again.") }; // Failed: plain message.
  revalidatePath("/safety/concerns"); // Refreshes the concerns page.
  const left = Number(data ?? 0); // How many bookings the pair still has.
  return { message: left > 0 ? `Match ended. They have ${left} upcoming booking(s) with this student: please change ${left === 1 ? "it" : "them"} in Sessions.` : "Match ended. The tutor can no longer open this student's records." }; // Confirms, and points to bookings to change.
} // End of endMatch.

// Lifts a quiet step.
export async function liftHold(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ hold: z.uuid(), reason: z.string().trim().min(2, "Please say why you are lifting this step.").max(1000, "Please keep the reason under 1000 characters.") }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("safety_lift_hold", { p_hold: parsed.data.hold, p_reason: parsed.data.reason }); // Lifts it.
  if (error) return { error: plainError(error, "We couldn't do that. Please try again.") }; // Failed: plain message.
  revalidatePath("/safety/concerns"); // Refreshes the concerns page.
  return { message: "Lifted." }; // Confirms.
} // End of liftHold.

// ---------------------------------------------------------------------------
// Naming the Child Safety Officer and deputy (owner only)
// ---------------------------------------------------------------------------

// Saves who receives concerns.
export async function setSafetyContacts(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ officer: z.uuid({ message: "Please choose a Child Safety Officer." }), deputy: z.union([z.uuid(), z.literal("")]) }).safeParse(Object.fromEntries(formData)); // Checks the two choices.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("set_child_safety_contacts", { p_officer: parsed.data.officer, p_deputy: parsed.data.deputy || null }); // Saves them.
  if (error) return { error: plainError(error, "We couldn't save that. Please try again.") }; // Failed: plain message.
  revalidatePath("/safety"); // Refreshes the concern page (it names them).
  return { message: "Saved. New concerns go to these people. Concerns already raised stay with the person they were sent to." }; // Confirms, and explains old concerns.
} // End of setSafetyContacts.
