"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { ATTENDANCE, SKILL_LEVELS } from "@/lib/progress";
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

  const supabase = await createClient();
  const { error } = await supabase.rpc("save_session_note", {
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
  });
  if (error) {
    // The database explains rule breaks in plain words.
    const plain = ["23514", "22023", "42501"].includes(error.code ?? "");
    return { error: plain ? error.message : "Couldn't save the note. Please try again." };
  }

  revalidatePath(progressPath(v.student_id));
  return { message: "Session note saved. The family can see what went well and the next step." };
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
