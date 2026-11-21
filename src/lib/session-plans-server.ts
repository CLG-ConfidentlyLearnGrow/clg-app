// Summary: server helpers for the plan for the next session and for files
// from a session (Carla, 21 Nov 2026). Used by the progress actions. Kept
// out of the actions file so these helpers can never be called straight
// from a browser. The database decides who may save (the student's tutor or
// an admin) and checks every limit again.
import "server-only"; // Stops this file from ever being sent to a browser.

import { randomUUID } from "node:crypto"; // Makes random ids, for file names.
import { z } from "zod"; // The form-checking library.
import { MAX_DOCUMENT_BYTES, documentType } from "@/lib/documents"; // The biggest allowed file size, and a check of the file's real type.
import { MAX_PLAN_MATERIALS } from "@/lib/session-plans"; // The most materials one plan can link.
import type { createClient } from "@/lib/supabase/server"; // The database connection maker (its type only).

type Supabase = Awaited<ReturnType<typeof createClient>>; // The database connection's type.

// The rules for the plan's boxes. Focus and activities are needed; the rest are optional.
const planSchema = z.object({
  plan_focus: z.string().trim().max(300, "Keep the focus under 300 characters.").optional(), // what the next session will focus on,
  plan_activities: z.string().trim().max(1000, "Keep the activities under 1,000 characters.").optional(), // how it will be taught,
  plan_review_first: z.string().trim().max(300, "Keep what to review first under 300 characters.").optional(), // what to review first (optional),
  plan_success_check: z.string().trim().max(300, "Keep how you will know it worked under 300 characters.").optional(), // how they will know it worked (optional),
  plan_other_resources: z.string().trim().max(500, "Keep other resources under 500 characters.").optional(), // other resources (optional).
}); // End of the rules.

// A plan read from a form, ready to save.
export type PlanInput = { // The shape:
  focus: string; // the focus,
  activities: string; // the activities,
  reviewFirst: string; // what to review first (may be blank),
  successCheck: string; // how they will know it worked (may be blank),
  otherResources: string; // other resources (may be blank),
  materials: string[]; // the linked materials' ids.
}; // End of the shape.

// Reads the plan from a form. Gives back the plan, nothing if every plan box
// is blank, or a plain problem to show.
export function readPlan(formData: FormData): { plan: PlanInput | null } | { error: string } { // Takes the form.
  const parsed = planSchema.safeParse(Object.fromEntries(formData)); // Checks the boxes against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const materials = formData // The linked materials:
    .getAll("plan_material_id") // (every plan material id in the form,)
    .map(String) // as text,
    .filter((m) => z.uuid().safeParse(m).success); // keeping only proper ids.
  if (materials.length > MAX_PLAN_MATERIALS) return { error: `Link up to ${MAX_PLAN_MATERIALS} materials for one session.` }; // Too many: says the limit.
  const anything = [v.plan_focus, v.plan_activities, v.plan_review_first, v.plan_success_check, v.plan_other_resources].some(Boolean) || materials.length > 0; // Whether anything at all was filled in.
  if (!anything) return { plan: null }; // Nothing filled in: no plan.
  if (!v.plan_focus || v.plan_focus.length < 3) return { error: "Write what the next session will focus on." }; // No focus: asks for it.
  if (!v.plan_activities || v.plan_activities.length < 3) return { error: "Write how you will teach it: the steps or activities." }; // No activities: asks for them.
  return { // Gives back the plan:
    plan: { // (the plan)
      focus: v.plan_focus, // the focus,
      activities: v.plan_activities, // the activities,
      reviewFirst: v.plan_review_first ?? "", // what to review first (or blank),
      successCheck: v.plan_success_check ?? "", // how they will know it worked (or blank),
      otherResources: v.plan_other_resources ?? "", // other resources (or blank),
      materials, // and the materials.
    }, // (end of the plan)
  }; // End of the reply.
} // End of readPlan.

// Saves a plan with its summary. Gives back a plain problem, or nothing if it saved.
export async function savePlan(supabase: Supabase, noteId: string, plan: PlanInput): Promise<string | null> { // Takes the connection, the summary and the plan.
  const { error } = await supabase.rpc("save_session_plan", { // Asks the database to save the plan:
    p_note: noteId, // for this summary,
    p_focus: plan.focus, // the focus,
    p_activities: plan.activities, // the activities,
    p_review_first: plan.reviewFirst, // what to review first,
    p_success_check: plan.successCheck, // how they will know it worked,
    p_other_resources: plan.otherResources, // other resources,
    p_materials: plan.materials, // and the linked materials.
  }); // End of the request.
  if (!error) return null; // Saved: no problem.
  const plain = ["23514", "22023", "42501", "P0002"].includes(error.code ?? ""); // True for the database's own plain refusals.
  return plain ? error.message : "The plan could not be saved. Please try again."; // That message, or a general one.
} // End of savePlan.

// Checks a file is a PDF or photo under the size limit, stores it in the
// student's private session files folder, and attaches it to the summary.
// Gives back a plain problem, or nothing if it saved.
export async function storeSessionFile( // Takes:
  supabase: Supabase, // the database connection,
  studentId: string, // the student,
  noteId: string, // the summary,
  file: File, // the file,
  title: string, // and a short name for it.
): Promise<string | null> { // Gives back a problem, or nothing.
  if (file.size > MAX_DOCUMENT_BYTES) return "That file is too big. Please use a file under 3.5 MB, or take a photo instead."; // Too big: says so.
  const bytes = new Uint8Array(await file.arrayBuffer()); // Reads the file's bytes.
  const kind = documentType(bytes); // Works out its real type from the bytes (not its name).
  if (!kind) return "Please upload a PDF or a photo (JPG, PNG or WebP)."; // Not a PDF or photo: says so.
  const path = `${studentId}/${randomUUID()}.${kind.ext}`; // The storage path: the student's folder and a random name.
  const upload = await supabase.storage // Uploads it:
    .from("session-files") // to the private session files store,
    .upload(path, bytes, { contentType: kind.type, upsert: false }); // at that path, with its type, never replacing another file.
  if (upload.error) return "Could not upload the file. Please try again."; // Failed: plain message.
  const name = (title.trim() || file.name || "Session file").slice(0, 200); // The name: the one typed, else the file's own name.
  const { error } = await supabase.from("session_note_files").insert({ // Records it:
    note_id: noteId, // on this summary,
    student_id: studentId, // for this student,
    title: name.length >= 2 ? name : "Session file", // with its name (at least 2 letters),
    file_path: path, // where it is stored,
    file_type: kind.type, // and its type.
  }); // End of the record.
  if (!error) return null; // Saved: no problem.
  await supabase.storage.from("session-files").remove([path]); // Failed: removes the stored copy so nothing is left behind.
  return error.code === "23514" ? error.message : "The file could not be saved. Please try again."; // The database's plain rule message, or a general one.
} // End of storeSessionFile.
