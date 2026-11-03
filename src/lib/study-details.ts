// Saves a university or TAFE student's degree, and each unit's code and
// link, after the student and their subjects are saved. Used by every form
// that adds or edits a student. Returns false if something didn't save.
import type { Wanted } from "@/lib/child-form";
import type { createClient } from "@/lib/supabase/server";

type Client = Awaited<ReturnType<typeof createClient>>;

export async function saveStudyDetails(
  supabase: Client,
  studentId: string,
  program: string | undefined,
  subjects: Wanted[],
): Promise<boolean> {
  let ok = true;
  const { data: current } = await supabase.from("students").select("program").eq("id", studentId).maybeSingle();
  if (current && (current.program ?? "") !== (program ?? "")) {
    const { error } = await supabase.from("students").update({ program: program || null }).eq("id", studentId);
    if (error) ok = false;
  }
  const { data: rows } = await supabase
    .from("student_subjects")
    .select("id, subject, course_code, course_url")
    .eq("student_id", studentId);
  for (const s of subjects) {
    const row = (rows ?? []).find((r) => r.subject.toLowerCase() === s.subject.toLowerCase());
    if (!row) continue;
    const code = s.course_code || null;
    const url = s.course_url || null;
    if (row.course_code === code && row.course_url === url) continue;
    const { error } = await supabase.from("student_subjects").update({ course_code: code, course_url: url }).eq("id", row.id);
    if (error) ok = false;
  }
  return ok;
}
