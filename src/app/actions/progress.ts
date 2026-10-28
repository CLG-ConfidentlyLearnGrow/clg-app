"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { MAX_DOCUMENT_BYTES, documentType } from "@/lib/documents";
import { ATTENDANCE, EVIDENCE_KINDS, SKILL_LEVELS } from "@/lib/progress";
import { createClient } from "@/lib/supabase/server";

// The database decides who may do each of these (the student's tutor,
// an admin, or the family); these actions only check the form is complete.

const progressPath = (studentId: string) => `/students/${studentId}/progress`;

const goalSchema = z.object({
  student_id: z.uuid(),
  subject: z.string().trim().min(1, "Choose a subject.").max(100),
  title: z.string().trim().min(3, "Write the goal in a few words a parent would understand.").max(200),
  target_date: z.union([z.iso.date(), z.literal("")]).optional(),
});

export async function addGoal(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = goalSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const skills = formData.getAll("skill_id").map(String);
  if (skills.length === 0) return { error: "Choose at least one skill for this goal." };
  if (!skills.every((s) => z.uuid().safeParse(s).success)) return { error: "Choose skills from the list." };

  const supabase = await createClient();
  const goal = await supabase
    .from("learning_goals")
    .insert({
      student_id: parsed.data.student_id,
      subject: parsed.data.subject,
      title: parsed.data.title,
      target_date: parsed.data.target_date || null,
    })
    .select("id")
    .single();
  if (goal.error) {
    return { error: goal.error.code === "23514" ? goal.error.message : "Couldn't save the goal." };
  }

  const linked = await supabase
    .from("goal_skills")
    .insert(skills.map((skill_id) => ({ goal_id: goal.data.id, skill_id })));
  if (linked.error) return { error: "The goal was saved, but its skills couldn't be. Please add them again." };

  revalidatePath(progressPath(parsed.data.student_id));
  return { message: "Goal added." };
}

export async function closeGoal(formData: FormData) {
  await requireViewer();
  const parsed = z
    .object({ goal_id: z.uuid(), student_id: z.uuid(), status: z.enum(["achieved", "stopped"]) })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return;
  const supabase = await createClient();
  await supabase.from("learning_goals").update({ status: parsed.data.status }).eq("id", parsed.data.goal_id);
  revalidatePath(progressPath(parsed.data.student_id));
}

const noteSchema = z.object({
  student_id: z.uuid(),
  session_date: z.iso.date("Enter the session date."),
  minutes: z.coerce.number().int().min(0).max(480),
  attendance: z.enum(ATTENDANCE),
  went_well: z.string().trim().max(1000).optional(),
  next_step: z.string().trim().max(500).optional(),
  homework: z.string().trim().max(1000).optional(),
  homework_due: z.union([z.iso.date(), z.literal("")]).optional(),
  staff_note: z.string().trim().max(4000).optional(),
  home_tip: z.string().trim().max(300, "Keep the tip under 300 characters.").optional(),
  session_id: z.union([z.uuid(), z.literal("")]).optional(),
  // How long the form was being filled in, measured in the browser.
  writing_seconds: z.union([z.coerce.number().int().min(0).max(7200), z.literal("")]).optional(),
});

export async function saveSessionNote(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = noteSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  if (v.attendance !== "absent" && (!v.went_well || !v.next_step)) {
    return { error: "Add what went well and one next step. These go to the student and their family." };
  }

  // Each skill field is named skill_<id>; blank means not worked on today.
  const skills: { skill_id: string; level: string }[] = [];
  for (const [key, value] of formData.entries()) {
    if (!key.startsWith("skill_") || !value) continue;
    const skillId = key.slice("skill_".length);
    if (!z.uuid().safeParse(skillId).success) continue;
    if (!SKILL_LEVELS.includes(String(value) as (typeof SKILL_LEVELS)[number])) continue;
    skills.push({ skill_id: skillId, level: String(value) });
  }

  const materialIds = formData
    .getAll("material_id")
    .map(String)
    .filter((m) => z.uuid().safeParse(m).success)
    .slice(0, 10);

  const supabase = await createClient();
  const { data: noteId, error } = await supabase.rpc("save_session_note", {
    p_student: v.student_id,
    p_session_date: v.session_date,
    p_minutes: v.minutes,
    p_attendance: v.attendance,
    p_went_well: v.went_well ?? "",
    p_next_step: v.next_step ?? "",
    p_homework: v.homework ?? "",
    p_homework_due: v.homework_due || null,
    p_staff_note: v.staff_note ?? "",
    p_skills: skills,
    p_session: v.session_id || null,
    p_home_tip: v.home_tip ?? "",
    p_writing_seconds: typeof v.writing_seconds === "number" ? v.writing_seconds : null,
  });
  if (error) {
    // The database explains rule breaks in plain words.
    const plain = ["23514", "22023", "42501"].includes(error.code ?? "");
    return { error: plain ? error.message : "Couldn't save the note. Please try again." };
  }

  // Which booklets or materials were used (kept by the materials module).
  // The note is already saved, so a problem here doesn't undo it.
  let materialsProblem = false;
  if (materialIds.length > 0 && typeof noteId === "string") {
    const used = await supabase.rpc("record_material_use", { p_note: noteId, p_materials: materialIds });
    materialsProblem = Boolean(used.error);
  }

  revalidatePath(progressPath(v.student_id));
  revalidatePath("/dashboard/tutor");
  return {
    message:
      "Session note saved. The family can see what went well, the next step and the tip for home." +
      (materialsProblem ? " The booklet used couldn't be recorded, but the note is saved." : ""),
  };
}

const reflectionSchema = z.object({
  student_id: z.uuid(),
  note_id: z.uuid(),
  confidence: z.coerce.number().int().min(1, "Choose how confident you feel.").max(4),
  what_was_hard: z.string().trim().max(500).optional(),
  what_i_will_try: z.string().trim().max(500).optional(),
});

export async function saveReflection(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = reflectionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;

  const supabase = await createClient();
  const { error } = await supabase.from("student_reflections").insert({
    note_id: v.note_id,
    student_id: v.student_id,
    confidence: v.confidence,
    what_was_hard: v.what_was_hard || null,
    what_i_will_try: v.what_i_will_try || null,
  });
  if (error) return { error: "Couldn't save the reflection." };

  revalidatePath(progressPath(v.student_id));
  return { message: "Thanks! Your tutor will see this before your next session." };
}

// Feedback, or how practice is going at home, from the student or a parent.
const familyNoteSchema = z.object({
  student_id: z.uuid(),
  kind: z.enum(["feedback", "home_progress"], "Choose what kind of note this is."),
  body: z.string().trim().min(1, "Write a few words.").max(2000, "Please keep it under 2,000 characters."),
});

export async function saveFamilyNote(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = familyNoteSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.from("family_notes").insert(parsed.data);
  if (error) return { error: "Couldn't send it. Please try again." };

  revalidatePath(progressPath(parsed.data.student_id));
  return { message: "Thanks! The tutor and CLG will see this." };
}

// ---------------------------------------------------------------------------
// Learning roadmaps. The database decides who may plan: the student's own
// login, a parent who manages them, their tutor, or an admin.
// ---------------------------------------------------------------------------

const targetSchema = z.object({
  student_id: z.uuid(),
  kind: z.enum(["assessment", "goal"], "Choose an assessment or a goal."),
  subject: z.string().trim().max(100).optional(),
  title: z.string().trim().min(3, "Say what it is in a few words.").max(200),
  due_on: z.union([z.iso.date(), z.literal("")]).optional(),
  current_grade: z.string().trim().max(20, "Keep the grade short, for example C or 62%.").optional(),
  target_grade: z.string().trim().max(20, "Keep the grade short, for example B or 75%.").optional(),
});

export async function addRoadmapTarget(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = targetSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  if (v.kind === "assessment" && !v.due_on) return { error: "Add the date of the assessment." };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("roadmap_targets")
    .insert({
      student_id: v.student_id,
      kind: v.kind,
      subject: v.subject || null,
      title: v.title,
      due_on: v.due_on || null,
      current_grade: v.current_grade || null,
      target_grade: v.target_grade || null,
    })
    .select("id")
    .single();
  if (error) return { error: error.code === "23514" ? error.message : "Couldn't save it. Please try again." };

  // Assessments get a study plan straight away; it can be edited after.
  if (v.kind === "assessment" && formData.get("plan") === "on") {
    await supabase.rpc("plan_assessment_steps", { p_target: data.id });
  }
  revalidatePath(progressPath(v.student_id));
  return { message: v.kind === "assessment" ? "Added, with steps planned up to the date." : "Added to the roadmap." };
}

const stepSchema = z.object({
  student_id: z.uuid(),
  target_id: z.union([z.uuid(), z.literal("")]).optional(),
  title: z.string().trim().min(2, "Write the step in a few words.").max(300),
  due_on: z.union([z.iso.date(), z.literal("")]).optional(),
});

export async function addRoadmapStep(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = stepSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.from("roadmap_steps").insert({
    student_id: v.student_id,
    target_id: v.target_id || null,
    title: v.title,
    due_on: v.due_on || null,
  });
  if (error) return { error: "Couldn't add the step. Please try again." };
  revalidatePath(progressPath(v.student_id));
  revalidatePath("/dashboard/student");
  return { message: "Step added." };
}

const ids = z.object({ student_id: z.uuid(), id: z.uuid() });

export async function tickRoadmapStep(formData: FormData) {
  await requireViewer();
  const parsed = ids.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return;
  const supabase = await createClient();
  await supabase.rpc("tick_roadmap_step", { p_step: parsed.data.id, p_done: formData.get("done") !== "false" });
  revalidatePath(progressPath(parsed.data.student_id));
  revalidatePath("/dashboard/student");
}

export async function removeRoadmapStep(formData: FormData) {
  await requireViewer();
  const parsed = ids.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return;
  const supabase = await createClient();
  await supabase.from("roadmap_steps").delete().eq("id", parsed.data.id);
  revalidatePath(progressPath(parsed.data.student_id));
}

export async function planRoadmapSteps(formData: FormData) {
  await requireViewer();
  const parsed = ids.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return;
  const supabase = await createClient();
  await supabase.rpc("plan_assessment_steps", { p_target: parsed.data.id });
  revalidatePath(progressPath(parsed.data.student_id));
}

export async function closeRoadmapTarget(formData: FormData) {
  await requireViewer();
  const parsed = ids.extend({ status: z.enum(["done", "dropped"]) }).safeParse(Object.fromEntries(formData));
  if (!parsed.success) return;
  const supabase = await createClient();
  await supabase.from("roadmap_targets").update({ status: parsed.data.status }).eq("id", parsed.data.id);
  revalidatePath(progressPath(parsed.data.student_id));
}

// ---------------------------------------------------------------------------
// Term reviews: the tutor writes, an admin checks, the family reads and replies.
// ---------------------------------------------------------------------------

const RECOMMENDATIONS = ["continue", "change_focus", "more_sessions", "fewer_sessions", "break"] as const;

const reviewSchema = z.object({
  student_id: z.uuid(),
  review_id: z.uuid(),
  summary: z.string().trim().max(2000, "Keep how the term went under 2,000 characters.").optional(),
  next_focus: z.string().trim().max(1000, "Keep the focus for next term under 1,000 characters.").optional(),
  recommendation: z.union([z.enum(RECOMMENDATIONS), z.literal("")]).optional(),
  recommendation_note: z.string().trim().max(500).optional(),
});

export async function saveTermReview(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = reviewSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const submit = formData.get("submit") === "on";
  const supabase = await createClient();
  const { error } = await supabase.rpc("save_term_review", {
    p_review: v.review_id,
    p_summary: v.summary ?? "",
    p_next_focus: v.next_focus ?? "",
    p_recommendation: v.recommendation || null,
    p_recommendation_note: v.recommendation_note ?? "",
    p_submit: submit,
  });
  if (error) {
    const plain = ["23514", "22023"].includes(error.code ?? "");
    return { error: plain ? error.message : "Couldn't save the review. Please try again." };
  }
  revalidatePath(progressPath(v.student_id));
  revalidatePath("/dashboard/tutor");
  return { message: submit ? "Sent to CLG to check. The family sees it once it's checked." : "Draft saved." };
}

export async function checkTermReview(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = z
    .object({ review_id: z.uuid(), decision: z.enum(["approve", "return"], "Choose approve or send back."), reason: z.string().trim().max(500).optional() })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("check_term_review", {
    p_review: v.review_id,
    p_approve: v.decision === "approve",
    p_reason: v.reason ?? "",
  });
  if (error) {
    const plain = ["23514", "22023", "42501"].includes(error.code ?? "");
    return { error: plain ? error.message : "Couldn't save that. Please try again." };
  }
  revalidatePath("/admin");
  return { message: v.decision === "approve" ? "Approved. The family can see it now." : "Sent back to the tutor." };
}

export async function replyTermReview(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = z
    .object({ student_id: z.uuid(), review_id: z.uuid(), reply: z.string().trim().max(2000, "Please keep it under 2,000 characters.").optional() })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("reply_term_review", {
    p_review: v.review_id,
    p_reply: v.reply ?? "",
    p_wants_call: formData.get("wants_call") === "on",
  });
  if (error) return { error: error.code === "23514" ? error.message : "Couldn't send it. Please try again." };
  revalidatePath(progressPath(v.student_id));
  return { message: "Thanks! CLG and the tutor will see this." };
}

// ---------------------------------------------------------------------------
// Evidence of learning: school reports, NAPLAN, marked work, work samples.
// ---------------------------------------------------------------------------
const evidenceSchema = z.object({
  student_id: z.uuid(),
  kind: z.enum(EVIDENCE_KINDS, "Choose what it is."),
  title: z.string().trim().min(2, "Give it a short name, for example \"Term 2 report\".").max(200),
  subject: z.string().trim().max(100).optional(),
  dated_on: z.union([z.iso.date(), z.literal("")]).optional(),
  grade: z.string().trim().max(30).optional(),
  note: z.string().trim().max(1000).optional(),
});

export async function addEvidence(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const { file, ...fields } = Object.fromEntries(formData);
  const parsed = evidenceSchema.safeParse(fields);
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;

  if (!(file instanceof File) || file.size === 0) return { error: "Choose a file or take a photo." };
  if (file.size > MAX_DOCUMENT_BYTES) {
    return { error: "That file is too big. Please use a file under 3.5 MB, or take a photo instead." };
  }
  const bytes = new Uint8Array(await file.arrayBuffer());
  const type = documentType(bytes);
  if (!type) return { error: "Please upload a PDF or a photo (JPG, PNG or WebP)." };

  const supabase = await createClient();
  const path = `${v.student_id}/${randomUUID()}.${type.ext}`;
  const upload = await supabase.storage
    .from("learning-evidence")
    .upload(path, bytes, { contentType: type.type, upsert: false });
  if (upload.error) return { error: "Couldn't upload the file. Please try again." };

  const { error } = await supabase.from("learning_evidence").insert({
    student_id: v.student_id,
    kind: v.kind,
    title: v.title,
    subject: v.subject || null,
    dated_on: v.dated_on || null,
    grade: v.grade || null,
    note: v.note || null,
    file_path: path,
    file_type: type.type,
    // The database sets the real value from who is uploading.
    uploaded_by_role: "parent",
  });
  if (error) {
    // Don't leave an unattached copy behind.
    await supabase.storage.from("learning-evidence").remove([path]);
    return { error: error.code === "23514" ? `${error.message}.` : "Couldn't save it. Please try again." };
  }

  revalidatePath(progressPath(v.student_id));
  return { message: "Uploaded. The tutor will have a look." };
}

export async function removeEvidence(formData: FormData) {
  await requireViewer();
  const parsed = z.object({ evidence_id: z.uuid(), student_id: z.uuid() }).safeParse(Object.fromEntries(formData));
  if (!parsed.success) return;
  const supabase = await createClient();
  // The file itself is removed by the daily job once the record is gone.
  await supabase.from("learning_evidence").delete().eq("id", parsed.data.evidence_id);
  revalidatePath(progressPath(parsed.data.student_id));
}

export async function reviewEvidence(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = z
    .object({ evidence_id: z.uuid(), student_id: z.uuid(), comment: z.string().trim().max(1000).optional() })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const skills = formData.getAll("skill_id").map(String);
  if (!skills.every((s) => z.uuid().safeParse(s).success)) return { error: "Choose skills from the list." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("review_evidence", {
    p_evidence: parsed.data.evidence_id,
    p_comment: parsed.data.comment ?? "",
    p_skills: skills,
  });
  if (error) return { error: error.code === "23514" ? `${error.message}.` : "Couldn't save it. Please try again." };
  revalidatePath(progressPath(parsed.data.student_id));
  return { message: "Saved." };
}

// ---------------------------------------------------------------------------
// Senior certificate subjects (SACE and other states' certificates).
// ---------------------------------------------------------------------------
const seniorSubjectSchema = z.object({
  student_id: z.uuid(),
  certificate: z.string().regex(/^[A-Z_]{2,12}$/),
  subject: z.string().trim().min(2, "Enter the subject.").max(100),
  stage: z.coerce.number().int().min(1).max(2, "Choose Stage 1 or Stage 2."),
  credits: z.coerce.number().refine((n) => n === 10 || n === 20, "Choose 10 or 20 credits."),
  area: z.enum(["", "eif", "literacy", "numeracy", "aif"]).optional(),
  school_year: z.union([z.coerce.number().int().min(2020).max(2100), z.literal("")]).optional(),
  status: z.enum(["planned", "studying", "finished"]),
  grade: z.string().trim().max(3).optional(),
});

export async function addSeniorSubject(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = seniorSubjectSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  if (v.status === "finished" && !v.grade) return { error: "Add the grade for a finished subject." };

  const supabase = await createClient();
  const { error } = await supabase.from("senior_subjects").insert({
    student_id: v.student_id,
    certificate: v.certificate,
    subject: v.subject,
    stage: v.stage,
    credits: v.credits,
    area: v.area || null,
    school_year: v.school_year || null,
    status: v.status,
    grade: v.status === "finished" ? v.grade : null,
  });
  if (error) return { error: error.code === "23514" ? `${error.message}.` : "Couldn't save it. Please try again." };
  revalidatePath(progressPath(v.student_id));
  return { message: "Subject added." };
}

export async function updateSeniorSubject(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = z
    .object({
      id: z.uuid(),
      student_id: z.uuid(),
      status: z.enum(["planned", "studying", "finished"]),
      grade: z.string().trim().max(3).optional(),
    })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  if (v.status === "finished" && !v.grade) return { error: "Add the grade for a finished subject." };

  const supabase = await createClient();
  const { error } = await supabase
    .from("senior_subjects")
    .update({ status: v.status, grade: v.status === "finished" ? v.grade : null })
    .eq("id", v.id);
  if (error) return { error: error.code === "23514" ? `${error.message}.` : "Couldn't save it. Please try again." };
  revalidatePath(progressPath(v.student_id));
  return { message: "Saved." };
}

export async function removeSeniorSubject(formData: FormData) {
  await requireViewer();
  const parsed = z.object({ id: z.uuid(), student_id: z.uuid() }).safeParse(Object.fromEntries(formData));
  if (!parsed.success) return;
  const supabase = await createClient();
  await supabase.from("senior_subjects").delete().eq("id", parsed.data.id);
  revalidatePath(progressPath(parsed.data.student_id));
}
