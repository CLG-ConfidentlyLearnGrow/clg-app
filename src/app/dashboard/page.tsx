import { redirect } from "next/navigation";
import { signOut } from "@/app/actions/auth";
import { Button, Card, Page, TextLink } from "@/components/ui";
import { needsTwoStep, requireViewer, type Viewer } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { removeAvailability } from "@/app/actions/tutor";
import { STATE_NAMES, WEEKDAYS, checkName, type AuState } from "@/lib/checks";
import { AddChildForm } from "./add-child-form";
import { AvailabilityForm, MaxHoursForm } from "./tutor-forms";

type Student = { id: string; full_name: string; year_level: string | null; school: string | null };
type Assignment = {
  id: string;
  subject: string;
  student_id: string;
  tutor: { account: { full_name: string } | null; bio: string | null } | null;
};
type CheckStatus = { kind: string; expires_on: string | null; status: string };


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
      <p className="text-sm">
        <TextLink href="/install">Add CLG to your phone&apos;s home screen</TextLink>
      </p>
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
  const [checks, states, settings, slots] = await Promise.all([
    supabase.from("tutor_check_status").select("kind, expires_on, status").eq("tutor_id", viewer.id),
    supabase.from("tutor_cleared_states").select("state").eq("tutor_id", viewer.id),
    supabase.from("tutor_work_settings").select("max_weekly_hours").eq("tutor_id", viewer.id).maybeSingle(),
    supabase
      .from("tutor_availability")
      .select("id, weekday, starts_at, ends_at")
      .eq("tutor_id", viewer.id)
      .order("weekday")
      .order("starts_at"),
  ]);

  const rows = (checks.data ?? []) as CheckStatus[];
  const clearedStates = (states.data ?? []).map((s) => STATE_NAMES[s.state as AuState] ?? s.state);
  const problems = rows.filter((c) => c.status === "expired" || c.status === "missing");

  return (
    <>
      <Card title="Your students">
        {problems.length > 0 && (
          <p className="mb-3 text-sm text-red-700">
            Some of your checks are missing or expired, so students who need them are hidden. Please contact CLG.
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
          {rows.length === 0 && <li>No checks recorded yet. Send CLG your check details to get started.</li>}
          {rows.map((c) => (
            <li key={c.kind} className={c.status === "current" ? "" : "text-red-700"}>
              {checkName(c.kind)}: {c.status.replace("_", " ")}
              {c.expires_on && ` (expires ${c.expires_on})`}
            </li>
          ))}
        </ul>
        <p className="mt-3 text-sm">
          You can currently be matched with students in:{" "}
          <strong>{clearedStates.length ? clearedStates.join(", ") : "no states yet"}</strong>.
        </p>
        <p className="mt-2 text-xs text-zinc-600 dark:text-zinc-400">
          Each state needs its own check (South Australia also needs RRHAN-EC Fundamentals and Masterclass). The more
          states you are cleared for, the more students you can be matched with when a suitable match comes up. No
          number of students or hours is guaranteed, whatever checks or availability you have.
        </p>
      </Card>
      <Card title="Your hours and availability">
        <p className="mb-3 text-sm text-zinc-600 dark:text-zinc-400">
          These are separate: your availability is when you could teach, and your weekly limit is the most hours you
          can work in total.
        </p>
        <MaxHoursForm current={settings.data?.max_weekly_hours ?? null} />
        <h3 className="mt-6 mb-2 text-sm font-semibold">Times you are available</h3>
        <ul className="mb-4 space-y-1 text-sm">
          {(slots.data ?? []).length === 0 && <li>None added yet.</li>}
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
    </>
  );
}
