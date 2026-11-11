// Summary: saves a university or TAFE student's degree, and each unit's code
// and link, after the student and their subjects are saved. Used by every
// form that adds or edits a student. Returns false if something didn't save.

// The shape of one chosen subject, for type checking only.
import type { Wanted } from "@/lib/child-form";
// The database helper's type, for type checking only.
import type { createClient } from "@/lib/supabase/server";

// A short name for "a connected database helper".
type Client = Awaited<ReturnType<typeof createClient>>;

// Saves the degree name and each unit's code and link, only where they changed.
export async function saveStudyDetails(
  supabase: Client, // The database connection, acting as the signed-in person.
  studentId: string, // Which student to update.
  program: string | undefined, // The degree or course name (blank if none).
  subjects: Wanted[], // The subjects chosen on the form, with any unit codes and links.
): Promise<boolean> {
  let ok = true; // Stays true unless any save fails.
  const { data: current } = await supabase.from("students").select("program").eq("id", studentId).maybeSingle(); // Reads the saved degree name.
  if (current && (current.program ?? "") !== (program ?? "")) { // Only saves if it has changed.
    const { error } = await supabase.from("students").update({ program: program || null }).eq("id", studentId); // Saves the new degree name (blank becomes empty).
    if (error) ok = false; // Remembers the failure.
  } // End of the degree save.
  const { data: rows } = await supabase // Reads this student's saved subjects:
    .from("student_subjects") // from the student subjects table,
    .select("id, subject, course_code, course_url") // just the id, name, unit code and link,
    .eq("student_id", studentId); // for this student only.
  for (const s of subjects) { // Goes through each subject from the form.
    const row = (rows ?? []).find((r) => r.subject.toLowerCase() === s.subject.toLowerCase()); // Finds the saved row with the same name (ignoring capitals).
    if (!row) continue; // Not saved yet, so nothing to update.
    const code = s.course_code || null; // The unit code, or empty.
    const url = s.course_url || null; // The unit link, or empty.
    if (row.course_code === code && row.course_url === url) continue; // Unchanged, so skips the save.
    const { error } = await supabase.from("student_subjects").update({ course_code: code, course_url: url }).eq("id", row.id); // Saves the new code and link.
    if (error) ok = false; // Remembers the failure.
  } // End of the loop over subjects.
  return ok; // True if everything saved.
} // End of saveStudyDetails.
