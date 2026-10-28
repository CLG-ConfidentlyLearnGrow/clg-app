"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import { childSchema, readSubjects } from "@/lib/child-form";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

export async function addChild(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("parent")) return { error: "Only parents can add a child." };

  const parsed = childSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const subjects = readSubjects(formData);
  if ("error" in subjects) return subjects;

  const supabase = await createClient();
  const { error } = await supabase.rpc("add_my_child", {
    p_full_name: parsed.data.full_name,
    p_date_of_birth: parsed.data.date_of_birth,
    p_state: parsed.data.state,
    p_year_level: parsed.data.year_level,
    p_school: parsed.data.school,
    p_subjects: subjects,
    p_goals: parsed.data.goals,
    p_extra_info: parsed.data.extra_info || undefined,
  });
  if (error) return { error: "We couldn't add your child. Please check the details and try again." };

  revalidatePath("/dashboard", "layout");
  return { message: `${parsed.data.full_name} has been added. CLG will confirm the details before a tutor is assigned.` };
}

// A parent changes a child's details. Date of birth and state can only be
// changed by CLG (the database enforces this), since they decide which
// child safety rules apply.
const editSchema = z.object({
  student_id: z.uuid(),
  full_name: childSchema.shape.full_name,
  year_level: childSchema.shape.year_level,
  school: childSchema.shape.school,
  goals: childSchema.shape.goals,
  extra_info: childSchema.shape.extra_info,
  // Only sent when CLG set up the child without them; the family fills them
  // in once (the database refuses later changes).
  date_of_birth: childSchema.shape.date_of_birth.optional(),
  state: childSchema.shape.state.optional(),
});

export async function updateChild(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("parent") && !viewer.roles.includes("admin")) {
    return { error: "Only a parent can change these details." };
  }
  const parsed = editSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const subjects = readSubjects(formData);
  if ("error" in subjects) return subjects;
  const v = parsed.data;

  const supabase = await createClient();
  const { data: updated, error } = await supabase
    .from("students")
    .update({
      full_name: v.full_name,
      year_level: v.year_level,
      school: v.school,
      goals: v.goals,
      extra_info: v.extra_info || null,
      ...(v.date_of_birth ? { date_of_birth: v.date_of_birth } : {}),
      ...(v.state ? { state: v.state } : {}),
    })
    .eq("id", v.student_id)
    .select("id");
  if (error || !updated?.length) return { error: "We couldn't save the changes. Please try again." };

  // Bring the subject list in line with what's ticked, and update levels.
  const { data: current } = await supabase
    .from("student_subjects")
    .select("id, subject, working_level")
    .eq("student_id", v.student_id);
  const wanted = new Map(subjects.map((s) => [s.subject.toLowerCase(), s]));
  const have = new Map((current ?? []).map((c) => [c.subject.toLowerCase(), c]));
  const remove = (current ?? []).filter((c) => !wanted.has(c.subject.toLowerCase())).map((c) => c.id);
  const add = subjects.filter((s) => !have.has(s.subject.toLowerCase()));
  const relevel = subjects.filter((s) => {
    const c = have.get(s.subject.toLowerCase());
    return c && c.working_level !== s.level;
  });
  const failed = { error: "Details saved, but we couldn't update the subjects. Please try again." };
  if (remove.length) {
    const { error: e } = await supabase.from("student_subjects").delete().in("id", remove);
    if (e) return failed;
  }
  if (add.length) {
    const { error: e } = await supabase
      .from("student_subjects")
      .insert(add.map((s) => ({ student_id: v.student_id, subject: s.subject, working_level: s.level })));
    if (e) return failed;
  }
  for (const s of relevel) {
    const { error: e } = await supabase
      .from("student_subjects")
      .update({ working_level: s.level })
      .eq("id", have.get(s.subject.toLowerCase())!.id);
    if (e) return failed;
  }

  revalidatePath("/dashboard", "layout");
  return { message: "Saved." };
}
