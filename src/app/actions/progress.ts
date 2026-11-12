// Summary: progress actions: learning goals, session notes, student
// reflections, family notes, roadmaps, term reviews, evidence of learning
// and senior certificate subjects.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { randomUUID } from "node:crypto"; // Makes random ids, for file names.
import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { MAX_DOCUMENT_BYTES, documentType } from "@/lib/documents"; // The biggest allowed file size, and a check of the file's type.
import { ATTENDANCE, EVIDENCE_KINDS, SKILL_LEVELS } from "@/lib/progress"; // Attendance choices, kinds of evidence and skill levels.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The database decides who may do each of these (the student's tutor,
// an admin, or the family); these actions only check the form is complete.

const progressPath = (studentId: string) => `/students/${studentId}/progress`; // The address of a student's progress page.

// The rules for a learning goal:
const goalSchema = z.object({
  student_id: z.uuid(), // which student,
  subject: z.string().trim().min(1, "Choose a subject.").max(100), // the subject,
  title: z.string().trim().min(3, "Write the goal in a few words a parent would understand.").max(200), // the goal in plain words,
  target_date: z.union([z.iso.date(), z.literal("")]).optional(), // a target date (optional, blank allowed).
}); // End of the rules.

// Adds a learning goal with the skills it covers.
export async function addGoal(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = goalSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const skills = formData.getAll("skill_id").map(String); // The chosen skills' ids.
  if (skills.length === 0) return { error: "Choose at least one skill for this goal." }; // None chosen: asks for at least one.
  if (!skills.every((s) => z.uuid().safeParse(s).success)) return { error: "Choose skills from the list." }; // Any odd id: asks them to pick from the list.

  const supabase = await createClient(); // Connects to the database.
  const goal = await supabase // Saves the goal:
    .from("learning_goals") // in the learning goals table,
    .insert({ // with:
      student_id: parsed.data.student_id, // the student,
      subject: parsed.data.subject, // the subject,
      title: parsed.data.title, // the goal's words,
      target_date: parsed.data.target_date || null, // the target date (or none),
    }) // (end of the values)
    .select("id") // and gets back its id,
    .single(); // (just the one row).
  if (goal.error) { // It failed:
    return { error: goal.error.code === "23514" ? goal.error.message : "Couldn't save the goal." }; // shows the database's plain rule message, or a general one.
  } // End of the failure case.

  const linked = await supabase // Links the skills to the goal:
    .from("goal_skills") // in the goal skills table,
    .insert(skills.map((skill_id) => ({ goal_id: goal.data.id, skill_id }))); // one row per skill.
  if (linked.error) return { error: "The goal was saved, but its skills couldn't be. Please add them again." }; // Failed: says the goal saved but the skills need adding again.

  revalidatePath(progressPath(parsed.data.student_id)); // Refreshes the student's progress page.
  return { message: "Goal added." }; // Confirms it.
} // End of addGoal.

// Marks a goal as achieved or stopped.
export async function closeGoal(formData: FormData) {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z // Checks the form:
    .object({ goal_id: z.uuid(), student_id: z.uuid(), status: z.enum(["achieved", "stopped"]) }) // the goal, the student, and the new status,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return; // Problem: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.from("learning_goals").update({ status: parsed.data.status }).eq("id", parsed.data.goal_id); // Saves the new status on the goal.
  revalidatePath(progressPath(parsed.data.student_id)); // Refreshes the student's progress page.
} // End of closeGoal.

// The rules for a session note:
const noteSchema = z.object({
  student_id: z.uuid(), // which student,
  session_date: z.iso.date("Enter the session date."), // the session date,
  minutes: z.coerce.number().int().min(0).max(480), // how many minutes (0 to 480),
  attendance: z.enum(ATTENDANCE), // attended or not,
  went_well: z.string().trim().max(1000).optional(), // what went well (optional),
  next_step: z.string().trim().max(500).optional(), // the next step (optional),
  homework: z.string().trim().max(1000).optional(), // homework (optional),
  homework_due: z.union([z.iso.date(), z.literal("")]).optional(), // when homework is due (optional),
  staff_note: z.string().trim().max(4000).optional(), // a note only staff see (optional),
  home_tip: z.string().trim().max(300, "Keep the tip under 300 characters.").optional(), // a tip for home (optional, under 300 characters),
  session_id: z.union([z.uuid(), z.literal("")]).optional(), // the booked session (optional),
  // How long the form was being filled in, measured in the browser.
  writing_seconds: z.union([z.coerce.number().int().min(0).max(7200), z.literal("")]).optional(), // seconds spent writing (optional).
}); // End of the rules.

// Saves a tutor's note after a session.
export async function saveSessionNote(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = noteSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  if (v.attendance !== "absent" && (!v.went_well || !v.next_step)) { // If the student came but "went well" or "next step" is blank:
    return { error: "Add what went well and one next step. These go to the student and their family." }; // asks for both.
  } // End of that check.

  // Each skill field is named skill_<id>; blank means not worked on today.
  const skills: { skill_id: string; level: string }[] = []; // The list of skills worked on, and how well.
  for (const [key, value] of formData.entries()) { // Goes through every form field:
    if (!key.startsWith("skill_") || !value) continue; // skips fields that aren't skills, or are blank,
    const skillId = key.slice("skill_".length); // takes the skill id from the field name,
    if (!z.uuid().safeParse(skillId).success) continue; // skips odd ids,
    if (!SKILL_LEVELS.includes(String(value) as (typeof SKILL_LEVELS)[number])) continue; // skips unknown levels,
    skills.push({ skill_id: skillId, level: String(value) }); // adds the skill and its level.
  } // End of the loop.

  const materialIds = formData // The materials used:
    .getAll("material_id") // (every material id in the form,)
    .map(String) // as text,
    .filter((m) => z.uuid().safeParse(m).success) // keeping only proper ids,
    .slice(0, 10); // and at most 10.

  const supabase = await createClient(); // Connects to the database.
  const { data: noteId, error } = await supabase.rpc("save_session_note", { // Asks the database to save the note, and gets its id:
    p_student: v.student_id, // the student,
    p_session_date: v.session_date, // the date,
    p_minutes: v.minutes, // the minutes,
    p_attendance: v.attendance, // the attendance,
    p_went_well: v.went_well ?? "", // what went well (or blank),
    p_next_step: v.next_step ?? "", // the next step (or blank),
    p_homework: v.homework ?? "", // homework (or blank),
    p_homework_due: v.homework_due || null, // homework due date (or none),
    p_staff_note: v.staff_note ?? "", // the staff note (or blank),
    p_skills: skills, // the skills,
    p_session: v.session_id || null, // the booked session (or none),
    p_home_tip: v.home_tip ?? "", // the tip for home (or blank),
    p_writing_seconds: typeof v.writing_seconds === "number" ? v.writing_seconds : null, // the writing time (or none).
  }); // End of the request.
  if (error) { // It failed:
    // The database explains rule breaks in plain words.
    const plain = ["23514", "22023", "42501"].includes(error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? error.message : "Couldn't save the note. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.

  // Which booklets or materials were used (kept by the materials module).
  // The note is already saved, so a problem here doesn't undo it.
  let materialsProblem = false; // Notes whether recording materials failed.
  if (materialIds.length > 0 && typeof noteId === "string") { // If materials were picked and the note has an id:
    const used = await supabase.rpc("record_material_use", { p_note: noteId, p_materials: materialIds }); // records them against the note,
    materialsProblem = Boolean(used.error); // and notes any failure.
  } // End of the materials step.

  revalidatePath(progressPath(v.student_id)); // Refreshes the student's progress page,
  revalidatePath("/dashboard/tutor"); // and the tutor's dashboard.
  return { // Tells the tutor:
    message: // (the message)
      "Session note saved. The family can see what went well, the next step and the tip for home." + // that the note is saved and what the family sees,
      (materialsProblem ? " The booklet used couldn't be recorded, but the note is saved." : ""), // plus a note if the materials couldn't be recorded.
  }; // End of the message.
} // End of saveSessionNote.

// The rules for a student's reflection:
const reflectionSchema = z.object({
  student_id: z.uuid(), // which student,
  note_id: z.uuid(), // which session note,
  confidence: z.coerce.number().int().min(1, "Choose how confident you feel.").max(4), // how confident they feel (1 to 4),
  what_was_hard: z.string().trim().max(500).optional(), // what was hard (optional),
  what_i_will_try: z.string().trim().max(500).optional(), // what they'll try (optional).
}); // End of the rules.

// Saves a student's reflection on a session.
export async function saveReflection(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = reflectionSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("student_reflections").insert({ // Saves the reflection:
    note_id: v.note_id, // the session note,
    student_id: v.student_id, // the student,
    confidence: v.confidence, // the confidence,
    what_was_hard: v.what_was_hard || null, // what was hard (or none),
    what_i_will_try: v.what_i_will_try || null, // what they'll try (or none).
  }); // End of the save.
  if (error) return { error: "Couldn't save the reflection." }; // Failed: plain message.

  revalidatePath(progressPath(v.student_id)); // Refreshes the student's progress page.
  return { message: "Thanks! Your tutor will see this before your next session." }; // Thanks them.
} // End of saveReflection.

// Feedback, or how practice is going at home, from the student or a parent.
const familyNoteSchema = z.object({
  student_id: z.uuid(), // which student,
  kind: z.enum(["feedback", "home_progress"], "Choose what kind of note this is."), // feedback or home progress,
  body: z.string().trim().min(1, "Write a few words.").max(2000, "Please keep it under 2,000 characters."), // the note itself (up to 2,000 characters).
}); // End of the rules.

// Saves a family's note.
export async function saveFamilyNote(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = familyNoteSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("family_notes").insert(parsed.data); // Saves the note.
  if (error) return { error: "Couldn't send it. Please try again." }; // Failed: plain message.

  revalidatePath(progressPath(parsed.data.student_id)); // Refreshes the student's progress page.
  return { message: "Thanks! The tutor and CLG will see this." }; // Thanks them.
} // End of saveFamilyNote.

// ---------------------------------------------------------------------------
// Learning roadmaps. The database decides who may plan: the student's own
// login, a parent who manages them, their tutor, or an admin.
// ---------------------------------------------------------------------------

// The rules for a roadmap target (an assessment or a goal):
const targetSchema = z.object({
  student_id: z.uuid(), // which student,
  kind: z.enum(["assessment", "goal"], "Choose an assessment or a goal."), // assessment or goal,
  subject: z.string().trim().max(100).optional(), // the subject (optional),
  title: z.string().trim().min(3, "Say what it is in a few words.").max(200), // what it is, in a few words,
  due_on: z.union([z.iso.date(), z.literal("")]).optional(), // the due date (optional),
  current_grade: z.string().trim().max(20, "Keep the grade short, for example C or 62%.").optional(), // the grade now (optional),
  target_grade: z.string().trim().max(20, "Keep the grade short, for example B or 75%.").optional(), // the grade they're aiming for (optional).
}); // End of the rules.

// Adds an assessment or goal to a student's roadmap, with any files.
export async function addRoadmapTarget(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = targetSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  if (v.kind === "assessment" && !v.due_on) return { error: "Add the date of the assessment." }; // An assessment needs a date.

  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase // Saves the target:
    .from("roadmap_targets") // in the roadmap targets table,
    .insert({ // with:
      student_id: v.student_id, // the student,
      kind: v.kind, // the kind,
      subject: v.subject || null, // the subject (or none),
      title: v.title, // the title,
      due_on: v.due_on || null, // the due date (or none),
      current_grade: v.current_grade || null, // the grade now (or none),
      target_grade: v.target_grade || null, // the aim grade (or none).
    }) // (end of the values)
    .select("id") // and gets back its id,
    .single(); // (just the one row).
  if (error) return { error: error.code === "23514" ? error.message : "Couldn't save it. Please try again." }; // Failed: the database's plain rule message, or a general one.

  // Assessments get a study plan straight away; it can be edited after.
  const planned = v.kind === "assessment" && formData.get("plan") === "on"; // True if it's an assessment and "plan" was ticked.
  if (planned) { // If so:
    await supabase.rpc("plan_assessment_steps", { p_target: data.id }); // asks the database to plan study steps up to the date.
  } // End of the planning step.

  // The task sheet and rubric, if given, are kept with the assessment.
  const problems: string[] = []; // A list of upload problems to report.
  for (const [field, kind, label] of [ // For each possible file:
    ["task_sheet", "task_sheet", "task sheet"], // the task sheet,
    ["rubric", "rubric", "rubric"], // and the rubric.
  ] as const) { // (end of the list)
    const file = formData.get(field); // Gets the file from the form.
    if (!(file instanceof File) || file.size === 0) continue; // Skips it if not given.
    const stored = await storeEvidenceFile(supabase, v.student_id, file); // Stores the file.
    if ("error" in stored) { // Storing failed:
      problems.push(`The ${label} didn't upload: ${stored.error}`); // notes the problem,
      continue; // and moves on.
    } // End of the failure case.
    const saved = await supabase.from("learning_evidence").insert({ // Records the file as evidence:
      student_id: v.student_id, // for this student,
      target_id: data.id, // linked to this target,
      kind, // the kind of file,
      subject: v.subject || null, // the subject (or none),
      title: `${v.title}: ${label}`.slice(0, 200), // a title like "Essay: rubric" (max 200 characters),
      file_path: stored.path, // where it's stored,
      file_type: stored.type, // its file type,
      uploaded_by_role: "parent", // and that a family member uploaded it.
    }); // End of the record.
    if (saved.error) { // Recording failed:
      await supabase.storage.from("learning-evidence").remove([stored.path]); // removes the stored file so nothing is left behind,
      problems.push(`The ${label} couldn't be saved. Please try again.`); // and notes the problem.
    } // End of the failure case.
  } // End of the files loop.

  revalidatePath(progressPath(v.student_id)); // Refreshes the student's progress page.
  if (problems.length) return { error: `Added to the roadmap. ${problems.join(" ")}` }; // Any problems: says it was added, then lists them.
  return { message: planned ? "Added, with study steps planned up to the date." : "Added to the roadmap." }; // Otherwise confirms it (and mentions planned steps).
} // End of addRoadmapTarget.

// The rules for a roadmap step:
const stepSchema = z.object({
  student_id: z.uuid(), // which student,
  target_id: z.union([z.uuid(), z.literal("")]).optional(), // which target it belongs to (optional),
  title: z.string().trim().min(2, "Write the step in a few words.").max(300), // the step in a few words,
  due_on: z.union([z.iso.date(), z.literal("")]).optional(), // when it's due (optional).
}); // End of the rules.

// Adds a step to a student's roadmap.
export async function addRoadmapStep(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = stepSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("roadmap_steps").insert({ // Saves the step:
    student_id: v.student_id, // the student,
    target_id: v.target_id || null, // the target (or none),
    title: v.title, // the step's words,
    due_on: v.due_on || null, // the due date (or none).
  }); // End of the save.
  if (error) return { error: error.code === "23514" ? error.message : "Couldn't add the step. Please try again." }; // Failed: the database's plain rule message, or a general one.
  revalidatePath(progressPath(v.student_id)); // Refreshes the student's progress page,
  revalidatePath("/dashboard/student"); // and the student's dashboard.
  return { message: "Step added." }; // Confirms it.
} // End of addRoadmapStep.

const ids = z.object({ student_id: z.uuid(), id: z.uuid() }); // The rules for a student id plus an item id.

// Ticks (or unticks) a roadmap step.
export async function tickRoadmapStep(formData: FormData) {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = ids.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return; // Problem: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("tick_roadmap_step", { p_step: parsed.data.id, p_done: formData.get("done") !== "false" }); // Asks the database to tick it (or untick if "done" is "false").
  revalidatePath(progressPath(parsed.data.student_id)); // Refreshes the student's progress page,
  revalidatePath("/dashboard/student"); // and the student's dashboard.
} // End of tickRoadmapStep.

// Removes a roadmap step.
export async function removeRoadmapStep(formData: FormData) {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = ids.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return; // Problem: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.from("roadmap_steps").delete().eq("id", parsed.data.id); // Deletes the step.
  revalidatePath(progressPath(parsed.data.student_id)); // Refreshes the student's progress page.
} // End of removeRoadmapStep.

// Plans study steps for an assessment.
export async function planRoadmapSteps(formData: FormData) {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = ids.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return; // Problem: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("plan_assessment_steps", { p_target: parsed.data.id }); // Asks the database to plan the steps.
  revalidatePath(progressPath(parsed.data.student_id)); // Refreshes the student's progress page.
} // End of planRoadmapSteps.

// Marks a roadmap target as done or dropped.
export async function closeRoadmapTarget(formData: FormData) {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = ids.extend({ status: z.enum(["done", "dropped"]) }).safeParse(Object.fromEntries(formData)); // Checks the form, plus the new status.
  if (!parsed.success) return; // Problem: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.from("roadmap_targets").update({ status: parsed.data.status }).eq("id", parsed.data.id); // Saves the new status.
  revalidatePath(progressPath(parsed.data.student_id)); // Refreshes the student's progress page.
} // End of closeRoadmapTarget.

// ---------------------------------------------------------------------------
// Term reviews: the tutor writes, an admin checks, the family reads and replies.
// ---------------------------------------------------------------------------

const RECOMMENDATIONS = ["continue", "change_focus", "more_sessions", "fewer_sessions", "break"] as const; // The tutor's recommendation choices for next term.

// The rules for a term review:
const reviewSchema = z.object({
  student_id: z.uuid(), // which student,
  review_id: z.uuid(), // which review,
  summary: z.string().trim().max(2000, "Keep how the term went under 2,000 characters.").optional(), // how the term went (optional),
  next_focus: z.string().trim().max(1000, "Keep the focus for next term under 1,000 characters.").optional(), // the focus for next term (optional),
  recommendation: z.union([z.enum(RECOMMENDATIONS), z.literal("")]).optional(), // a recommendation (optional),
  recommendation_note: z.string().trim().max(500).optional(), // a note on it (optional).
}); // End of the rules.

// Saves a tutor's term review as a draft, or sends it to CLG to check.
export async function saveTermReview(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = reviewSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const submit = formData.get("submit") === "on"; // True if "send to CLG" was ticked.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("save_term_review", { // Asks the database to save the review:
    p_review: v.review_id, // which review,
    p_summary: v.summary ?? "", // how the term went (or blank),
    p_next_focus: v.next_focus ?? "", // next term's focus (or blank),
    p_recommendation: v.recommendation || null, // the recommendation (or none),
    p_recommendation_note: v.recommendation_note ?? "", // the note (or blank),
    p_submit: submit, // and whether to send it.
  }); // End of the request.
  if (error) { // It failed:
    const plain = ["23514", "22023"].includes(error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? error.message : "Couldn't save the review. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  revalidatePath(progressPath(v.student_id)); // Refreshes the student's progress page,
  revalidatePath("/dashboard/tutor"); // and the tutor's dashboard.
  return { message: submit ? "Sent to CLG to check. The family sees it once it's checked." : "Draft saved." }; // Confirms it was sent, or saved as a draft.
} // End of saveTermReview.

// An admin approves a term review, or sends it back.
export async function checkTermReview(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in (the database checks for an admin).
  const parsed = z // Checks the form:
    .object({ review_id: z.uuid(), decision: z.enum(["approve", "return"], "Choose approve or send back."), reason: z.string().trim().max(500).optional() }) // the review, approve or send back, and a reason (optional),
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("check_term_review", { // Asks the database to record the decision:
    p_review: v.review_id, // which review,
    p_approve: v.decision === "approve", // approved or not,
    p_reason: v.reason ?? "", // the reason (or blank).
  }); // End of the request.
  if (error) { // It failed:
    const plain = ["23514", "22023", "42501"].includes(error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? error.message : "Couldn't save that. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.
  revalidatePath("/admin"); // Refreshes the admin pages.
  return { message: v.decision === "approve" ? "Approved. The family can see it now." : "Sent back to the tutor." }; // Confirms what happened.
} // End of checkTermReview.

// The family replies to a term review (and can ask for a call).
export async function replyTermReview(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z // Checks the form:
    .object({ student_id: z.uuid(), review_id: z.uuid(), reply: z.string().trim().max(2000, "Please keep it under 2,000 characters.").optional() }) // the student, the review, and the reply (optional),
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("reply_term_review", { // Asks the database to save the reply:
    p_review: v.review_id, // which review,
    p_reply: v.reply ?? "", // the reply (or blank),
    p_wants_call: formData.get("wants_call") === "on", // and whether they'd like a call.
  }); // End of the request.
  if (error) return { error: error.code === "23514" ? error.message : "Couldn't send it. Please try again." }; // Failed: the database's plain rule message, or a general one.
  revalidatePath(progressPath(v.student_id)); // Refreshes the student's progress page.
  return { message: "Thanks! CLG and the tutor will see this." }; // Thanks them.
} // End of replyTermReview.

// ---------------------------------------------------------------------------
// Evidence of learning: school reports, NAPLAN, marked work, work samples.
// ---------------------------------------------------------------------------
// The rules for a piece of evidence:
const evidenceSchema = z.object({
  student_id: z.uuid(), // which student,
  kind: z.enum(EVIDENCE_KINDS, "Choose what it is."), // what kind it is,
  title: z.string().trim().min(2, "Give it a short name, for example \"Term 2 report\".").max(200), // a short name,
  subject: z.string().trim().max(100).optional(), // the subject (optional),
  dated_on: z.union([z.iso.date(), z.literal("")]).optional(), // the date on it (optional),
  grade: z.string().trim().max(30).optional(), // the grade (optional),
  note: z.string().trim().max(1000).optional(), // a note (optional).
}); // End of the rules.

type Supabase = Awaited<ReturnType<typeof createClient>>; // The database connection's type, for the helper below.

// Checks an uploaded file is a PDF or photo under the size limit and puts it
// in the student's private folder. The caller saves the record, and removes
// the file if that fails.
async function storeEvidenceFile(
  supabase: Supabase, // the database connection,
  studentId: string, // the student,
  file: File, // the file.
): Promise<{ path: string; type: string } | { error: string }> { // Gives back where it's stored and its type, or a problem.
  if (file.size > MAX_DOCUMENT_BYTES) { // Too big:
    return { error: "That file is too big. Please use a file under 3.5 MB, or take a photo instead." }; // says so.
  } // End of the size check.
  const bytes = new Uint8Array(await file.arrayBuffer()); // Reads the file's bytes.
  const kind = documentType(bytes); // Works out its real type from the bytes.
  if (!kind) return { error: "Please upload a PDF or a photo (JPG, PNG or WebP)." }; // Not a PDF or photo: says so.
  const path = `${studentId}/${randomUUID()}.${kind.ext}`; // The storage path: the student's folder and a random name.
  const upload = await supabase.storage // Uploads it:
    .from("learning-evidence") // to the evidence storage,
    .upload(path, bytes, { contentType: kind.type, upsert: false }); // at that path, with its type, never replacing another file.
  if (upload.error) return { error: "Couldn't upload the file. Please try again." }; // Failed: plain message.
  return { path, type: kind.type }; // Gives back the path and type.
} // End of storeEvidenceFile.

// Uploads a piece of evidence (a report, test result or work sample).
export async function addEvidence(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const { file, ...fields } = Object.fromEntries(formData); // Splits the file from the other form fields.
  const parsed = evidenceSchema.safeParse(fields); // Checks the fields against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.

  if (!(file instanceof File) || file.size === 0) return { error: "Choose a file or take a photo." }; // No file: asks for one.
  const supabase = await createClient(); // Connects to the database.
  const stored = await storeEvidenceFile(supabase, v.student_id, file); // Stores the file.
  if ("error" in stored) return stored; // Storing failed: shows why.
  const { path, type } = stored; // Where it's stored and its type.

  const { error } = await supabase.from("learning_evidence").insert({ // Records it:
    student_id: v.student_id, // the student,
    kind: v.kind, // the kind,
    title: v.title, // the name,
    subject: v.subject || null, // the subject (or none),
    dated_on: v.dated_on || null, // the date (or none),
    grade: v.grade || null, // the grade (or none),
    note: v.note || null, // the note (or none),
    file_path: path, // where it's stored,
    file_type: type, // its file type,
    // The database sets the real value from who is uploading.
    uploaded_by_role: "parent", // (a placeholder).
  }); // End of the record.
  if (error) { // It failed:
    // Don't leave an unattached copy behind.
    await supabase.storage.from("learning-evidence").remove([path]); // removes the stored file,
    return { error: error.code === "23514" ? `${error.message}.` : "Couldn't save it. Please try again." }; // and shows the database's plain rule message, or a general one.
  } // End of the failure case.

  revalidatePath(progressPath(v.student_id)); // Refreshes the student's progress page.
  return { message: "Uploaded. The tutor will have a look." }; // Confirms it.
} // End of addEvidence.

// Removes a piece of evidence.
export async function removeEvidence(formData: FormData) {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ evidence_id: z.uuid(), student_id: z.uuid() }).safeParse(Object.fromEntries(formData)); // Checks the form has the evidence and student ids.
  if (!parsed.success) return; // Problem: does nothing.
  const supabase = await createClient(); // Connects to the database.
  // The file itself is removed by the daily job once the record is gone.
  await supabase.from("learning_evidence").delete().eq("id", parsed.data.evidence_id); // Deletes the record.
  revalidatePath(progressPath(parsed.data.student_id)); // Refreshes the student's progress page.
} // End of removeEvidence.

// A tutor comments on evidence and links it to skills.
export async function reviewEvidence(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z // Checks the form:
    .object({ evidence_id: z.uuid(), student_id: z.uuid(), comment: z.string().trim().max(1000).optional() }) // the evidence, the student, and a comment (optional),
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const skills = formData.getAll("skill_id").map(String); // The chosen skills' ids.
  if (!skills.every((s) => z.uuid().safeParse(s).success)) return { error: "Choose skills from the list." }; // Any odd id: asks them to pick from the list.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("review_evidence", { // Asks the database to save the review:
    p_evidence: parsed.data.evidence_id, // which evidence,
    p_comment: parsed.data.comment ?? "", // the comment (or blank),
    p_skills: skills, // the skills.
  }); // End of the request.
  if (error) return { error: error.code === "23514" ? `${error.message}.` : "Couldn't save it. Please try again." }; // Failed: the database's plain rule message, or a general one.
  revalidatePath(progressPath(parsed.data.student_id)); // Refreshes the student's progress page.
  return { message: "Saved." }; // Confirms it.
} // End of reviewEvidence.

// ---------------------------------------------------------------------------
// Senior certificate subjects (SACE and other states' certificates).
// ---------------------------------------------------------------------------
// The rules for a senior certificate subject:
const seniorSubjectSchema = z.object({
  student_id: z.uuid(), // which student,
  certificate: z.string().regex(/^[A-Z_]{2,12}$/), // the certificate's code, e.g. SACE,
  subject: z.string().trim().min(2, "Enter the subject.").max(100), // the subject,
  stage: z.coerce.number().int().min(1).max(2, "Choose Stage 1 or Stage 2."), // stage 1 or 2,
  credits: z.coerce.number().refine((n) => n === 10 || n === 20, "Choose 10 or 20 credits."), // 10 or 20 credits,
  area: z.enum(["", "eif", "literacy", "numeracy", "aif"]).optional(), // the required area it counts towards (optional),
  school_year: z.union([z.coerce.number().int().min(2020).max(2100), z.literal("")]).optional(), // the school year (optional),
  status: z.enum(["planned", "studying", "finished"]), // planned, studying or finished,
  grade: z.string().trim().max(3).optional(), // the grade (optional, up to 3 characters).
}); // End of the rules.

// Adds a senior certificate subject.
export async function addSeniorSubject(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = seniorSubjectSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  if (v.status === "finished" && !v.grade) return { error: "Add the grade for a finished subject." }; // A finished subject needs a grade.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("senior_subjects").insert({ // Saves the subject:
    student_id: v.student_id, // the student,
    certificate: v.certificate, // the certificate,
    subject: v.subject, // the subject,
    stage: v.stage, // the stage,
    credits: v.credits, // the credits,
    area: v.area || null, // the area (or none),
    school_year: v.school_year || null, // the school year (or none),
    status: v.status, // the status,
    grade: v.status === "finished" ? v.grade : null, // the grade, only when finished.
  }); // End of the save.
  if (error) return { error: error.code === "23514" ? `${error.message}.` : "Couldn't save it. Please try again." }; // Failed: the database's plain rule message, or a general one.
  revalidatePath(progressPath(v.student_id)); // Refreshes the student's progress page.
  return { message: "Subject added." }; // Confirms it.
} // End of addSeniorSubject.

// Changes a senior subject's status and grade.
export async function updateSeniorSubject(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z // Checks the form:
    .object({ // (the rules:)
      id: z.uuid(), // which subject,
      student_id: z.uuid(), // which student,
      status: z.enum(["planned", "studying", "finished"]), // the new status,
      grade: z.string().trim().max(3).optional(), // the grade (optional).
    }) // (end of the rules)
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  if (v.status === "finished" && !v.grade) return { error: "Add the grade for a finished subject." }; // A finished subject needs a grade.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase // Saves:
    .from("senior_subjects") // in the senior subjects table,
    .update({ status: v.status, grade: v.status === "finished" ? v.grade : null }) // the status, and the grade only when finished,
    .eq("id", v.id); // for this subject.
  if (error) return { error: error.code === "23514" ? `${error.message}.` : "Couldn't save it. Please try again." }; // Failed: the database's plain rule message, or a general one.
  revalidatePath(progressPath(v.student_id)); // Refreshes the student's progress page.
  return { message: "Saved." }; // Confirms it.
} // End of updateSeniorSubject.

// Removes a senior subject.
export async function removeSeniorSubject(formData: FormData) {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ id: z.uuid(), student_id: z.uuid() }).safeParse(Object.fromEntries(formData)); // Checks the form has the subject and student ids.
  if (!parsed.success) return; // Problem: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.from("senior_subjects").delete().eq("id", parsed.data.id); // Deletes the subject.
  revalidatePath(progressPath(parsed.data.student_id)); // Refreshes the student's progress page.
} // End of removeSeniorSubject.
