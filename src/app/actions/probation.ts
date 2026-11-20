// Summary: the server actions for staff probation (Carla, 20 Nov 2026). The
// owner sets up a probation, corrects a start date, and records the review
// (passed, extended to a new date, or ended). The database checks every one
// of these rules again, including that only the owner can do them.
// See docs/features/staff-probation.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireAdminLevel } from "@/lib/auth"; // Makes sure the person is an admin at the right level.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message. Messages the database wrote
// for people (codes 42501 and 22023) are shown as they are; anything else
// gets the general message given.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the database error and a general message.
  return ["42501", "22023"].includes(error.code ?? "") ? error.message : fallback; // The database's own words, or the general message.
} // End of plainError.

// A date box's value: a real date, or empty.
const optionalDate = z.union([z.iso.date("Please choose a real date."), z.literal("")]).optional(); // "YYYY-MM-DD" or nothing.

// Sets up a probation for a staff member.
export async function startProbation(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(["owner"]); // Must be the owner, with two-step sign-in.
  const parsed = z.object({ // The rules:
    person: z.uuid("Please choose a staff member."), // who,
    kind: z.enum(["tutor", "admin"], "Please choose tutor or admin."), // which role,
    started_on: optionalDate, // the start date (optional),
    note: z.string().trim().max(1000, "Please keep the note under 1000 characters.").optional(), // and a note.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("staff_probation_start", { // Asks the database to set it up:
    p_account: d.person, // who,
    p_kind: d.kind, // which role,
    p_started_on: d.started_on || null, // the start date (none: their pay start date, or today),
    p_note: d.note || null, // and the note.
  }); // End of the request.
  if (error) return { error: plainError(error, "We could not set up that probation. Please try again.") }; // Failed: plain message.
  revalidatePath("/admin/probation"); // Refreshes the page.
  return { message: "Probation set up." }; // Confirms.
} // End of startProbation.

// Corrects a probation's start date.
export async function setProbationStart(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(["owner"]); // Must be the owner, with two-step sign-in.
  const parsed = z.object({ // The rules:
    id: z.uuid(), // which probation,
    started_on: z.iso.date("Please choose a real date."), // and the right start date.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("staff_probation_set_start", { p_id: parsed.data.id, p_started_on: parsed.data.started_on }); // Saves it.
  if (error) return { error: plainError(error, "We could not change the start date. Please try again.") }; // Failed: plain message.
  revalidatePath("/admin/probation"); // Refreshes the page.
  return { message: "Start date saved." }; // Confirms.
} // End of setProbationStart.

// Records the owner's probation review.
export async function decideProbation(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(["owner"]); // Must be the owner, with two-step sign-in.
  const parsed = z.object({ // The rules:
    id: z.uuid(), // which probation,
    outcome: z.enum(["passed", "extended", "ended"], "Please choose an outcome."), // the outcome,
    extend_to: optionalDate, // a new review date (for an extension),
    note: z.string().trim().max(1000, "Please keep the note under 1000 characters.").optional(), // and a note.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  if (d.outcome === "extended" && !d.extend_to) return { error: "Please choose the new review date." }; // An extension needs a date.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("staff_probation_decide", { // Asks the database to save it:
    p_id: d.id, // which probation,
    p_outcome: d.outcome, // the outcome,
    p_extend_to: d.outcome === "extended" ? d.extend_to : null, // the new date (extensions only),
    p_note: d.note || null, // and the note.
  }); // End of the request.
  if (error) return { error: plainError(error, "We could not save the review. Please try again.") }; // Failed: plain message.
  revalidatePath("/", "layout"); // Refreshes every page, so the side menu number updates.
  return { message: d.outcome === "passed" ? "Marked as passed." : d.outcome === "ended" ? "Marked as ended." : "Probation extended." }; // Confirms.
} // End of decideProbation.
