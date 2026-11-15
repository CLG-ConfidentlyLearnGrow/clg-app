// Summary: the server actions for feedback. Anyone signed in can give
// feedback; the people who can read a piece of feedback can mark where it's
// up to and keep a private note; only the owner changes the list of areas.
// The database checks every one of these rules again.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message. Messages the database wrote
// for people (codes 42501, 22023 and 54000) are shown as they are; anything
// else gets the general message given.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the database error and a general message.
  return ["42501", "22023", "54000"].includes(error.code ?? "") ? error.message : fallback; // The database's own words, or the general message.
} // End of plainError.

// The rules for the feedback form:
const giveSchema = z.object({ // Each field and its rule:
  area: z.string().min(1, "Please choose what your feedback is about."), // what it's about,
  kind: z.enum(["praise", "idea", "worry"], { message: "Please choose praise, an idea or a worry." }), // the kind,
  rating: z.union([z.enum(["1", "2", "3", "4", "5"]), z.literal("")]).optional(), // the optional rating,
  about: z.union([z.uuid(), z.literal("")]).optional(), // the person it's about (only for "A person at CLG"),
  comment: z.string().trim().min(3, "Please write a few words.").max(4000, "Please keep it under 4000 characters."), // what they want to say.
}); // End of the rules.

// Saves a piece of feedback.
export async function giveFeedback(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = giveSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const isPerson = d.area === "people_person"; // True when it's about a person.
  if (isPerson && !d.about) return { error: "Please choose who this feedback is about." }; // A person area with nobody chosen.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("give_feedback", { // Asks the database to save it:
    p_area: d.area, // what it's about,
    p_kind: d.kind, // the kind,
    p_rating: d.rating ? Number(d.rating) : null, // the rating (if any),
    p_comment: d.comment, // the comment,
    p_about: isPerson ? d.about : null, // and the person (only for "A person at CLG").
  }); // End of the request.
  if (error) return { error: plainError(error, "We couldn't save that. Please try again.") }; // Failed: plain message.
  revalidatePath("/feedback"); // Refreshes the feedback page (for "Your feedback").
  revalidatePath("/admin/feedback"); // Refreshes the overview.
  return { message: isPerson ? "Thank you. Your feedback has been sent privately. The person it's about won't see it." : "Thank you for your feedback!" }; // Thanks them.
} // End of giveFeedback.

// Marks where a piece of feedback is up to, and saves the private note.
export async function updateFeedback(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ // The rules:
    id: z.uuid(), // which feedback,
    status: z.enum(["new", "read", "acting", "done"], { message: "Please choose where this is up to." }), // its stage,
    note: z.string().trim().max(4000, "Please keep the note under 4000 characters.").optional(), // and the note.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("feedback_update", { p_id: parsed.data.id, p_status: parsed.data.status, p_note: parsed.data.note ?? null }); // Saves it.
  if (error) return { error: plainError(error, "We couldn't save that. Please try again.") }; // Failed: plain message.
  revalidatePath("/admin/feedback"); // Refreshes the overview.
  return { message: "Saved." }; // Confirms.
} // End of updateFeedback.

// Adds, renames or hides a feedback area (owner only).
export async function setFeedbackArea(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ // The rules:
    label: z.string().trim().min(2, "Please give the area a name.").max(80, "Please keep the name under 80 characters."), // its name,
    grp: z.enum(["app", "service"], { message: "Please choose \"The app\" or \"CLG's service\"." }), // its group,
    id: z.string().optional(), // its short name (when renaming or hiding),
    active: z.enum(["yes", "no"]).optional(), // whether it can be picked,
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const id = d.id || `${d.grp}_${d.label.toLowerCase().replace(/[^a-z]+/g, "_").replace(/^_|_$/g, "")}`.slice(0, 40); // A short name made from the group and the name, for a new area.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("set_feedback_area", { p_id: id, p_grp: d.grp, p_label: d.label, p_active: d.active !== "no" }); // Saves it.
  if (error) return { error: plainError(error, "We couldn't save that. Please try again.") }; // Failed: plain message.
  revalidatePath("/admin/feedback"); // Refreshes the overview.
  revalidatePath("/feedback"); // Refreshes the form (its list of areas).
  return { message: "Saved." }; // Confirms.
} // End of setFeedbackArea.
