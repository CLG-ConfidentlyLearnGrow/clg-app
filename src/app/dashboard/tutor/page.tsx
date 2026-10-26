import { redirect } from "next/navigation";
import { removeAvailability, removeTeaching } from "@/app/actions/tutor";
import { Card, Empty, SubHeading, Table, TextLink } from "@/components/ui";
import { RoleTabs } from "@/components/role-tabs";
import { SectionShell } from "@/components/section-shell";
import { needsTwoStep, requireViewer } from "@/lib/auth";
import { STATE_NAMES, WEEKDAYS, checkName, type AuState } from "@/lib/checks";
import { createClient } from "@/lib/supabase/server";
import { AvailabilityForm, MaxHoursForm, MyCheckForm, TeachingForm } from "../tutor-forms";

const SECTIONS = [
  { id: "students", label: "Your students" },
  { id: "teaching", label: "What you teach" },
  { id: "checks", label: "Child safety checks" },
  { id: "hours", label: "Hours and availability" },
] as const;

type CheckStatus = { kind: string; expires_on: string | null; status: string };
type MyCheck = {
  id: string;
  kind: string;
  reference: string | null;
  completed_on: string | null;
  expires_on: string;
  submitted_at: string | null;
  verified_at: string | null;
  declined_at: string | null;
  declined_reason: string | null;
  document_path: string | null;
};

const STATUS_NAMES: Record<string, string> = {
  current: "Current",
  expiring_soon: "Renew soon",
  expired: "Expired",
  missing: "Missing",
};

const day = (iso: string | null) =>
  iso ? new Date(iso).toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric" }) : "-";

export default async function TutorDashboard({ searchParams }: PageProps<"/dashboard/tutor">) {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("tutor")) redirect("/dashboard");
  if (needsTwoStep(viewer)) redirect("/mfa");
  const params = await searchParams;
  const requested = SECTIONS.find((s) => s.id === params.section)?.id ?? "students";

  const supabase = await createClient();
  const teaching = await supabase
    .from("tutor_teaching")
    .select("id, subject, from_level, to_level")
    .eq("tutor_id", viewer.id)
    .order("subject");
  const teachingRows = (teaching.data ?? []) as { id: string; subject: string; from_level: string; to_level: string }[];
  // New tutors are asked what they teach before anything else.
  const firstTime = teachingRows.length === 0;
  const section = firstTime ? "teaching" : requested;

  const [assigned, checks, mine, states, settings, slots] = await Promise.all([
    supabase
      .from("tutor_assignments")
      .select("id, subject, student:students(id, full_name, year_level)")
      .eq("tutor_id", viewer.id),
    supabase.from("tutor_check_status").select("kind, expires_on, status").eq("tutor_id", viewer.id),
    supabase
      .from("tutor_checks")
      .select("id, kind, reference, completed_on, expires_on, submitted_at, verified_at, declined_at, declined_reason, document_path")
      .eq("tutor_id", viewer.id)
      .order("submitted_at", { ascending: false }),
    supabase.from("tutor_cleared_states").select("state").eq("tutor_id", viewer.id),
    supabase.from("tutor_work_settings").select("max_weekly_hours").eq("tutor_id", viewer.id).maybeSingle(),
    supabase
      .from("tutor_availability")
      .select("id, weekday, starts_at, ends_at")
      .eq("tutor_id", viewer.id)
      .order("weekday")
      .order("starts_at"),
  ]);

  const statusRows = (checks.data ?? []) as CheckStatus[];
  const myChecks = (mine.data ?? []) as MyCheck[];
  const students = ((assigned.data ?? []) as unknown as {
    id: string;
    subject: string;
    student: { id: string; full_name: string; year_level: string | null } | null;
  }[]).filter((a) => a.student);
  const clearedStates = (states.data ?? []).map((s) => STATE_NAMES[s.state as AuState] ?? s.state);
  const problems = statusRows.filter((c) => c.status !== "current").length;

  return (
    <>
      <RoleTabs roles={viewer.roles} active="tutor" />
      <SectionShell
        basePath="/dashboard/tutor"
        label="Tutor"
        section={section}
        sections={SECTIONS.map((s) => ({ ...s, count: s.id === "checks" && problems ? problems : undefined }))}
      >
        {section === "students" && (
          <Card title="Your students">
            {problems > 0 && (
              <p className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
                Some of your checks are missing, expired or due soon. Students who need them are hidden until they are
                current. <TextLink href="/dashboard/tutor?section=checks">See your checks</TextLink>
              </p>
            )}
            {students.length === 0 ? (
              <Empty>No students assigned yet.</Empty>
            ) : (
              <ul className="divide-y divide-zinc-100 text-sm">
                {students.map((a) => (
                  <li key={a.id} className="flex flex-wrap items-baseline justify-between gap-2 py-3 first:pt-0">
                    <span>
                      <span className="font-medium">{a.student!.full_name}</span>
                      <span className="text-zinc-600">
                        {a.student!.year_level && ` · ${a.student!.year_level}`} · {a.subject}
                      </span>
                    </span>
                    <TextLink href={`/students/${a.student!.id}/progress`}>Progress and notes</TextLink>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        )}

        {section === "teaching" && (
          <>
            {firstTime && (
              <p className="rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm text-teal-900">
                Welcome! Before anything else, add each subject you can tutor and the year levels you teach it for.
                CLG uses this to match you with students.
              </p>
            )}
            <Card
              title="What you teach"
              description="Add each subject with its own year levels, for example Maths from Year 3 to Year 10 and English from Year 7 to Year 12."
            >
              {teachingRows.length === 0 ? (
                <Empty>No subjects added yet.</Empty>
              ) : (
                <ul className="divide-y divide-zinc-100 text-sm">
                  {teachingRows.map((t) => (
                    <li key={t.id} className="flex items-center justify-between gap-3 py-2.5 first:pt-0">
                      <span>
                        <span className="font-medium">{t.subject}</span>
                        <span className="text-zinc-600">
                          {" "}
                          · {t.from_level === t.to_level ? t.from_level : `${t.from_level} to ${t.to_level}`}
                        </span>
                      </span>
                      <form action={removeTeaching}>
                        <input type="hidden" name="id" value={t.id} />
                        <button type="submit" className="text-xs text-red-700 underline">
                          Remove
                        </button>
                      </form>
                    </li>
                  ))}
                </ul>
              )}
              <SubHeading>Add a subject</SubHeading>
              <TeachingForm />
            </Card>
          </>
        )}

        {section === "checks" && (
          <>
            <Card
              title="Where you stand"
              description={
                <>
                  You can currently be matched with students in:{" "}
                  <strong>{clearedStates.length ? clearedStates.join(", ") : "no states yet"}</strong>.
                </>
              }
            >
              {statusRows.length === 0 ? (
                <Empty>No checks confirmed yet. Add your checks below.</Empty>
              ) : (
                <Table headings={["Check", "Due again", "Status"]}>
                  {statusRows.map((c) => (
                    <tr key={c.kind} className={c.status === "current" ? "" : "text-red-700"}>
                      <td className="font-medium">{checkName(c.kind)}</td>
                      <td>{day(c.expires_on)}</td>
                      <td>{STATUS_NAMES[c.status] ?? c.status}</td>
                    </tr>
                  ))}
                </Table>
              )}
              <p className="mt-4 text-xs text-zinc-600">
                Each state needs its own working with children check (South Australia also needs RRHAN-EC Fundamentals
                and Masterclass). You can also add a first aid certificate or a police check. These are optional. The more states you are cleared for, the
                more students you can be matched with when a suitable match comes up. No number of students or hours is
                guaranteed.
              </p>
            </Card>

            <Card title="Add or renew a check">
              <MyCheckForm />
            </Card>

            <Card title="What you've sent" description="Every check you add is logged here with its dates.">
              {myChecks.length === 0 ? (
                <Empty>Nothing sent yet.</Empty>
              ) : (
                <Table headings={["Check", "Done", "Due again", "Sent", "Status"]}>
                  {myChecks.map((c) => (
                    <tr key={c.id}>
                      <td className="font-medium">
                        {checkName(c.kind)}
                        {c.reference && <span className="block text-xs text-zinc-500">{c.reference}</span>}
                        {c.document_path && (
                          <a
                            href={`/checks/${c.id}/document`}
                            target="_blank"
                            rel="noreferrer"
                            className="block text-xs text-teal-800 underline"
                          >
                            Your copy
                          </a>
                        )}
                      </td>
                      <td>{day(c.completed_on)}</td>
                      <td>{day(c.expires_on)}</td>
                      <td>{day(c.submitted_at)}</td>
                      <td>
                        {c.verified_at ? (
                          <span className="text-teal-800">Confirmed</span>
                        ) : c.declined_at ? (
                          <span className="text-red-700">
                            Sent back
                            {c.declined_reason && <span className="block text-xs">{c.declined_reason}</span>}
                          </span>
                        ) : (
                          <span className="text-zinc-600">Waiting for CLG</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </Table>
              )}
            </Card>
          </>
        )}

        {section === "hours" && (
          <Card
            title="Your hours and availability"
            description={
              <>
                These are separate: your availability is when you could teach, and your weekly limit is the most hours
                you can work in total.
              </>
            }
          >
            <MaxHoursForm current={settings.data?.max_weekly_hours ?? null} />
            <SubHeading>Times you are available</SubHeading>
            <ul className="mb-4 space-y-1 text-sm">
              {(slots.data ?? []).length === 0 && <li className="text-zinc-500">None added yet.</li>}
              {(slots.data ?? []).map((slot) => (
                <li key={slot.id} className="flex items-center gap-3">
                  <span>
                    {WEEKDAYS[slot.weekday - 1]} {slot.starts_at.slice(0, 5)} to {slot.ends_at.slice(0, 5)}
                  </span>
                  <form action={removeAvailability}>
                    <input type="hidden" name="id" value={slot.id} />
                    <button type="submit" className="text-xs text-red-700 underline">
                      Remove
                    </button>
                  </form>
                </li>
              ))}
            </ul>
            <AvailabilityForm />
          </Card>
        )}
      </SectionShell>
    </>
  );
}
