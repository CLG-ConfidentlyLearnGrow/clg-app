// Summary: the server actions for the decision steps record (Carla, 22 Nov
// 2026). Carla moves a person's step and changes the kinds of problem;
// Carla, or Operations admins for tutors, add notes to a record; each staff
// member adds to their own decisions log. The database checks every rule
// again. See docs/features/decision-steps.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in (the database checks the rest).
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Runs one database request and gives back the form reply. Messages the
// database wrote for people (codes 42501, 22023 and P0002) are shown as they are.
async function run(name: string, args: Record<string, unknown>, done: string): Promise<FormState> { // Takes the function, its inputs, and the thank you message.
  await requireViewer(); // Makes sure someone is signed in.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc(name, args); // Asks the database.
  if (error) return { error: ["42501", "22023", "P0002"].includes(error.code ?? "") ? error.message : "We could not save this. Please try again." }; // Failed: plain message.
  revalidatePath("/decisions"); // Refreshes the page.
  return { message: done }; // Confirms.
} // End of run.

// An id, or blank.
const optionalId = z.union([z.literal(""), z.uuid()]).default(""); // Blank or an id.

// Carla moves a person's step for one kind of problem.
export async function moveDecisionStep(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = z.object({ person: z.uuid(), kind: z.uuid(), step: z.coerce.number().int().min(1).max(5), note: z.string().trim().max(1000, "Please keep the note under 1000 characters.").optional() }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!p.success) return { error: "Please choose a step from 1 to 5." }; // Bad form: plain message.
  return run("decision_step_move", { p_account: p.data.person, p_kind: p.data.kind, p_step: p.data.step, p_note: p.data.note || null }, "Step saved. They have been told."); // Moves it.
} // End of moveDecisionStep.

// Carla, or Operations for tutors, adds a note to a record.
export async function addDecisionNote(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = z.object({ person: z.uuid(), kind: optionalId, body: z.string().trim().min(2, "Please write the note.").max(2000, "Please keep the note under 2000 characters.") }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!p.success) return { error: p.error.issues[0].message }; // Shows the first rule that failed.
  return run("decision_note_add", { p_account: p.data.person, p_kind: p.data.kind || null, p_body: p.data.body }, "Note added."); // Adds it.
} // End of addDecisionNote.

// A staff member adds to their own decisions log.
export async function addDecisionLog(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = z.object({ // The form's fields:
    kind: optionalId, // the kind of problem (optional),
    problem: z.string().trim().min(2, "Please write the problem.").max(2000, "Please keep each box under 2000 characters."), // the problem,
    options: z.string().trim().min(2, "Please write the options you considered.").max(2000, "Please keep each box under 2000 characters."), // the options,
    choice: z.string().trim().min(2, "Please write the one you chose and why.").max(2000, "Please keep each box under 2000 characters."), // the choice and why.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!p.success) return { error: p.error.issues[0].message }; // Shows the first rule that failed.
  return run("decision_log_add", { p_kind: p.data.kind || null, p_problem: p.data.problem, p_options: p.data.options, p_choice: p.data.choice, p_done: formData.get("done") === "on" }, "Recorded in your decisions log."); // Saves it.
} // End of addDecisionLog.

// Carla adds or changes a kind of problem.
export async function saveDecisionKind(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = z.object({ // The form's fields:
    id: optionalId, // which kind (blank for a new one),
    audience: z.enum(["admin", "tutor"], { message: "Please choose admin or tutors." }), // who it is for,
    title: z.string().trim().min(3, "Please describe the kind of problem.").max(300, "Please keep it under 300 characters."), // the kind of problem,
    start: z.coerce.number().int().min(1).max(5), // the starting step,
    goal: z.coerce.number().int().min(1).max(5), // the goal step,
    goal_note: z.string().trim().max(200, "Please keep the goal note under 200 characters.").optional(), // extra words for the goal.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!p.success) return { error: p.error.issues[0].message }; // Shows the first rule that failed.
  const active = p.data.id ? formData.get("active") === "on" : true; // Whether it is in use (new ones always are).
  return run("decision_kind_save", { p_id: p.data.id || null, p_audience: p.data.audience, p_title: p.data.title, p_start: p.data.start, p_goal: p.data.goal, p_goal_note: p.data.goal_note || null, p_active: active }, "Saved."); // Saves it.
} // End of saveDecisionKind.
