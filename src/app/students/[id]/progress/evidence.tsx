// Summary: the "Work and reports" card: uploads from the family and tutor, with the tutor's review.
//
import { removeEvidence } from "@/app/actions/progress"; // The server action that removes an upload.
import { Card, Empty, SubHeading } from "@/components/ui"; // The card, "nothing yet" note and small heading.
import { EVIDENCE_KIND_NAMES } from "@/lib/progress"; // Names for each kind of upload.
import { localDate, shortDate } from "@/lib/scheduling"; // Dates from a time, and dates in short form.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { EvidenceReviewForm, EvidenceUploadForm } from "./forms"; // The forms for reviewing and uploading.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while sending.

// An upload as the database gives it.
type Evidence = {
  id: string; // its id,
  kind: string; // what kind it is,
  subject: string | null; // the subject (if any),
  title: string; // its name,
  dated_on: string | null; // the date on it (if any),
  grade: string | null; // the grade (if any),
  note: string | null; // a note (if any),
  file_type: string; // its file type,
  uploaded_by: string | null; // who uploaded it,
  uploaded_by_role: "student" | "parent" | "tutor"; // whether a student, parent or tutor,
  uploaded_at: string; // when,
  reviewed_at: string | null; // when the tutor looked at it (if they have),
  tutor_comment: string | null; // the tutor's comment (if any),
  evidence_skills: { skill_id: string; skill: { description: string; plain_description: string | null } | null }[]; // and the skills it shows.
}; // End of the shape.

const FROM: Record<Evidence["uploaded_by_role"], string> = { // Words for who uploaded it:
  student: "from the student", // the student,
  parent: "from the family", // the family,
  tutor: "from the tutor", // the tutor.
}; // End of the list.

// "Work and reports": school reports, NAPLAN results, marked work and
// samples from sessions. The family and student upload; the tutor looks at
// each one and links the skills it shows. Only people who can see this
// student can open the files.
export async function EvidenceCard({
  studentId, // the student,
  viewerId, // who is looking,
  today, // today's date,
  canUpload, // whether they can upload,
  canRemoveAny, // whether they can remove anyone's uploads,
  canAddReports, // whether they can add school reports,
  isStaff, // whether they're staff,
  goalSkills, // and the skills in the student's goals.
}: { // (their types:)
  studentId: string; // an id,
  viewerId: string; // an id,
  today: string; // a date,
  canUpload: boolean; // true or false,
  canRemoveAny: boolean; // true or false,
  canAddReports: boolean; // true or false,
  isStaff: boolean; // true or false,
  goalSkills: { id: string; label: string }[]; // a list of skills.
}) { // (end of the settings)
  const supabase = await createClient(); // Connects to the database.
  const res = await supabase // Reads the uploads:
    .from("learning_evidence") // from the uploads table,
    .select( // (with these fields:)
      "id, kind, subject, title, dated_on, grade, note, file_type, uploaded_by, uploaded_by_role, uploaded_at, reviewed_at, tutor_comment, evidence_skills(skill_id, skill:curriculum_skills(description, plain_description))", // the details and linked skills,
    ) // (end of the fields)
    .eq("student_id", studentId) // for this student,
    // Task sheets and rubrics show with their assessment on the roadmap.
    .is("target_id", null) // not linked to an assessment,
    .order("uploaded_at", { ascending: false }) // newest first,
    .limit(30); // at most 30.
  const items = (res.data ?? []) as unknown as Evidence[]; // The uploads.
  const waiting = items.filter((e) => !e.reviewed_at && e.uploaded_by_role !== "tutor").length; // How many the tutor still needs to look at.

  return ( // Shows:
    <Card // a card:
      collapsible // that can be opened and closed,
      defaultOpen={isStaff ? waiting > 0 : false} // open for staff when there's something new,
      title={`Work and reports${items.length ? ` (${items.length})` : ""}`} // titled with how many there are,
      description={ // with a description:
        isStaff // for staff:
          ? waiting > 0 // if there's something new,
            ? `${waiting} new from the family to look at.` // how many,
            : "School reports, NAPLAN, marked work and samples from sessions." // otherwise what goes here;
          : canAddReports // for families who can add reports,
            ? "Share school reports, NAPLAN results and marked work, so the tutor can see where to focus." // what to share,
            : "Share marked work, so the tutor can see where to focus." // otherwise just marked work.
      } // (end of the description)
    >{/* (end of the card's settings) */}
      {items.length === 0 ? ( // If nothing's uploaded:
        <Empty>Nothing uploaded yet.</Empty> // says so.
      ) : ( // Otherwise:
        <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
          {items.map((e) => ( // for each upload:
            <li key={e.id} className="py-4 first:pt-0">{/* a list item: */}
              <p className="font-medium">{/* a line in medium weight: */}
                {/* A plain link, so the file is only fetched when tapped. */}
                <a // a link:
                  href={`/evidence/${e.id}/file`} // that opens the file,
                  target="_blank" // in a new tab,
                  rel="noopener" // safely,
                  className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700" // styled as a link.
                >{/* (end of its settings) */}
                  {e.title}{/* The upload's name. */}
                </a>{/* End of the link. */}
                <span className="font-normal text-zinc-600">{/* Grey details: */}
                  {" "}{/* (a space) */}
                  · {EVIDENCE_KIND_NAMES[e.kind] ?? e.kind}{/* the kind, */}
                  {e.subject && ` · ${e.subject}`}{/* the subject, if any, */}
                  {e.grade && ` · ${e.grade}`}{/* and the grade, if any. */}
                </span>{/* End of the details. */}
              </p>{/* End of the line. */}
              <p className="text-xs text-zinc-500">{/* A small grey line: */}
                {e.dated_on ? `Dated ${shortDate(e.dated_on)}, uploaded` : "Uploaded"} {shortDate(localDate(e.uploaded_at))}{" "}{/* the date on it and when it was uploaded, */}
                {FROM[e.uploaded_by_role]}{/* who uploaded it, */}
                {e.file_type === "application/pdf" ? " (PDF)" : " (photo)"}{/* and whether it's a PDF or photo. */}
              </p>{/* End of the line. */}
              {e.note && <p className="mt-1 whitespace-pre-line">{e.note}</p>}{/* The note, if any, */}
              {e.tutor_comment && ( // if the tutor commented:
                <p className="mt-1">{/* a line: */}
                  <strong>Tutor:</strong> {e.tutor_comment}{/* "Tutor:" and the comment. */}
                </p> // End of the line.
              )}{/* End of the comment. */}
              {e.evidence_skills.length > 0 && ( // If it shows skills:
                <p className="mt-1 text-zinc-600">{/* a grey line: */}
                  Shows:{" "}{/* "Shows:", */}
                  {e.evidence_skills // the skills:
                    .map((s) => s.skill?.plain_description || s.skill?.description) // each skill's plain words (or official words),
                    .filter(Boolean) // leaving out blanks,
                    .join("; ")}{/* joined with semicolons. */}
                </p> // End of the line.
              )}{/* End of the skills. */}
              {isStaff && ( // For staff:
                <details className="mt-2" open={!e.reviewed_at && e.uploaded_by_role !== "tutor"}>{/* a section that opens when clicked (open if not looked at yet): */}
                  <summary className="cursor-pointer text-teal-800">{/* its clickable heading: */}
                    {e.reviewed_at ? "Change your comment or skills" : "Look at it and link skills"}{/* words depend on whether they've looked at it. */}
                  </summary>{/* End of the heading. */}
                  <div className="mt-3">{/* A block: */}
                    <EvidenceReviewForm // the review form:
                      studentId={studentId} // the student,
                      evidenceId={e.id} // the upload,
                      skills={goalSkills} // the goal skills to choose from,
                      comment={e.tutor_comment} // the current comment,
                      linked={e.evidence_skills.map((s) => s.skill_id)} // and the skills already linked.
                    />{/* (end of the form) */}
                  </div>{/* End of the block. */}
                </details> // End of the section.
              )}{/* End of the staff part. */}
              {(canRemoveAny || e.uploaded_by === viewerId) && ( // If this person can remove it:
                <form action={removeEvidence} className="mt-2">{/* a form that removes it: */}
                  <input type="hidden" name="evidence_id" value={e.id} />{/* which upload (hidden), */}
                  <input type="hidden" name="student_id" value={studentId} />{/* which student (hidden), */}
                  <BusyButton type="submit" className="text-xs text-zinc-500 underline hover:text-red-700">{/* a small button: */}
                    Remove{/* "Remove". */}
                  </BusyButton>{/* End of the button. */}
                </form> // End of the form.
              )}{/* End of the remove part. */}
            </li> // End of the list item.
          ))}{/* End of the uploads loop. */}
        </ul> // End of the list.
      )}{/* End of the choice. */}
      {canUpload && ( // If this person can upload:
        <>{/* (a group:) */}
          <SubHeading>Upload</SubHeading>{/* a small heading, */}
          <EvidenceUploadForm studentId={studentId} today={today} isStaff={isStaff} canAddReports={canAddReports} />{/* and the upload form. */}
        </> // (end of the group)
      )}{/* End of the upload part. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of EvidenceCard.
