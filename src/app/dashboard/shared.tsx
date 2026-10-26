import { createClient } from "@/lib/supabase/server";

export type Student = { id: string; full_name: string; year_level: string | null; school: string | null };
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
