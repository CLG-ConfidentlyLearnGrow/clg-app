// Summary: reads students' birth dates through the database's checked
// function (student_birth_dates), which gives them only to admins, the
// student's parents and the student themselves. Tutors never get them: they
// work from the year level (Carla, 12 Nov 2026).
// If that database update hasn't been run yet, it falls back to reading the
// column directly, so pages keep working in between.

import type { createClient } from "@/lib/supabase/server"; // The type of a database connection (only used for checking types).

type Db = Awaited<ReturnType<typeof createClient>>; // A connection to the database as the signed-in person.

// Gives back each student's birth date (or nothing if not given), by student id.
export async function loadBirthDates(supabase: Db): Promise<Map<string, string | null>> { // Takes a connection; gives a list by student.
  const checked = await supabase.rpc("student_birth_dates"); // Asks the checked function for the birth dates this person may see.
  if (!checked.error) { // If it worked:
    const rows = (checked.data ?? []) as { student_id: string; date_of_birth: string | null }[]; // the rows (student and birth date),
    return new Map(rows.map((r) => [r.student_id, r.date_of_birth])); // given back by student.
  } // End of the normal case.
  // The function isn't there yet (database update not run): reads the column as before.
  const direct = await supabase.from("students").select("id, date_of_birth"); // Reads each student's id and birth date.
  const rows = (direct.data ?? []) as { id: string; date_of_birth: string | null }[]; // The rows (student and birth date).
  return new Map(rows.map((r) => [r.id, r.date_of_birth])); // Given back by student.
} // End of loadBirthDates.
