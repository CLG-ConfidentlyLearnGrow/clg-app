// Summary: the server actions for work outside CLG (Carla, 22 Nov 2026;
// contract clause 6.7). Staff add, change and end their own reports; CLG's
// owner marks a report as seen with a private note. The database checks
// every rule again. See docs/features/outside-work-reports.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireAdminLevel, requireViewer } from "@/lib/auth"; // The admin level check, and the signed-in check.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message. Messages the database wrote
// for people (codes 42501, 22023 and P0002) are shown as they are; anything
// else gets the general message given.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the database error and a general message.
  return ["42501", "22023", "P0002"].includes(error.code ?? "") ? error.message : fallback; // The database's own words, or the general message.
} // End of plainError.

// Refreshes the pages that show the reports.
function refresh(): void { // No inputs.
  revalidatePath("/contract"); // The staff member's My contract page.
  revalidatePath("/admin/contracts"); // The owner's Contracts page.
} // End of refresh.

// The rules for a report.
const reportSchema = z.object({ // The form's fields:
  id: z.union([z.literal(""), z.uuid()]).default(""), // the report being changed (blank for a new one),
  kind: z.enum(["tutoring", "education_support", "admin", "other"], "Please choose the kind of role."), // the kind of role,
  role_title: z.string().trim().min(2, "Please say what the role is.").max(200, "Please keep the role under 200 characters."), // the role,
  organisation: z.string().trim().max(200, "Please keep the name under 200 characters.").optional(), // where (optional),
  details: z.string().trim().max(1000, "Please keep the details under 1000 characters.").optional(), // anything else (optional),
  paid: z.enum(["yes", "no"], "Please say whether it is paid."), // paid or not,
  starts_on: z.iso.date("Please choose the start date."), // when it starts,
  ends_on: z.union([z.iso.date("Please choose a real end date."), z.literal("")]).optional(), // when it ends (optional).
}); // End of the rules.

// Adds a report, or changes one of the person's own.
export async function saveOutsideWork(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in (the database checks they are staff).
  const parsed = reportSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("outside_work_save", { // Asks the database to save it:
    p_id: d.id || null, // which report (none for a new one),
    p_kind: d.kind, // the kind,
    p_role_title: d.role_title, // the role,
    p_organisation: d.organisation || null, // where,
    p_details: d.details || null, // anything else,
    p_paid: d.paid === "yes", // paid or not,
    p_starts_on: d.starts_on, // the start date,
    p_ends_on: d.ends_on || null, // and the end date (if any).
  }); // End of the request.
  if (error) return { error: plainError(error, "We could not save this. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: d.id ? "Saved. CLG has been told about the change." : "Thank you. CLG has been told." }; // Confirms.
} // End of saveOutsideWork.

// Ends one of the person's own reports.
export async function endOutsideWork(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ id: z.uuid(), ends_on: z.iso.date("Please choose the date it ends.") }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("outside_work_end", { p_id: parsed.data.id, p_ends_on: parsed.data.ends_on }); // Asks the database to end it.
  if (error) return { error: plainError(error, "We could not save this. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Saved. CLG has been told it ends." }; // Confirms.
} // End of endOutsideWork.

// The owner marks a report as seen, with a private note.
export async function markOutsideWorkSeen(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(["owner"]); // Must be the owner, with two-step sign-in.
  const parsed = z.object({ id: z.uuid(), note: z.string().trim().max(1000, "Please keep the note under 1000 characters.").optional() }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("outside_work_mark_seen", { p_id: parsed.data.id, p_note: parsed.data.note || null }); // Asks the database to save it.
  if (error) return { error: plainError(error, "We could not save this. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Marked as seen." }; // Confirms.
} // End of markOutsideWorkSeen.
