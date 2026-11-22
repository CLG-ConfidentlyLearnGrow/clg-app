// Summary: the admin card for changing a student's details (Carla, 20 Nov
// 2026). Admins confirming a new family check the year level, school,
// subjects and levels, and goals, and can now correct them here instead of
// asking the parent. Preferred days and times stay on the Schedule page.
// It also holds the Student Success Program section (Carla, 22 Nov 2026).
//
import { EditChildForm } from "@/app/dashboard/edit-child-form"; // The same "change a child's details" form parents use.
import { Button, Card, Empty, Select } from "@/components/ui"; // Shared page parts: button, card, empty line and drop-down.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { SspForm, type SspRecord } from "./ssp-form"; // The Student Success Program forms.

// One student as the picker needs them.
type StudentChoice = { id: string; full_name: string }; // their id and name.

// Plain words for where a student is up to in the Student Success Program.
export const SSP_STATUS: Record<string, string> = { // Each status and its words:
  requested: "the family has asked", // asked, not yet decided,
  approved: "place approved, waiting for the deposit", // place held, deposit not yet paid,
  enrolled: "in the program", // deposit paid,
  declined: "request declined", // CLG could not offer a place,
  withdrawn: "request or place withdrawn", // cancelled by the family or CLG,
  left: "has left the program", // was in it, now left.
}; // End of the words.

// Shows a drop-down of students and, once one is chosen, their details form.
export async function StudentDetailsCard({ // Its settings:
  students, // every student this admin can see,
  chosenId, // the student picked in the address (if any),
  birthDates, // each student's birth date, by id.
}: { // The settings' types:
  students: StudentChoice[]; // a list of students,
  chosenId: string | undefined; // an id or nothing,
  birthDates: Map<string, string | null>; // birth dates by student id (none if not known).
}) { // End of the settings.
  const chosen = students.find((s) => s.id === chosenId); // The chosen student, if the id is one of theirs.
  const supabase = await createClient(); // Connects to the database.
  // Reads the chosen student's full details and subjects (only when one is chosen).
  const [details, subjects, program] = chosen // If a student is chosen:
    ? await Promise.all([ // reads two things at once:
        supabase // their details:
          .from("students") // from students,
          .select("id, full_name, state, year_level, school, goals, extra_info, learning_needs, program") // the fields the form shows,
          .eq("id", chosen.id) // for this student,
          .maybeSingle(), // as one row (or none).
        supabase // and their subjects:
          .from("student_subjects") // from student_subjects,
          .select("subject, working_level, course_code, course_url") // with level and any unit code and link,
          .eq("student_id", chosen.id) // for this student,
          .order("added_at"), // oldest first.
        supabase // and their Student Success Program place:
          .from("ssp_enrolments") // from the program list,
          .select("status, request_note, sessions_planned, book_until, deposit_paid_on, note") // where they are up to and the details the forms show,
          .eq("student_id", chosen.id) // for this student,
          .maybeSingle(), // as one row (or none if they never asked).
      ]) // (end of the reads)
    : [null, null, null]; // Otherwise nothing is read.
  const row = details?.data ?? null; // The student's details (or nothing).
  const sspRow = (program?.data ?? null) as SspRecord | null; // Their program record (or nothing if they never asked).
  return ( // Shows:
    <Card // a fold-up card:
      collapsible // can fold,
      defaultOpen={!!chosen} // open when a student is chosen (for example from the Matching tab),
      title="Change a student's details" // its title,
      description="Correct a student's year level, school, subjects and levels, goals and other information. Preferred days and times are on the Schedule page, under the student's places." // its help text.
    >{/* (end of the card's settings) */}
      {students.length === 0 ? ( // If there are no students:
        <Empty>No students yet.</Empty> // says so.
      ) : ( // Otherwise:
        <div className="space-y-4">{/* a block: */}
          <form method="get" action="/admin" className="flex flex-wrap items-end gap-2">{/* a picker that reloads the page with the student chosen: */}
            <input type="hidden" name="section" value="families" />{/* stays on the families section (hidden), */}
            <Select label="Student" name="student" defaultValue={chosen?.id ?? ""}>{/* the student drop-down: */}
              <option value="" disabled>{/* a blank first choice that cannot be picked: */}
                Choose a student…{/* "Choose a student…". */}
              </option>{/* End of the choice. */}
              {students.map((s) => ( // for each student:
                <option key={s.id} value={s.id}>{/* a choice: */}
                  {s.full_name}{/* their name. */}
                </option> // End of the choice.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
            <Button type="submit">Open</Button>{/* the button that opens their details. */}
          </form>{/* End of the picker. */}
          {chosen && !row && <Empty>We could not load this student&apos;s details. Please try again.</Empty>}{/* A plain message if the read failed. */}
          {row && ( // Once the details are loaded:
            <EditChildForm // the details form:
              key={row.id} // starts fresh for each student,
              child={{ ...row, date_of_birth: birthDates.get(row.id) ?? null }} // with their details and birth date,
              subjects={(subjects?.data ?? []).map((s) => ({ // and their subjects, each as:
                subject: s.subject, // the subject,
                level: s.working_level as string | null, // the level,
                course_code: s.course_code ?? null, // any unit code,
                course_url: s.course_url ?? null, // and any unit link.
              }))} // (end of the subjects)
            /> // End of the form.
          )}{/* End of this part. */}
          {row && ( // Once the details are loaded, the program section:
            <section id="student-success-program" className="scroll-mt-4 space-y-3 border-t border-zinc-200 pt-4">{/* a section with a line above (the program card links straight here): */}
              <h3 className="text-base font-semibold text-zinc-900">{/* its heading: */}
                Student Success Program{sspRow ? `: ${SSP_STATUS[sspRow.status] ?? sspRow.status}` : ""}{/* the program name, and where they are up to. */}
              </h3>{/* End of the heading. */}
              <p className="text-sm text-zinc-600">{/* what the program does: */}
                Places are limited. Approving a place sends the family the $500 deposit invoice, and the student is in the program once it is paid{sspRow?.deposit_paid_on ? ` (paid ${sspRow.deposit_paid_on})` : ""}. Students in the program get a study plan, each term review at no charge, a program label, and first place in the Matching queue.{/* the plain explanation, with the day the deposit was paid if it has been. */}
              </p>{/* End of the explanation. */}
              <SspForm key={`${row.id}-${sspRow?.status ?? "none"}`} studentId={row.id} current={sspRow} />{/* the forms (fresh after each change). */}
            </section> // End of the section.
          )}{/* End of this part. */}
        </div> // End of the block.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of StudentDetailsCard.
