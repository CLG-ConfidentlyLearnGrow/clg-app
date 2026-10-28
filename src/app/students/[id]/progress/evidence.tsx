import { removeEvidence } from "@/app/actions/progress";
import { Card, Empty, SubHeading } from "@/components/ui";
import { EVIDENCE_KIND_NAMES } from "@/lib/progress";
import { localDate, shortDate } from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";
import { EvidenceReviewForm, EvidenceUploadForm } from "./forms";

type Evidence = {
  id: string;
  kind: string;
  subject: string | null;
  title: string;
  dated_on: string | null;
  grade: string | null;
  note: string | null;
  file_type: string;
  uploaded_by: string | null;
  uploaded_by_role: "student" | "parent" | "tutor";
  uploaded_at: string;
  reviewed_at: string | null;
  tutor_comment: string | null;
  evidence_skills: { skill_id: string; skill: { description: string; plain_description: string | null } | null }[];
};

const FROM: Record<Evidence["uploaded_by_role"], string> = {
  student: "from the student",
  parent: "from the family",
  tutor: "from the tutor",
};

// "Work and reports": school reports, NAPLAN results, marked work and
// samples from sessions. The family and student upload; the tutor looks at
// each one and links the skills it shows. Only people who can see this
// student can open the files.
export async function EvidenceCard({
  studentId,
  viewerId,
  today,
  canUpload,
  canRemoveAny,
  canAddReports,
  isStaff,
  goalSkills,
}: {
  studentId: string;
  viewerId: string;
  today: string;
  canUpload: boolean;
  canRemoveAny: boolean;
  canAddReports: boolean;
  isStaff: boolean;
  goalSkills: { id: string; label: string }[];
}) {
  const supabase = await createClient();
  const res = await supabase
    .from("learning_evidence")
    .select(
      "id, kind, subject, title, dated_on, grade, note, file_type, uploaded_by, uploaded_by_role, uploaded_at, reviewed_at, tutor_comment, evidence_skills(skill_id, skill:curriculum_skills(description, plain_description))",
    )
    .eq("student_id", studentId)
    // Task sheets and rubrics show with their assessment on the roadmap.
    .is("target_id", null)
    .order("uploaded_at", { ascending: false })
    .limit(30);
  const items = (res.data ?? []) as unknown as Evidence[];
  const waiting = items.filter((e) => !e.reviewed_at && e.uploaded_by_role !== "tutor").length;

  return (
    <Card
      collapsible
      defaultOpen={isStaff ? waiting > 0 : false}
      title={`Work and reports${items.length ? ` (${items.length})` : ""}`}
      description={
        isStaff
          ? waiting > 0
            ? `${waiting} new from the family to look at.`
            : "School reports, NAPLAN, marked work and samples from sessions."
          : canAddReports
            ? "Share school reports, NAPLAN results and marked work, so the tutor can see where to focus."
            : "Share marked work, so the tutor can see where to focus."
      }
    >
      {items.length === 0 ? (
        <Empty>Nothing uploaded yet.</Empty>
      ) : (
        <ul className="divide-y divide-zinc-100 text-sm">
          {items.map((e) => (
            <li key={e.id} className="py-4 first:pt-0">
              <p className="font-medium">
                {/* A plain link, so the file is only fetched when tapped. */}
                <a
                  href={`/evidence/${e.id}/file`}
                  target="_blank"
                  rel="noopener"
                  className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700"
                >
                  {e.title}
                </a>
                <span className="font-normal text-zinc-600">
                  {" "}
                  · {EVIDENCE_KIND_NAMES[e.kind] ?? e.kind}
                  {e.subject && ` · ${e.subject}`}
                  {e.grade && ` · ${e.grade}`}
                </span>
              </p>
              <p className="text-xs text-zinc-500">
                {e.dated_on ? `Dated ${shortDate(e.dated_on)}, uploaded` : "Uploaded"} {shortDate(localDate(e.uploaded_at))}{" "}
                {FROM[e.uploaded_by_role]}
                {e.file_type === "application/pdf" ? " (PDF)" : " (photo)"}
              </p>
              {e.note && <p className="mt-1 whitespace-pre-line">{e.note}</p>}
              {e.tutor_comment && (
                <p className="mt-1">
                  <strong>Tutor:</strong> {e.tutor_comment}
                </p>
              )}
              {e.evidence_skills.length > 0 && (
                <p className="mt-1 text-zinc-600">
                  Shows:{" "}
                  {e.evidence_skills
                    .map((s) => s.skill?.plain_description || s.skill?.description)
                    .filter(Boolean)
                    .join("; ")}
                </p>
              )}
              {isStaff && (
                <details className="mt-2" open={!e.reviewed_at && e.uploaded_by_role !== "tutor"}>
                  <summary className="cursor-pointer text-teal-800">
                    {e.reviewed_at ? "Change your comment or skills" : "Look at it and link skills"}
                  </summary>
                  <div className="mt-3">
                    <EvidenceReviewForm
                      studentId={studentId}
                      evidenceId={e.id}
                      skills={goalSkills}
                      comment={e.tutor_comment}
                      linked={e.evidence_skills.map((s) => s.skill_id)}
                    />
                  </div>
                </details>
              )}
              {(canRemoveAny || e.uploaded_by === viewerId) && (
                <form action={removeEvidence} className="mt-2">
                  <input type="hidden" name="evidence_id" value={e.id} />
                  <input type="hidden" name="student_id" value={studentId} />
                  <button type="submit" className="text-xs text-zinc-500 underline hover:text-red-700">
                    Remove
                  </button>
                </form>
              )}
            </li>
          ))}
        </ul>
      )}
      {canUpload && (
        <>
          <SubHeading>Upload</SubHeading>
          <EvidenceUploadForm studentId={studentId} today={today} isStaff={isStaff} canAddReports={canAddReports} />
        </>
      )}
    </Card>
  );
}
