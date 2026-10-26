import {
  confirmCheck,
  releaseHold,
  verifyParentLink,
} from "@/app/actions/admin";
import { confirmAllCurricula, confirmCurriculum, discardCurriculum } from "@/app/actions/curriculum";
import { AcaraImportForm } from "./acara-import";
import { Button, Card, Empty, SubHeading, Table } from "@/components/ui";
import { RoleTabs } from "@/components/role-tabs";
import { SectionShell } from "@/components/section-shell";
import { ADMIN_SECTIONS, sectionFrom } from "./sections";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { STATE_NAMES, checkName, type AuState } from "@/lib/checks";
import {
  AssignForm,
  CheckForm,
  DeclineCheckForm,
  EraseStudentForm,
  HoldForm,
  InviteForm,
  RetentionPeriodForm,
  TutorLeftForm,
  UnlockForm,
  WorkStateForm,
} from "./forms";
import {
  FrameworkForm,
  ImportSkillsForm,
  StudentFrameworkForm,
} from "./curriculum-forms";

type PendingLink = {
  parent_id: string;
  student_id: string;
  relationship: string;
  parent: { full_name: string } | null;
  student: { full_name: string; date_of_birth: string } | null;
};
type CheckRow = {
  tutor_id: string;
  full_name: string;
  kind: string;
  expires_on: string | null;
  status: string;
};

type Due = {
  kind: "student" | "account" | "tutor";
  record_id: string;
  full_name: string;
  due_on: string;
};
type Hold = {
  id: string;
  reason: string;
  placed_at: string;
  student: { full_name: string } | null;
  account: { full_name: string } | null;
};
type Rule = { kind: string; keep_for: string; description: string };

const RULE_LABELS: Record<string, string> = {
  student_records: "Student records",
  unused_accounts: "Unused accounts",
  former_tutors: "Former tutors",
  activity_log: "Activity log",
};
const DUE_LABELS: Record<Due["kind"], string> = {
  student: "Student",
  account: "Unused account",
  tutor: "Former tutor",
};

// Postgres writes "1 year 6 mons"; show it in plain words.
function plainPeriod(p: string) {
  return p.replace(/\bmons?\b/g, (m) => (m === "mon" ? "month" : "months"));
}

type Eligible = {
  tutor_id: string;
  full_name: string;
  subjects: string[];
  max_weekly_hours: number | null;
};

export default async function AdminPage({ searchParams }: PageProps<"/admin">) {
  const viewer = await requireAdmin();
  const supabase = await createClient();
  const params = await searchParams;
  const studentId = typeof params.student === "string" ? params.student : null;
  const section = sectionFrom(params.section);

  const [me, pending, checks, students, tutorList, cleared, due, holds, rules] =
    await Promise.all([
      supabase
        .from("admin_profiles")
        .select("level")
        .eq("account_id", viewer.id)
        .maybeSingle(),
      supabase
        .from("parent_student_links")
        .select(
          "parent_id, student_id, relationship, parent:parent_profiles(account:accounts(full_name)), student:students(full_name, date_of_birth)",
        )
        .is("verified_at", null),
      supabase
        .from("tutor_check_status")
        .select("tutor_id, full_name, kind, expires_on, status")
        .order("full_name"),
      supabase
        .from("students")
        .select("id, full_name, state, year_level")
        .order("full_name"),
      supabase
        .from("tutor_profiles")
        .select("account_id, account:accounts(full_name)"),
      supabase.from("tutor_cleared_states").select("tutor_id, state"),
      supabase.rpc("upcoming_deletions", { p_days: 30 }),
      supabase
        .from("retention_holds")
        .select(
          "id, reason, placed_at, student:students(full_name), account:accounts!retention_holds_account_id_fkey(full_name)",
        )
        .is("released_at", null)
        .order("placed_at"),
      supabase
        .from("retention_rules")
        .select("kind, keep_for, description")
        .order("kind"),
    ]);
  const teachingList = await supabase
    .from("tutor_teaching")
    .select("tutor_id, subject, from_level, to_level")
    .order("subject");
  const teachingByTutor = new Map<string, string[]>();
  for (const t of teachingList.data ?? []) {
    const range = t.from_level === t.to_level ? t.from_level : `${t.from_level} to ${t.to_level}`;
    teachingByTutor.set(t.tutor_id, [...(teachingByTutor.get(t.tutor_id) ?? []), `${t.subject} (${range})`]);
  }
  const pendingChecks = await supabase
    .from("tutor_checks")
    .select(
      "id, kind, reference, completed_on, expires_on, submitted_at, tutor:tutor_profiles(account:accounts(full_name))",
    )
    .is("verified_at", null)
    .is("declined_at", null)
    .order("submitted_at");
  const pendingCheckRows = (pendingChecks.data ?? []) as unknown as {
    id: string;
    kind: string;
    reference: string | null;
    completed_on: string | null;
    expires_on: string;
    submitted_at: string | null;
    tutor: { account: { full_name: string } | null } | null;
  }[];
  const frameworkList = await supabase
    .from("curriculum_frameworks")
    .select("id, code, name, version, confirmed_at, source")
    .eq("active", true)
    .order("code");
  const frameworks = (frameworkList.data ?? []).map((f) => ({
    id: f.id as string,
    code: f.code as string,
    name: `${f.code}: ${f.name} (v${f.version})`,
    confirmed: Boolean(f.confirmed_at),
    source: (f.source as string | null) ?? null,
  }));
  const frameworkOptions = frameworks.map(({ id, name }) => ({ id, name }));
  const confirmedOptions = frameworks
    .filter((f) => f.confirmed)
    .map(({ id, name }) => ({ id, name }));
  const drafts = await Promise.all(
    frameworks
      .filter((f) => !f.confirmed)
      .map(async (f) => {
        const summary = await supabase.rpc("curriculum_summary", {
          p_framework: f.id,
        });
        return {
          ...f,
          summary: (summary.data ?? []) as {
            subject: string;
            level_band: string;
            skills: number;
          }[],
        };
      }),
  );
  const isOwner = me.data?.level === "owner";
  const dueRows = (due.data ?? []) as Due[];
  const holdRows = (holds.data ?? []) as unknown as Hold[];
  const ruleRows = (rules.data ?? []) as Rule[];

  const eligible = studentId
    ? await supabase.rpc("eligible_tutors", { p_student: studentId })
    : null;
  const eligibleRows = (eligible?.data ?? []) as Eligible[];
  const statesByTutor = new Map<string, string[]>();
  for (const row of cleared.data ?? []) {
    statesByTutor.set(row.tutor_id, [
      ...(statesByTutor.get(row.tutor_id) ?? []),
      row.state,
    ]);
  }

  const checkRows = (checks.data ?? []) as CheckRow[];
  const tutors = (
    (tutorList.data ?? []) as unknown as {
      account_id: string;
      account: { full_name: string } | null;
    }[]
  )
    .map((t) => ({ id: t.account_id, name: t.account?.full_name ?? "Tutor" }))
    .sort((a, b) => a.name.localeCompare(b.name));
  const studentRows = (students.data ?? []) as {
    id: string;
    full_name: string;
    state: AuState;
    year_level: string | null;
  }[];
  const chosen = studentRows.find((s) => s.id === studentId);
  const pendingLinks = (
    (pending.data ?? []) as unknown as (Omit<PendingLink, "parent"> & {
      parent: { account: { full_name: string } | null } | null;
    })[]
  ).map((l) => ({ ...l, parent: l.parent?.account ?? null }));

  return (
    <>
      <RoleTabs roles={viewer.roles} active="admin" />
      <SectionShell
        basePath="/admin"
        label="Admin"
        section={section}
        sections={ADMIN_SECTIONS.map((s) => ({
          ...s,
          count:
            s.id === "families"
              ? pendingLinks.length
              : s.id === "tutors"
                ? pendingCheckRows.length
                : s.id === "curriculum" && drafts.length
                  ? drafts.length
                  : s.id === "records"
                    ? dueRows.length
                    : undefined,
        }))}
      >
        {section === "families" && (
          <>
            <Card
              title="Parent links to confirm"
              description={
                <>
                  Confirm each parent and child before a tutor can be assigned.
                </>
              }
            >
              {pendingLinks.length === 0 ? (
                <Empty>Nothing waiting.</Empty>
              ) : (
                <ul className="space-y-2 text-sm">
                  {pendingLinks.map((l) => (
                    <li
                      key={`${l.parent_id}-${l.student_id}`}
                      className="flex items-center justify-between gap-4"
                    >
                      <span>
                        {l.parent?.full_name ?? "Parent"} ({l.relationship}) of{" "}
                        {l.student?.full_name}, born {l.student?.date_of_birth}
                      </span>
                      <form action={verifyParentLink}>
                        <input
                          type="hidden"
                          name="parent_id"
                          value={l.parent_id}
                        />
                        <input
                          type="hidden"
                          name="student_id"
                          value={l.student_id}
                        />
                        <Button type="submit">Confirm</Button>
                      </form>
                    </li>
                  ))}
                </ul>
              )}
            </Card>

            <Card title="Assign a tutor">
              <form method="get" className="mb-4 flex items-end gap-3">
                <input type="hidden" name="section" value="families" />
                <label className="block flex-1 space-y-1">
                  <span className="text-sm font-medium">Student</span>
                  <select
                    name="student"
                    defaultValue={studentId ?? ""}
                    className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"
                  >
                    <option value="" disabled>
                      Choose…
                    </option>
                    {studentRows.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.full_name} ({s.state})
                      </option>
                    ))}
                  </select>
                </label>
                <Button type="submit">Find tutors</Button>
              </form>
              {chosen && (
                <>
                  <p className="mb-2 text-sm">
                    Tutors cleared for {STATE_NAMES[chosen.state]} who teach {chosen.year_level ?? "this year level"}:
                  </p>
                  {eligibleRows.length === 0 ? (
                    <p className="text-sm text-red-700">
                      No tutor is both cleared for this student and has added a subject they teach at this year level.
                      Tutors add their subjects under &quot;What you teach&quot; in their dashboard.
                    </p>
                  ) : (
                    <>
                      <ul className="mb-4 list-disc pl-5 text-sm">
                        {eligibleRows.map((t) => (
                          <li key={t.tutor_id}>
                            {t.full_name}
                            {t.subjects.length > 0 &&
                              `: ${t.subjects.join(", ")}`}
                            {t.max_weekly_hours != null &&
                              ` (up to ${t.max_weekly_hours} h/week)`}
                          </li>
                        ))}
                      </ul>
                      <AssignForm
                        studentId={chosen.id}
                        tutors={eligibleRows.map((t) => ({
                          id: t.tutor_id,
                          name: t.full_name,
                          subjects: t.subjects,
                        }))}
                      />
                    </>
                  )}
                </>
              )}
            </Card>
          </>
        )}

        {section === "tutors" && (
          <>
            <Card
              title="Checks to confirm"
              description="Checks tutors have added themselves. Confirm each one against the official screening or training record before it counts."
            >
              {pendingCheckRows.length === 0 ? (
                <Empty>Nothing waiting.</Empty>
              ) : (
                <ul className="divide-y divide-zinc-100">
                  {pendingCheckRows.map((c) => (
                    <li
                      key={c.id}
                      className="space-y-3 py-4 text-sm first:pt-0 last:pb-0"
                    >
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div>
                          <p className="font-medium">
                            {c.tutor?.account?.full_name ?? "Tutor"}:{" "}
                            {checkName(c.kind)}
                          </p>
                          <p className="text-zinc-600">
                            {c.reference && `Number ${c.reference} · `}
                            {c.completed_on && `Done ${c.completed_on} · `}
                            Due again {c.expires_on}
                          </p>
                        </div>
                        <form action={confirmCheck}>
                          <input type="hidden" name="check_id" value={c.id} />
                          <Button type="submit">Confirm</Button>
                        </form>
                      </div>
                      <details className="rounded-xl bg-zinc-50 px-4 py-2">
                        <summary className="cursor-pointer text-zinc-700">
                          Doesn&apos;t match? Send it back
                        </summary>
                        <div className="pt-3">
                          <DeclineCheckForm checkId={c.id} />
                        </div>
                      </details>
                    </li>
                  ))}
                </ul>
              )}
            </Card>

            <Card title="Tutor child safety checks">
              {checkRows.length === 0 ? (
                <Empty>
                  No tutors yet. Checks appear here once tutors are added.
                </Empty>
              ) : (
                <Table headings={["Tutor", "Check", "Expires", "Status"]}>
                  {checkRows.map((c) => (
                    <tr
                      key={`${c.tutor_id}-${c.kind}`}
                      className={c.status === "current" ? "" : "text-red-700"}
                    >
                      <td className="font-medium">{c.full_name}</td>
                      <td>{checkName(c.kind)}</td>
                      <td>{c.expires_on ?? "-"}</td>
                      <td>{c.status.replace("_", " ")}</td>
                    </tr>
                  ))}
                </Table>
              )}
            </Card>

            <Card title="Record a check">
              <CheckForm tutors={tutors} />
            </Card>

            <Card title="States each tutor is cleared for">
              <ul className="space-y-1 text-sm">
                {tutors.map((t) => (
                  <li key={t.id}>
                    {t.name}:{" "}
                    {(statesByTutor.get(t.id) ?? []).join(", ") || "none yet"}
                  </li>
                ))}
              </ul>
            </Card>

            <Card title="What each tutor teaches" description="Tutors add these themselves in their dashboard.">
              <ul className="space-y-1 text-sm">
                {tutors.map((t) => (
                  <li key={t.id}>
                    {t.name}: {(teachingByTutor.get(t.id) ?? []).join(", ") || "not added yet"}
                  </li>
                ))}
              </ul>
            </Card>

            <Card title="Tutor work state">
              <WorkStateForm tutors={tutors} />
            </Card>

            <Card title="Tutor finished with CLG">
              <TutorLeftForm tutors={tutors} />
            </Card>
          </>
        )}

        {section === "curriculum" && (
          <>
            {drafts.length > 0 && (
              <Card
                title={`Curricula to check and confirm (${drafts.length})`}
                description="Each one is a draft until you confirm it. Open one to see how many skills it has for each year, then confirm it so tutors can use it in goals."
              >
                <ul className="divide-y divide-zinc-100">
                  {drafts.map((d) => {
                    const total = d.summary.reduce((n, r) => n + Number(r.skills), 0);
                    return (
                      <li key={d.id} className="py-3 first:pt-0">
                        <details>
                          <summary className="cursor-pointer text-sm">
                            <span className="font-medium">{d.name}</span>{" "}
                            <span className="text-zinc-600">({total.toLocaleString("en-AU")} skills)</span>
                          </summary>
                          <div className="mt-3 space-y-3">
                            {total === 0 ? (
                              <Empty>No skills loaded yet.</Empty>
                            ) : (
                              <div className="max-h-64 overflow-y-auto">
                                <Table headings={["Subject", "Year or level", "Skills"]}>
                                  {d.summary.map((r) => (
                                    <tr key={`${r.subject}-${r.level_band}`}>
                                      <td className="font-medium">{r.subject}</td>
                                      <td>{r.level_band}</td>
                                      <td>{r.skills}</td>
                                    </tr>
                                  ))}
                                </Table>
                              </div>
                            )}
                            {d.source && <p className="text-xs text-zinc-500">Source: {d.source}</p>}
                          </div>
                        </details>
                        <div className="mt-2 flex flex-wrap gap-3">
                          {total > 0 && (
                            <form action={confirmCurriculum}>
                              <input type="hidden" name="framework_id" value={d.id} />
                              <button type="submit" className="text-sm font-medium text-teal-800 underline">
                                Confirm
                              </button>
                            </form>
                          )}
                          <form action={discardCurriculum}>
                            <input type="hidden" name="framework_id" value={d.id} />
                            <button type="submit" className="text-sm text-red-700 underline">
                              Throw away
                            </button>
                          </form>
                        </div>
                      </li>
                    );
                  })}
                </ul>
                {drafts.length > 1 && (
                  <form action={confirmAllCurricula} className="mt-4">
                    <Button type="submit">Confirm all {drafts.length}</Button>
                  </form>
                )}
              </Card>
            )}

            <Card
              title="Load the Australian Curriculum"
              description="Load many subjects at once from ACARA's curriculum file."
            >
              <AcaraImportForm loadedCodes={frameworks.map((f) => f.code)} />
            </Card>

            <Card
              title="Curriculum and skills"
              description="Goals are built from these skills. Load each curriculum once, confirm it, then set which one applies to each student."
            >
              {frameworks.length === 0 ? (
                <Empty>No curriculum loaded yet.</Empty>
              ) : (
                <ul className="mb-2 space-y-1 text-sm">
                  {frameworks.map((f) => (
                    <li
                      key={f.id}
                      className="flex flex-wrap items-center gap-2"
                    >
                      <span className="font-medium">{f.name}</span>
                      {f.confirmed ? (
                        <span className="rounded-full bg-teal-50 px-2 text-xs text-teal-800">
                          In use
                        </span>
                      ) : (
                        <span className="rounded-full bg-zinc-100 px-2 text-xs text-zinc-600">
                          Draft
                        </span>
                      )}
                    </li>
                  ))}
                </ul>
              )}
              <SubHeading>Set a student&apos;s curriculum</SubHeading>
              <StudentFrameworkForm
                students={studentRows.map((s) => ({
                  id: s.id,
                  name: `${s.full_name} (${s.state})`,
                }))}
                frameworks={confirmedOptions}
              />
              <SubHeading>Load skills by pasting rows</SubHeading>
              <ImportSkillsForm frameworks={frameworkOptions} />
              <SubHeading>Add a curriculum</SubHeading>
              <FrameworkForm />
            </Card>
          </>
        )}

        {section === "staff" && (
          <>
            <Card title="Add staff">
              <InviteForm canInviteAdmins={isOwner} />
            </Card>

            <Card title="Unlock an account">
              <UnlockForm />
            </Card>
          </>
        )}

        {section === "records" && (
          <>
            <Card
              title="Records due for deletion"
              description={
                <>
                  The app deletes records automatically each night once CLG no
                  longer needs them. These are due in the next 30 days. Place a
                  hold to keep any of them, for example while a complaint or
                  concern is open.
                </>
              }
            >
              {dueRows.length === 0 ? (
                <Empty>Nothing due in the next 30 days.</Empty>
              ) : (
                <>
                  <div className="mb-6">
                    <Table headings={["Name", "Type", "Deleted on"]}>
                      {dueRows.map((d) => (
                        <tr key={`${d.kind}-${d.record_id}`}>
                          <td className="font-medium">{d.full_name}</td>
                          <td>{DUE_LABELS[d.kind]}</td>
                          <td>{d.due_on}</td>
                        </tr>
                      ))}
                    </Table>
                  </div>
                  <HoldForm
                    due={dueRows.map((d) => ({
                      value: `${d.kind === "student" ? "student" : "account"}:${d.record_id}`,
                      label: `${d.full_name} (${DUE_LABELS[d.kind].toLowerCase()})`,
                    }))}
                  />
                </>
              )}
            </Card>

            <Card title="Holds">
              {holdRows.length === 0 ? (
                <Empty>No holds in place.</Empty>
              ) : (
                <ul className="space-y-2 text-sm">
                  {holdRows.map((h) => (
                    <li
                      key={h.id}
                      className="flex items-center justify-between gap-4"
                    >
                      <span>
                        {h.student?.full_name ??
                          h.account?.full_name ??
                          "Deleted record"}
                        : {h.reason} (since {h.placed_at.slice(0, 10)})
                      </span>
                      <form action={releaseHold}>
                        <input type="hidden" name="hold_id" value={h.id} />
                        <Button type="submit">Release</Button>
                      </form>
                    </li>
                  ))}
                </ul>
              )}
            </Card>

            <Card title="How long records are kept">
              <ul className="mb-4 space-y-1 text-sm">
                {ruleRows.map((r) => (
                  <li key={r.kind}>
                    <strong>
                      {RULE_LABELS[r.kind] ?? r.kind}: {plainPeriod(r.keep_for)}
                      .
                    </strong>{" "}
                    {r.description}
                  </li>
                ))}
              </ul>
              {isOwner && (
                <RetentionPeriodForm
                  rules={ruleRows.map((r) => ({
                    kind: r.kind,
                    label: RULE_LABELS[r.kind] ?? r.kind,
                  }))}
                />
              )}
            </Card>

            {isOwner && (
              <Card
                title="Delete a student on request"
                description={
                  <>
                    When a family asks for their child&apos;s information to be
                    deleted. Billing and child safety records kept elsewhere are
                    not affected.
                  </>
                }
              >
                <EraseStudentForm
                  students={studentRows.map((s) => ({
                    id: s.id,
                    name: s.full_name,
                  }))}
                />
              </Card>
            )}
          </>
        )}
      </SectionShell>
    </>
  );
}
