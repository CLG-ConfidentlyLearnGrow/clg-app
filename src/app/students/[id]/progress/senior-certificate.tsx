// Summary: the senior certificate card (SACE and others): requirements, subjects and forms.
//
import { removeSeniorSubject } from "@/app/actions/progress"; // The server action that removes a subject.
import { Card, Empty, SubHeading, Table } from "@/components/ui"; // The card, "nothing yet" note, small heading and table.
import { SENIOR_AREA_NAMES, SENIOR_STATUS_NAMES } from "@/lib/progress"; // Names for the required areas and subject statuses.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { SeniorResultForm, SeniorSubjectForm } from "./forms"; // The forms for adding a subject and updating a result.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while sending.

type Certificate = { code: string; name: string; rules_loaded: boolean; total_credits: number | null }; // A certificate: its code, name, whether its rules are loaded, and total credits.
// A requirement and how far the student is towards it.
type Requirement = {
  code: string; // its code,
  name: string; // its name,
  plain_description: string; // a plain description,
  min_credits: number; // credits needed,
  credits_done: number; // credits done,
  credits_under_way: number; // credits under way,
  met: boolean; // and whether it's met.
}; // End of the shape.
// A senior subject the student is taking.
type SeniorSubject = {
  id: string; // its id,
  subject: string; // the subject,
  stage: number; // stage 1 or 2,
  credits: number; // credits,
  area: string | null; // the required area it counts towards (if any),
  school_year: number | null; // the school year (if set),
  status: string; // planned, studying or finished,
  grade: string | null; // and the grade (if any).
}; // End of the shape.

const SENIOR_YEARS = ["Year 10", "Year 11", "Year 12"]; // The year levels when the card shows.

// The student's senior certificate (SACE in South Australia): their senior
// subjects and how far they are towards each requirement. Shown from Year 10,
// or once a subject has been added. A planning aid; the school and the
// certificate board hold the official record.
export async function SeniorCertificateCard({
  studentId, // the student,
  yearLevel, // their year level,
  canPlan, // whether this person can plan (add and change subjects),
  thisYear, // and this year.
}: { // (their types:)
  studentId: string; // an id,
  yearLevel: string | null; // text or nothing,
  canPlan: boolean; // true or false,
  thisYear: number; // a number.
}) { // (end of the settings)
  const supabase = await createClient(); // Connects to the database.
  const [certRes, subjectsRes] = await Promise.all([ // Reads two things at once:
    supabase.rpc("student_certificate", { p_student: studentId }), // which certificate the student is on,
    supabase // and their senior subjects:
      .from("senior_subjects") // (from the senior subjects table)
      .select("id, subject, stage, credits, area, school_year, status, grade") // with their details,
      .eq("student_id", studentId) // for this student,
      .order("stage") // by stage,
      .order("school_year") // then year,
      .order("subject"), // then subject.
  ]); // End of the reads.
  const code = certRes.data as string | null; // The certificate's code.
  const subjects = (subjectsRes.data ?? []) as SeniorSubject[]; // The subjects.
  if (!code || (subjects.length === 0 && !SENIOR_YEARS.includes(yearLevel ?? ""))) return null; // No certificate, or not senior years and no subjects: shows nothing.

  const [certInfo, progressRes] = await Promise.all([ // Reads two more things at once:
    supabase.from("senior_certificates").select("code, name, rules_loaded, total_credits").eq("code", code).maybeSingle(), // the certificate's details,
    supabase.rpc("certificate_progress", { p_student: studentId }), // and the student's progress towards each requirement.
  ]); // End of the reads.
  const cert = certInfo.data as Certificate | null; // The certificate.
  if (!cert) return null; // Not found: shows nothing.
  const progress = (progressRes.data ?? []) as Requirement[]; // The progress.
  const total = progress.find((p) => p.code === "total"); // The overall credits requirement.

  return ( // Shows:
    <Card // a card:
      collapsible // that can be opened and closed,
      defaultOpen={false} // closed to start,
      title={`${cert.code === "ACT_SSC" ? "Senior certificate" : cert.code} progress${
        total ? ` (${total.credits_done} of ${total.min_credits} credits)` : ""
      }`} // titled with the certificate and credits done,
      description={`${cert.name}: subjects and what's still needed. The school's record is the official one.`} // with a short explanation.
    >{/* (end of the card's settings) */}
      {!cert.rules_loaded ? ( // If the rules aren't loaded:
        <p className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">{/* an amber note: */}
          CLG hasn&apos;t loaded the {cert.code} completion rules yet, so the app can&apos;t work out what&apos;s still
          needed. You can still list subjects and results.{/* that progress can't be worked out yet. */}
        </p> // End of the note.
      ) : ( // Otherwise:
        <Table headings={["Requirement", "Done", "Under way", ""]}>{/* a table with these headings: */}
          {progress.map((r) => ( // for each requirement:
            <tr key={r.code}>{/* a row: */}
              <td>{/* a cell: */}
                <span className="font-medium">{r.name}</span>{/* its name, */}
                <span className="block text-xs text-zinc-500">{r.plain_description}</span>{/* and its description below. */}
              </td>{/* End of the cell. */}
              <td>{/* A cell: */}
                {r.credits_done} of {r.min_credits}{/* credits done of credits needed. */}
              </td>{/* End of the cell. */}
              <td>{r.credits_under_way || "-"}</td>{/* Credits under way (or "-"), */}
              <td className={r.met ? "font-semibold text-teal-800" : "text-zinc-500"}>{r.met ? "Done" : "Not yet"}</td>{/* done or not yet. */}
            </tr> // End of the row.
          ))}{/* End of the loop. */}
        </Table> // End of the table.
      )}{/* End of the choice. */}

      <SubHeading>Subjects</SubHeading>{/* A small heading "Subjects", */}
      {subjects.length === 0 ? ( // if there are none:
        <Empty>No subjects added yet.</Empty> // says so.
      ) : ( // Otherwise:
        <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
          {subjects.map((s) => ( // for each subject:
            <li key={s.id} className="py-3 first:pt-0">{/* a list item: */}
              <p>{/* a line: */}
                <span className="font-medium">{s.subject}</span>{/* the subject's name, */}
                <span className="text-zinc-600">{/* grey details: */}
                  {" "}{/* (a space) */}
                  · Stage {s.stage} · {s.credits} credits{/* stage and credits, */}
                  {s.school_year && ` · ${s.school_year}`} · {SENIOR_STATUS_NAMES[s.status] ?? s.status}{/* year and status, */}
                  {s.grade && ` · ${s.grade}`}{/* and grade, if any. */}
                </span>{/* End of the details. */}
              </p>{/* End of the line. */}
              {s.area && <p className="text-xs text-zinc-500">Counts towards {SENIOR_AREA_NAMES[s.area] ?? s.area}</p>}{/* The area it counts towards, if any. */}
              {canPlan && ( // If this person can plan:
                <details className="mt-2">{/* a section that opens when clicked: */}
                  <summary className="cursor-pointer text-teal-800">Update result</summary>{/* its heading "Update result", */}
                  <div className="mt-3 space-y-3">{/* a block: */}
                    <SeniorResultForm studentId={studentId} id={s.id} status={s.status} grade={s.grade} />{/* the result form, */}
                    <form action={removeSeniorSubject}>{/* a form that removes the subject: */}
                      <input type="hidden" name="id" value={s.id} />{/* which subject (hidden), */}
                      <input type="hidden" name="student_id" value={studentId} />{/* which student (hidden), */}
                      <BusyButton type="submit" className="text-xs text-zinc-500 underline hover:text-red-700">{/* a small button: */}
                        Remove subject{/* "Remove subject". */}
                      </BusyButton>{/* End of the button. */}
                    </form>{/* End of the form. */}
                  </div>{/* End of the block. */}
                </details> // End of the section.
              )}{/* End of the planning part. */}
            </li> // End of the list item.
          ))}{/* End of the subjects loop. */}
        </ul> // End of the list.
      )}{/* End of the choice. */}
      {canPlan && ( // If this person can plan:
        <>{/* (a group:) */}
          <SubHeading>Add a subject</SubHeading>{/* a small heading, */}
          <SeniorSubjectForm studentId={studentId} certificate={cert.code} thisYear={thisYear} />{/* and the form to add a subject. */}
        </> // (end of the group)
      )}{/* End of the planning part. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of SeniorCertificateCard.
