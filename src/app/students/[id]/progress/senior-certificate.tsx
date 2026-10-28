import { removeSeniorSubject } from "@/app/actions/progress";
import { Card, Empty, SubHeading, Table } from "@/components/ui";
import { SENIOR_AREA_NAMES, SENIOR_STATUS_NAMES } from "@/lib/progress";
import { createClient } from "@/lib/supabase/server";
import { SeniorResultForm, SeniorSubjectForm } from "./forms";

type Certificate = { code: string; name: string; rules_loaded: boolean; total_credits: number | null };
type Requirement = {
  code: string;
  name: string;
  plain_description: string;
  min_credits: number;
  credits_done: number;
  credits_under_way: number;
  met: boolean;
};
type SeniorSubject = {
  id: string;
  subject: string;
  stage: number;
  credits: number;
  area: string | null;
  school_year: number | null;
  status: string;
  grade: string | null;
};

const SENIOR_YEARS = ["Year 10", "Year 11", "Year 12"];

// The student's senior certificate (SACE in South Australia): their senior
// subjects and how far they are towards each requirement. Shown from Year 10,
// or once a subject has been added. A planning aid; the school and the
// certificate board hold the official record.
export async function SeniorCertificateCard({
  studentId,
  yearLevel,
  canPlan,
  thisYear,
}: {
  studentId: string;
  yearLevel: string | null;
  canPlan: boolean;
  thisYear: number;
}) {
  const supabase = await createClient();
  const [certRes, subjectsRes] = await Promise.all([
    supabase.rpc("student_certificate", { p_student: studentId }),
    supabase
      .from("senior_subjects")
      .select("id, subject, stage, credits, area, school_year, status, grade")
      .eq("student_id", studentId)
      .order("stage")
      .order("school_year")
      .order("subject"),
  ]);
  const code = certRes.data as string | null;
  const subjects = (subjectsRes.data ?? []) as SeniorSubject[];
  if (!code || (subjects.length === 0 && !SENIOR_YEARS.includes(yearLevel ?? ""))) return null;

  const [certInfo, progressRes] = await Promise.all([
    supabase.from("senior_certificates").select("code, name, rules_loaded, total_credits").eq("code", code).maybeSingle(),
    supabase.rpc("certificate_progress", { p_student: studentId }),
  ]);
  const cert = certInfo.data as Certificate | null;
  if (!cert) return null;
  const progress = (progressRes.data ?? []) as Requirement[];
  const total = progress.find((p) => p.code === "total");

  return (
    <Card
      collapsible
      defaultOpen={false}
      title={`${cert.code === "ACT_SSC" ? "Senior certificate" : cert.code} progress${
        total ? ` (${total.credits_done} of ${total.min_credits} credits)` : ""
      }`}
      description={`${cert.name}: subjects and what's still needed. The school's record is the official one.`}
    >
      {!cert.rules_loaded ? (
        <p className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          CLG hasn&apos;t loaded the {cert.code} completion rules yet, so the app can&apos;t work out what&apos;s still
          needed. You can still list subjects and results.
        </p>
      ) : (
        <Table headings={["Requirement", "Done", "Under way", ""]}>
          {progress.map((r) => (
            <tr key={r.code}>
              <td>
                <span className="font-medium">{r.name}</span>
                <span className="block text-xs text-zinc-500">{r.plain_description}</span>
              </td>
              <td>
                {r.credits_done} of {r.min_credits}
              </td>
              <td>{r.credits_under_way || "-"}</td>
              <td className={r.met ? "font-semibold text-teal-800" : "text-zinc-500"}>{r.met ? "Done" : "Not yet"}</td>
            </tr>
          ))}
        </Table>
      )}

      <SubHeading>Subjects</SubHeading>
      {subjects.length === 0 ? (
        <Empty>No subjects added yet.</Empty>
      ) : (
        <ul className="divide-y divide-zinc-100 text-sm">
          {subjects.map((s) => (
            <li key={s.id} className="py-3 first:pt-0">
              <p>
                <span className="font-medium">{s.subject}</span>
                <span className="text-zinc-600">
                  {" "}
                  · Stage {s.stage} · {s.credits} credits
                  {s.school_year && ` · ${s.school_year}`} · {SENIOR_STATUS_NAMES[s.status] ?? s.status}
                  {s.grade && ` · ${s.grade}`}
                </span>
              </p>
              {s.area && <p className="text-xs text-zinc-500">Counts towards {SENIOR_AREA_NAMES[s.area] ?? s.area}</p>}
              {canPlan && (
                <details className="mt-2">
                  <summary className="cursor-pointer text-teal-800">Update result</summary>
                  <div className="mt-3 space-y-3">
                    <SeniorResultForm studentId={studentId} id={s.id} status={s.status} grade={s.grade} />
                    <form action={removeSeniorSubject}>
                      <input type="hidden" name="id" value={s.id} />
                      <input type="hidden" name="student_id" value={studentId} />
                      <button type="submit" className="text-xs text-zinc-500 underline hover:text-red-700">
                        Remove subject
                      </button>
                    </form>
                  </div>
                </details>
              )}
            </li>
          ))}
        </ul>
      )}
      {canPlan && (
        <>
          <SubHeading>Add a subject</SubHeading>
          <SeniorSubjectForm studentId={studentId} certificate={cert.code} thisYear={thisYear} />
        </>
      )}
    </Card>
  );
}
