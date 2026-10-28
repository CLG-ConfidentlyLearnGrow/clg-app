import { Card, TextLink } from "@/components/ui";
import { sessionWhen } from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";

export type Student = {
  id: string;
  full_name: string;
  date_of_birth: string | null;
  state: string | null;
  year_level: string | null;
  school: string | null;
  goals: string | null;
  extra_info: string | null;
};
export type Assignment = {
  id: string;
  subject: string;
  student_id: string;
  tutor: { account: { full_name: string } | null; bio: string | null } | null;
};

// Students and tutor assignments this person may see. The database decides
// which rows come back.
export async function loadStudentsAndTutors() {
  const supabase = await createClient();
  const [students, assignments] = await Promise.all([
    supabase.from("students").select("id, full_name, date_of_birth, state, year_level, school, goals, extra_info").order("full_name"),
    supabase
      .from("tutor_assignments")
      .select("id, subject, student_id, tutor:tutor_profiles(bio, account:accounts(full_name))"),
  ]);
  return {
    students: (students.data ?? []) as Student[],
    assignments: (assignments.data ?? []) as unknown as Assignment[],
  };
}

export function TutorList({ assignments }: { assignments: Assignment[] }) {
  if (assignments.length === 0) return null;
  return (
    <ul className="mt-1 list-disc pl-5 text-zinc-700">
      {assignments.map((a) => (
        <li key={a.id}>
          {a.subject} with {a.tutor?.account?.full_name ?? "your tutor"}
        </li>
      ))}
    </ul>
  );
}

type Update = { id: string; student_id: string; title: string; body: string; deliver_at: string };

// New session notes since the family last looked: what went well is on the
// progress page; here is the next step and the tip for home. Opening the
// progress page marks them as seen. Shows nothing when there is nothing new.
export async function NewUpdates({ studentIds }: { studentIds?: string[] }) {
  const supabase = await createClient();
  const res = await supabase
    .from("progress_notices")
    .select("id, student_id, title, body, deliver_at")
    .eq("kind", "session_update")
    .is("read_at", null)
    .order("deliver_at", { ascending: false })
    .limit(10);
  const updates = ((res.data ?? []) as Update[]).filter((u) => !studentIds || studentIds.includes(u.student_id));
  if (updates.length === 0) return null;
  return (
    <Card title="New from your tutor">
      <ul className="divide-y divide-zinc-100 text-sm">
        {updates.map((u) => (
          <li key={u.id} className="py-3 first:pt-0 last:pb-0">
            <p className="flex flex-wrap items-baseline justify-between gap-2">
              <span className="font-medium">{u.title}</span>
              <span className="text-xs text-zinc-500">{sessionWhen(u.deliver_at)}</span>
            </p>
            <p className="mt-1 whitespace-pre-line text-zinc-700">{u.body}</p>
            <p className="mt-1">
              <TextLink href={`/students/${u.student_id}/progress?view=family`}>See the full note</TextLink>
            </p>
          </li>
        ))}
      </ul>
    </Card>
  );
}

// Details the family still needs to give (for children set up by CLG).
export function missingDetails(s: Student, subjectCount: number): string[] {
  const missing: string[] = [];
  if (!s.date_of_birth) missing.push("date of birth");
  if (!s.state) missing.push("state");
  if (!s.year_level) missing.push("year level");
  if (!s.school) missing.push("school");
  if (subjectCount === 0) missing.push("subjects");
  if (!s.goals) missing.push("end goal");
  return missing;
}
