import { releaseHold, verifyParentLink } from "@/app/actions/admin";
import { Button, Card } from "@/components/ui";
import { AdminShell } from "./admin-shell";
import { ADMIN_SECTIONS, sectionFrom } from "./sections";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { STATE_NAMES, checkName, type AuState } from "@/lib/checks";
import {
  AssignForm,
  CheckForm,
  EraseStudentForm,
  HoldForm,
  InviteForm,
  RetentionPeriodForm,
  TutorLeftForm,
  UnlockForm,
  WorkStateForm,
} from "./forms";
import { FrameworkForm, ImportSkillsForm, StudentFrameworkForm } from "./curriculum-forms";

type PendingLink = {
  parent_id: string;
  student_id: string;
  relationship: string;
  parent: { full_name: string } | null;
  student: { full_name: string; date_of_birth: string } | null;
};
type CheckRow = { tutor_id: string; full_name: string; kind: string; expires_on: string | null; status: string };

type Due = { kind: "student" | "account" | "tutor"; record_id: string; full_name: string; due_on: string };
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

type Eligible = { tutor_id: string; full_name: string; subjects: string[]; max_weekly_hours: number | null };

export default async function AdminPage({ searchParams }: PageProps<"/admin">) {
  const viewer = await requireAdmin();
  const supabase = await createClient();
  const params = await searchParams;
  const studentId = typeof params.student === "string" ? params.student : null;
  const section = sectionFrom(params.section);

  const [me, pending, checks, students, tutorList, cleared, due, holds, rules] = await Promise.all([
    supabase.from("admin_profiles").select("level").eq("account_id", viewer.id).maybeSingle(),
    supabase
      .from("parent_student_links")
      .select(
        "parent_id, student_id, relationship, parent:parent_profiles(account:accounts(full_name)), student:students(full_name, date_of_birth)",
      )
      .is("verified_at", null),
    supabase.from("tutor_check_status").select("tutor_id, full_name, kind, expires_on, status").order("full_name"),
    supabase.from("students").select("id, full_name, state").order("full_name"),
    supabase.from("tutor_profiles").select("account_id, account:accounts(full_name)"),
    supabase.from("tutor_cleared_states").select("tutor_id, state"),
    supabase.rpc("upcoming_deletions", { p_days: 30 }),
    supabase
      .from("retention_holds")
      .select("id, reason, placed_at, student:students(full_name), account:accounts!retention_holds_account_id_fkey(full_name)")
      .is("released_at", null)
      .order("placed_at"),
    supabase.from("retention_rules").select("kind, keep_for, description").order("kind"),
  ]);
  const frameworkList = await supabase
    .from("curriculum_frameworks")
    .select("id, code, name, version")
    .eq("active", true)
    .order("code");
  const frameworkOptions = (frameworkList.data ?? []).map((f) => ({
    id: f.id,
    name: `${f.code}: ${f.name} (v${f.version})`,
  }));
  const isOwner = me.data?.level === "owner";
  const dueRows = (due.data ?? []) as Due[];
  const holdRows = (holds.data ?? []) as unknown as Hold[];
  const ruleRows = (rules.data ?? []) as Rule[];

  const eligible = studentId ? await supabase.rpc("eligible_tutors", { p_student: studentId }) : null;
  const eligibleRows = (eligible?.data ?? []) as Eligible[];
  const statesByTutor = new Map<string, string[]>();
  for (const row of cleared.data ?? []) {
    statesByTutor.set(row.tutor_id, [...(statesByTutor.get(row.tutor_id) ?? []), row.state]);
  }

  const checkRows = (checks.data ?? []) as CheckRow[];
  const tutors = ((tutorList.data ?? []) as unknown as { account_id: string; account: { full_name: string } | null }[])
    .map((t) => ({ id: t.account_id, name: t.account?.full_name ?? "Tutor" }))
    .sort((a, b) => a.name.localeCompare(b.name));
  const studentRows = (students.data ?? []) as { id: string; full_name: string; state: AuState }[];
  const chosen = studentRows.find((s) => s.id === studentId);
  const pendingLinks = ((pending.data ?? []) as unknown as (Omit<PendingLink, "parent"> & {
    parent: { account: { full_name: string } | null } | null;
  })[]).map((l) => ({ ...l, parent: l.parent?.account ?? null }));

  return (
    <AdminShell
      section={section}
      sections={ADMIN_SECTIONS.map((s) => ({
        ...s,
        count: s.id === "families" ? pendingLinks.length : s.id === "records" ? dueRows.length : undefined,
      }))}
    >
      {section === "families" && (
        <>
          <Card title="Parent links to confirm">
            <p className="mb-3 text-sm text-zinc-600">
              Confirm each parent and child before a tutor can be assigned.
            </p>
            {pendingLinks.length === 0 ? (
              <p className="text-sm">Nothing waiting.</p>
            ) : (
              <ul className="space-y-2 text-sm">
                {pendingLinks.map((l) => (
                  <li key={`${l.parent_id}-${l.student_id}`} className="flex items-center justify-between gap-4">
                    <span>
                      {l.parent?.full_name ?? "Parent"} ({l.relationship}) of {l.student?.full_name}, born{" "}
                      {l.student?.date_of_birth}
                    </span>
                    <form action={verifyParentLink}>
                      <input type="hidden" name="parent_id" value={l.parent_id} />
                      <input type="hidden" name="student_id" value={l.student_id} />
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
                  className="w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm"
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
                  Tutors cleared for students in {STATE_NAMES[chosen.state]}:
                </p>
                {eligibleRows.length === 0 ? (
                  <p className="text-sm text-red-700">No tutor currently holds every check this student needs.</p>
                ) : (
                  <>
                    <ul className="mb-4 list-disc pl-5 text-sm">
                      {eligibleRows.map((t) => (
                        <li key={t.tutor_id}>
                          {t.full_name}
                          {t.subjects.length > 0 && `: ${t.subjects.join(", ")}`}
                          {t.max_weekly_hours != null && ` (up to ${t.max_weekly_hours} h/week)`}
                        </li>
                      ))}
                    </ul>
                    <AssignForm
                      studentId={chosen.id}
                      tutors={eligibleRows.map((t) => ({ id: t.tutor_id, name: t.full_name }))}
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
          <Card title="Tutor child safety checks">
            <table className="w-full text-left text-sm">
              <thead>
                <tr>
                  <th className="py-1">Tutor</th>
                  <th>Check</th>
                  <th>Expires</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {checkRows.map((c) => (
                  <tr key={`${c.tutor_id}-${c.kind}`} className={c.status === "current" ? "" : "text-red-700"}>
                    <td className="py-1">{c.full_name}</td>
                    <td>{checkName(c.kind)}</td>
                    <td>{c.expires_on ?? "-"}</td>
                    <td>{c.status.replace("_", " ")}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>

          <Card title="Record a check">
            <CheckForm tutors={tutors} />
          </Card>

          <Card title="States each tutor is cleared for">
            <ul className="space-y-1 text-sm">
              {tutors.map((t) => (
                <li key={t.id}>
                  {t.name}: {(statesByTutor.get(t.id) ?? []).join(", ") || "none yet"}
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
          <Card title="Curriculum and skills">
            <p className="mb-3 text-sm text-zinc-600">
              Goals are built from these skills. Load each curriculum once, then set which one applies to each student.
            </p>
            {frameworkOptions.length > 0 && (
              <ul className="mb-4 list-disc pl-5 text-sm">
                {frameworkOptions.map((f) => (
                  <li key={f.id}>{f.name}</li>
                ))}
              </ul>
            )}
            <h3 className="mb-2 text-sm font-semibold">Set a student&apos;s curriculum</h3>
            <StudentFrameworkForm
              students={studentRows.map((s) => ({ id: s.id, name: `${s.full_name} (${s.state})` }))}
              frameworks={frameworkOptions}
            />
            <h3 className="mt-6 mb-2 text-sm font-semibold">Load skills</h3>
            <ImportSkillsForm frameworks={frameworkOptions} />
            <h3 className="mt-6 mb-2 text-sm font-semibold">Add a curriculum</h3>
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
          <Card title="Records due for deletion">
            <p className="mb-3 text-sm text-zinc-600">
              The app deletes records automatically each night once CLG no longer needs them. These are due in the next 30
              days. Place a hold to keep any of them, for example while a complaint or concern is open.
            </p>
            {dueRows.length === 0 ? (
              <p className="text-sm">Nothing due in the next 30 days.</p>
            ) : (
              <>
                <table className="mb-4 w-full text-left text-sm">
                  <thead>
                    <tr>
                      <th className="py-1">Name</th>
                      <th>Type</th>
                      <th>Deleted on</th>
                    </tr>
                  </thead>
                  <tbody>
                    {dueRows.map((d) => (
                      <tr key={`${d.kind}-${d.record_id}`}>
                        <td className="py-1">{d.full_name}</td>
                        <td>{DUE_LABELS[d.kind]}</td>
                        <td>{d.due_on}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
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
              <p className="text-sm">No holds in place.</p>
            ) : (
              <ul className="space-y-2 text-sm">
                {holdRows.map((h) => (
                  <li key={h.id} className="flex items-center justify-between gap-4">
                    <span>
                      {h.student?.full_name ?? h.account?.full_name ?? "Deleted record"}: {h.reason} (since{" "}
                      {h.placed_at.slice(0, 10)})
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
                    {RULE_LABELS[r.kind] ?? r.kind}: {plainPeriod(r.keep_for)}.
                  </strong>{" "}
                  {r.description}
                </li>
              ))}
            </ul>
            {isOwner && (
              <RetentionPeriodForm rules={ruleRows.map((r) => ({ kind: r.kind, label: RULE_LABELS[r.kind] ?? r.kind }))} />
            )}
          </Card>

          {isOwner && (
            <Card title="Delete a student on request">
              <p className="mb-3 text-sm text-zinc-600">
                When a family asks for their child&apos;s information to be deleted. Billing and child safety records kept
                elsewhere are not affected.
              </p>
              <EraseStudentForm students={studentRows.map((s) => ({ id: s.id, name: s.full_name }))} />
            </Card>
          )}
        </>
      )}
    </AdminShell>
  );
}
