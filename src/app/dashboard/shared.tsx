// Summary: parts shared by the dashboards: loading students and tutors, the tutor list, new updates and missing details.
//
import { Card, TextLink } from "@/components/ui"; // The card and link style.
import { sessionWhen } from "@/lib/scheduling"; // Session times in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { loadBirthDates } from "@/lib/birth-dates"; // Reads students' birth dates through the database's check.

// A student as the dashboards need it.
export type Student = {
  id: string; // their id,
  full_name: string; // full name,
  date_of_birth: string | null; // date of birth (if known),
  state: string | null; // state (if known),
  year_level: string | null; // year level (if known),
  school: string | null; // school (if known),
  goals: string | null; // goals (if given),
  extra_info: string | null; // extra information (if given),
  learning_needs: string | null; // learning needs (if given),
  program: string | null; // degree or course (if any).
}; // End of the shape.
// A tutor assigned to a student for a subject.
export type Assignment = {
  id: string; // its id,
  subject: string; // the subject,
  student_id: string; // the student,
  tutor: { account: { full_name: string } | null; bio: string | null } | null; // the tutor's name and bio.
}; // End of the shape.

// Students and tutor assignments this person may see. The database decides
// which rows come back.
const STUDENT_FIELDS = "id, full_name, state, year_level, school, goals, extra_info, learning_needs, program"; // The student fields to read.
// The fields every version of the database has. Used if a newer database
// update hasn't been run yet, so families still see their children.
const CORE_STUDENT_FIELDS = "id, full_name, state, year_level, school, goals, extra_info"; // The fewer fields every database version has.

// Reads the students, falling back to fewer fields if the database is behind.
// Birth dates are read separately through the database's check (tutors
// don't get them), then added to each student.
async function loadStudents(supabase: Awaited<ReturnType<typeof createClient>>): Promise<Student[]> { // Takes a connection; gives the students with birth dates.
  const [rows, birthDates] = await Promise.all([loadStudentRows(supabase), loadBirthDates(supabase)]); // Reads the students and the birth dates at once.
  return rows.map((s) => ({ ...s, date_of_birth: birthDates.get(s.id) ?? null })); // Each student with their birth date (or none).
} // End of loadStudents.

// Reads the students' details (without birth dates), with the fallback.
async function loadStudentRows(supabase: Awaited<ReturnType<typeof createClient>>): Promise<Omit<Student, "date_of_birth">[]> { // Takes a connection; gives the students without birth dates.
  const full = await supabase.from("students").select(STUDENT_FIELDS).order("full_name"); // Tries all the fields.
  if (!full.error) return (full.data ?? []) as Omit<Student, "date_of_birth">[]; // Worked: gives them back.
  console.error("Loading students failed; trying the core fields. Has every database update been run?", full.error.code, full.error.message); // Didn't: notes it in the server log.
  const core = await supabase.from("students").select(CORE_STUDENT_FIELDS).order("full_name"); // Tries the core fields.
  return ((core.data ?? []) as Omit<Student, "learning_needs" | "program" | "date_of_birth">[]).map((s) => ({ // Gives them back,
    ...s, // with everything else,
    learning_needs: null, // no learning needs,
    program: null, // and no course.
  })); // (end of each student)
} // End of loadStudentRows.

// Reads the students and their tutors.
export async function loadStudentsAndTutors() {
  const supabase = await createClient(); // Connects to the database.
  const [students, assignments] = await Promise.all([ // Reads two things at once:
    loadStudents(supabase), // the students,
    supabase // and the tutor assignments:
      .from("tutor_assignments") // (from the assignments table)
      .select("id, subject, student_id, tutor:tutor_profiles(bio, account:accounts(full_name))"), // with the subject, student and tutor's name and bio.
  ]); // End of the reads.
  return { // Gives back:
    students, // the students,
    assignments: (assignments.data ?? []) as unknown as Assignment[], // and the assignments.
  }; // End of what's given back.
} // End of loadStudentsAndTutors.

// Lists a student's subjects and tutors.
export function TutorList({ assignments }: { assignments: Assignment[] }) {
  if (assignments.length === 0) return null; // None: shows nothing.
  return ( // Shows:
    <ul className="mt-1 list-disc pl-5 text-zinc-700">{/* a bulleted list: */}
      {assignments.map((a) => ( // for each assignment:
        <li key={a.id}>{/* a line: */}
          {a.subject} with {a.tutor?.account?.full_name ?? "your tutor"}{/* the subject and the tutor's name. */}
        </li> // End of the line.
      ))}{/* End of the loop. */}
    </ul> // End of the list.
  ); // End of what's shown.
} // End of TutorList.

type Update = { id: string; student_id: string; title: string; body: string; deliver_at: string }; // An update: its id, student, title, words and when it was sent.

// What's new since the family last looked: session notes (next step and the
// tip for home), steps due tomorrow, term reviews, and offers of a paid term review (no monthly summaries, Carla 12 Nov 2026).
// Opening the progress page marks them as seen. Shows nothing when there is
// nothing new.
export async function NewUpdates({ studentIds }: { studentIds?: string[] }) {
  const supabase = await createClient(); // Connects to the database.
  const res = await supabase // Reads the updates:
    .from("progress_notices") // from the progress notices table,
    .select("id, student_id, title, body, deliver_at") // with their details,
    .in("kind", ["session_update", "review_ready", "review_offer", "step_due"]) // of the kinds families see,
    .is("read_at", null) // not yet read,
    .order("deliver_at", { ascending: false }) // newest first,
    .limit(10); // at most 10.
  const updates = ((res.data ?? []) as Update[]).filter((u) => !studentIds || studentIds.includes(u.student_id)); // Keeps only the chosen students' updates (or all).
  if (updates.length === 0) return null; // None: shows nothing.
  return ( // Shows:
    <Card title="New from your tutor">{/* a card titled "New from your tutor": */}
      <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
        {updates.map((u) => ( // for each update:
          <li key={u.id} className="py-3 first:pt-0 last:pb-0">{/* a list item: */}
            <p className="flex flex-wrap items-baseline justify-between gap-2">{/* a row: */}
              <span className="font-medium">{u.title}</span>{/* the title, */}
              <span className="text-xs text-zinc-500">{sessionWhen(u.deliver_at)}</span>{/* and when it was sent. */}
            </p>{/* End of the row. */}
            <p className="mt-1 whitespace-pre-line text-zinc-700">{u.body}</p>{/* The update's words, keeping line breaks. */}
            <p className="mt-1">{/* A line: */}
              <TextLink href={`/students/${u.student_id}/progress?view=family`}>Open the progress page</TextLink>{/* with a link to the progress page. */}
            </p>{/* End of the line. */}
          </li> // End of the list item.
        ))}{/* End of the loop. */}
      </ul>{/* End of the list. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of NewUpdates.

// Details the family still needs to give (for children set up by CLG).
export function missingDetails(s: Student, subjectCount: number): string[] {
  const missing: string[] = []; // The list of missing details.
  if (!s.date_of_birth) missing.push("date of birth"); // No date of birth: adds it.
  if (!s.state) missing.push("state"); // No state: adds it.
  if (!s.year_level) missing.push("year level"); // No year level: adds it.
  if (!s.school) missing.push("school"); // No school: adds it.
  if (subjectCount === 0) missing.push("subjects"); // No subjects: adds them.
  if (!s.goals) missing.push("end goal"); // No goals: adds "end goal".
  return missing; // Gives back the list.
} // End of missingDetails.
