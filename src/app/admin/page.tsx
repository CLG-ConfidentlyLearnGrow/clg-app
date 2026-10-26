import { verifyParentLink } from "@/app/actions/admin";
import { Button, Card, Page, TextLink } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { STATE_NAMES, checkName, type AuState } from "@/lib/checks";
import { AssignForm, CheckForm, InviteForm, UnlockForm, WorkStateForm } from "./forms";

type PendingLink = {
  parent_id: string;
  student_id: string;
  relationship: string;
  parent: { full_name: string } | null;
  student: { full_name: string; date_of_birth: string } | null;
};
type CheckRow = { tutor_id: string; full_name: string; kind: string; expires_on: string | null; status: string };

type Eligible = { tutor_id: string; full_name: string; subjects: string[]; max_weekly_hours: number | null };

export default async function AdminPage({ searchParams }: PageProps<"/admin">) {
  const viewer = await requireAdmin();
  const supabase = await createClient();
  const { student } = await searchParams;
  const studentId = typeof student === "string" ? student : null;

  const [me, pending, checks, students, tutorList, cleared] = await Promise.all([
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
  ]);

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
    <Page title="Admin">
      <p className="text-sm">
        <TextLink href="/dashboard">Back to dashboard</TextLink>
      </p>

      <Card title="Parent links to confirm">
        <p className="mb-3 text-sm text-zinc-600 dark:text-zinc-400">
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

      <Card title="Assign a tutor">
        <form method="get" className="mb-4 flex items-end gap-3">
          <label className="block flex-1 space-y-1">
            <span className="text-sm font-medium">Student</span>
            <select
              name="student"
              defaultValue={studentId ?? ""}
              className="w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
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

      <Card title="Invite staff">
        <InviteForm canInviteAdmins={me.data?.level === "owner"} />
      </Card>

      <Card title="Unlock an account">
        <UnlockForm />
      </Card>
    </Page>
  );
}
