import { redirect } from "next/navigation";
import { signOut } from "@/app/actions/auth";
import { Button, Card, Page, TextLink } from "@/components/ui";
import { needsTwoStep, requireViewer, type Viewer } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AddChildForm } from "./add-child-form";

type Student = { id: string; full_name: string; year_level: string | null; school: string | null };
type Assignment = {
  id: string;
  subject: string;
  student_id: string;
  tutor: { account: { full_name: string } | null; bio: string | null } | null;
};
type CheckStatus = { kind: string; expires_on: string | null; status: string };

const CHECK_NAMES: Record<string, string> = {
  wwcc: "Working With Children Check",
  rrhan_ec_fundamentals: "RRHAN-EC Fundamentals",
  rrhan_ec_masterclass: "RRHAN-EC Masterclass",
};

export default async function DashboardPage() {
  const viewer = await requireViewer();
  if (needsTwoStep(viewer)) redirect("/mfa");

  return (
    <Page title={`Welcome${viewer.fullName ? `, ${viewer.fullName}` : ""}`}>
      {viewer.roles.includes("admin") && (
        <Card title="Admin">
          <TextLink href="/admin">Open admin tools</TextLink>
        </Card>
      )}
      {viewer.roles.includes("tutor") && <TutorSection viewer={viewer} />}
      {viewer.roles.includes("parent") && <ParentSection />}
      {viewer.roles.includes("student") && <StudentSection />}
      <form action={signOut}>
        <Button type="submit">Sign out</Button>
      </form>
    </Page>
  );
}

async function loadStudentsAndTutors() {
  const supabase = await createClient();
  const [students, assignments] = await Promise.all([
    supabase.from("students").select("id, full_name, year_level, school").order("full_name"),
    supabase
      .from("tutor_assignments")
      .select("id, subject, student_id, tutor:tutor_profiles(bio, account:accounts(full_name))"),
  ]);
  return {
    students: (students.data ?? []) as Student[],
    assignments: (assignments.data ?? []) as unknown as Assignment[],
  };
}

async function ParentSection() {
  const supabase = await createClient();
  const { students, assignments } = await loadStudentsAndTutors();
  const links = await supabase.from("parent_student_links").select("student_id, verified_at");
  const verified = new Set((links.data ?? []).filter((l) => l.verified_at).map((l) => l.student_id));

  return (
    <>
      <Card title="Your children">
        {students.length === 0 ? (
          <p className="text-sm">Add your child below to get started.</p>
        ) : (
          <ul className="space-y-3">
            {students.map((s) => (
              <li key={s.id} className="text-sm">
                <span className="font-medium">{s.full_name}</span>
                {s.year_level && `, ${s.year_level}`}
                {!verified.has(s.id) && <span className="ml-2 text-zinc-500">(CLG is confirming the details)</span>}
                <TutorList assignments={assignments.filter((a) => a.student_id === s.id)} />
              </li>
            ))}
          </ul>
        )}
      </Card>
      <Card title="Add a child">
        <AddChildForm />
      </Card>
    </>
  );
}

async function StudentSection() {
  const { assignments } = await loadStudentsAndTutors();
  return (
    <Card title="Your tutors">
      {assignments.length === 0 ? <p className="text-sm">No tutor yet.</p> : <TutorList assignments={assignments} />}
    </Card>
  );
}

function TutorList({ assignments }: { assignments: Assignment[] }) {
  if (assignments.length === 0) return null;
  return (
    <ul className="mt-1 list-disc pl-5 text-zinc-700 dark:text-zinc-300">
      {assignments.map((a) => (
        <li key={a.id}>
          {a.subject} with {a.tutor?.account?.full_name ?? "your tutor"}
        </li>
      ))}
    </ul>
  );
}

async function TutorSection({ viewer }: { viewer: Viewer }) {
  const supabase = await createClient();
  const { students } = await loadStudentsAndTutors();
  const checks = await supabase
    .from("tutor_check_status")
    .select("kind, expires_on, status")
    .eq("tutor_id", viewer.id);

  const rows = (checks.data ?? []) as CheckStatus[];
  const cleared = rows.length > 0 && rows.every((c) => c.status === "current" || c.status === "expiring_soon");

  return (
    <>
      <Card title="Your students">
        {!cleared && (
          <p className="mb-3 text-sm text-red-700">
            Your students are hidden until all your checks below are current. Please contact CLG.
          </p>
        )}
        {students.length === 0 ? (
          <p className="text-sm">No students assigned yet.</p>
        ) : (
          <ul className="list-disc pl-5 text-sm">
            {students.map((s) => (
              <li key={s.id}>
                {s.full_name}
                {s.year_level && `, ${s.year_level}`}
              </li>
            ))}
          </ul>
        )}
      </Card>
      <Card title="Your child safety checks">
        <ul className="space-y-1 text-sm">
          {rows.map((c) => (
            <li key={c.kind}>
              {CHECK_NAMES[c.kind] ?? c.kind}: {c.status.replace("_", " ")}
              {c.expires_on && ` (expires ${c.expires_on})`}
            </li>
          ))}
        </ul>
      </Card>
    </>
  );
}
