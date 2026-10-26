import { verifyParentLink } from "@/app/actions/admin";
import { Button, Card, Page, TextLink } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AssignForm, CheckForm, InviteForm, UnlockForm } from "./forms";

type PendingLink = {
  parent_id: string;
  student_id: string;
  relationship: string;
  parent: { full_name: string } | null;
  student: { full_name: string; date_of_birth: string } | null;
};
type CheckRow = { tutor_id: string; full_name: string; kind: string; expires_on: string | null; status: string };

const CHECK_NAMES: Record<string, string> = {
  wwcc: "WWCC",
  rrhan_ec_fundamentals: "RRHAN-EC Fundamentals",
  rrhan_ec_masterclass: "RRHAN-EC Masterclass",
};

export default async function AdminPage() {
  const viewer = await requireAdmin();
  const supabase = await createClient();

  const [me, pending, checks, students] = await Promise.all([
    supabase.from("admin_profiles").select("level").eq("account_id", viewer.id).maybeSingle(),
    supabase
      .from("parent_student_links")
      .select(
        "parent_id, student_id, relationship, parent:parent_profiles(account:accounts(full_name)), student:students(full_name, date_of_birth)",
      )
      .is("verified_at", null),
    supabase.from("tutor_check_status").select("tutor_id, full_name, kind, expires_on, status").order("full_name"),
    supabase.from("students").select("id, full_name").order("full_name"),
  ]);

  const checkRows = (checks.data ?? []) as CheckRow[];
  const tutors = Array.from(new Map(checkRows.map((c) => [c.tutor_id, { id: c.tutor_id, name: c.full_name }])).values());
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
                <td>{CHECK_NAMES[c.kind] ?? c.kind}</td>
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

      <Card title="Assign a tutor">
        <AssignForm
          tutors={tutors}
          students={(students.data ?? []).map((s) => ({ id: s.id, name: s.full_name }))}
        />
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
