import { notFound, redirect } from "next/navigation";
import { closeGoal } from "@/app/actions/progress";
import { Button, Card, Page, TextLink } from "@/components/ui";
import { needsTwoStep, requireViewer } from "@/lib/auth";
import { ATTENDANCE_NAMES, CONFIDENCE_NAMES, SKILL_LEVELS, levelName, type Attendance, type SkillLevel } from "@/lib/progress";
import { createClient } from "@/lib/supabase/server";
import { AddGoalForm, ReflectionForm, SessionNoteForm, type GoalSkill } from "./forms";

type Skill = {
  id: string;
  subject: string;
  level_band: string;
  description: string;
  plain_description: string | null;
};
type Goal = {
  id: string;
  subject: string;
  title: string;
  target_date: string | null;
  status: "active" | "achieved" | "stopped";
  goal_skills: { skill: Skill | null }[];
};
type Reflection = { confidence: number; what_was_hard: string | null; what_i_will_try: string | null };
type Note = {
  id: string;
  session_date: string;
  minutes: number | null;
  attendance: Attendance;
  went_well: string | null;
  next_step: string | null;
  homework: string | null;
  homework_due: string | null;
  tutor: { account: { full_name: string } | null } | null;
  session_note_skills: { skill_id: string; level_before: SkillLevel; level_after: SkillLevel; skill: Skill | null }[];
  student_reflections: Reflection | Reflection[] | null;
};

const skillLabel = (s: Skill) => s.plain_description || s.description;
const reflectionOf = (n: Note) =>
  (Array.isArray(n.student_reflections) ? n.student_reflections[0] : n.student_reflections) ?? null;

// One student's progress: their next step, goals and skills, and recent
// sessions. The database decides who may see it (the family, the student's
// current tutors, admins) and what each may change.
export default async function ProgressPage({ params, searchParams }: PageProps<"/students/[id]/progress">) {
  const viewer = await requireViewer();
  if (needsTwoStep(viewer)) redirect("/mfa");
  const { id } = await params;
  const { subject } = await searchParams;
  const supabase = await createClient();

  const student = await supabase.from("students").select("id, full_name, year_level").eq("id", id).maybeSingle();
  if (!student.data) notFound();

  const [frameworks, goals, levels, notes] = await Promise.all([
    supabase.from("student_frameworks").select("framework_id").eq("student_id", id),
    supabase
      .from("learning_goals")
      .select(
        "id, subject, title, target_date, status, goal_skills(skill:curriculum_skills(id, subject, level_band, description, plain_description))",
      )
      .eq("student_id", id)
      .order("created_at"),
    supabase.from("student_skill_levels").select("skill_id, level").eq("student_id", id),
    supabase
      .from("session_notes")
      .select(
        "id, session_date, minutes, attendance, went_well, next_step, homework, homework_due, tutor:tutor_profiles(account:accounts(full_name)), session_note_skills(skill_id, level_before, level_after, skill:curriculum_skills(id, subject, level_band, description, plain_description)), student_reflections(confidence, what_was_hard, what_i_will_try)",
      )
      .eq("student_id", id)
      .order("session_date", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(10),
  ]);

  const isStaff = viewer.roles.includes("tutor") || viewer.roles.includes("admin");
  const isFamily = viewer.roles.includes("parent") || viewer.roles.includes("student");
  const goalRows = (goals.data ?? []) as unknown as Goal[];
  const activeGoals = goalRows.filter((g) => g.status === "active");
  const closedGoals = goalRows.filter((g) => g.status !== "active");
  const levelBySkill = new Map((levels.data ?? []).map((l) => [l.skill_id, l.level as SkillLevel]));
  const noteRows = (notes.data ?? []) as unknown as Note[];
  // Returns nothing for families: the database never shows them staff notes.
  const staffNotes =
    noteRows.length > 0
      ? await supabase
          .from("session_staff_notes")
          .select("note_id, body")
          .in(
            "note_id",
            noteRows.map((n) => n.id),
          )
      : null;
  const staffByNote = new Map((staffNotes?.data ?? []).map((s) => [s.note_id, s.body]));
  const latest = noteRows.find((n) => n.attendance !== "absent");
  const frameworkIds = (frameworks.data ?? []).map((f) => f.framework_id);

  // For adding a goal: subjects in the student's curriculum, then that
  // subject's skills.
  let subjects: string[] = [];
  let subjectSkills: Skill[] = [];
  const chosenSubject = typeof subject === "string" ? subject : "";
  if (isStaff && frameworkIds.length > 0) {
    const all = await supabase
      .from("curriculum_skills")
      .select("subject")
      .in("framework_id", frameworkIds)
      .is("retired_at", null)
      .limit(10000);
    subjects = [...new Set((all.data ?? []).map((s) => s.subject))].sort();
    if (chosenSubject) {
      const list = await supabase
        .from("curriculum_skills")
        .select("id, subject, level_band, description, plain_description")
        .in("framework_id", frameworkIds)
        .eq("subject", chosenSubject)
        .is("retired_at", null)
        .order("sort_order")
        .order("level_band")
        .limit(2000);
      subjectSkills = (list.data ?? []) as Skill[];
    }
  }

  const noteSkills: GoalSkill[] = [];
  const seen = new Set<string>();
  for (const g of activeGoals) {
    for (const { skill } of g.goal_skills) {
      if (!skill || seen.has(skill.id)) continue;
      seen.add(skill.id);
      noteSkills.push({
        id: skill.id,
        label: skillLabel(skill),
        level: levelBySkill.get(skill.id) ?? "not_started",
        goal: g.title,
      });
    }
  }

  return (
    <Page title={`${student.data.full_name}: progress`}>
      <p className="text-sm">
        <TextLink href="/dashboard">Back to dashboard</TextLink>
      </p>

      <Card title="Next step">
        {latest ? (
          <div className="space-y-2 text-sm">
            <p className="text-base font-medium">{latest.next_step}</p>
            {latest.homework && (
              <p>
                <strong>Practice:</strong> {latest.homework}
                {latest.homework_due && ` (by ${latest.homework_due})`}
              </p>
            )}
            <p className="text-zinc-600">
              <strong>Went well on {latest.session_date}:</strong> {latest.went_well}
            </p>
          </div>
        ) : (
          <p className="text-sm">The next step appears here after the first session note.</p>
        )}
      </Card>

      {isFamily && latest && !reflectionOf(latest) && (
        <Card
          title="How did it go?"
          description={
            <>
              A few seconds of thinking back helps learning stick. Younger students can answer with a parent.
            </>
          }
        >
          <ReflectionForm studentId={id} noteId={latest.id} />
        </Card>
      )}

      <Card title="Goals and skills">
        {activeGoals.length === 0 ? (
          <p className="text-sm">No goals set yet. The tutor sets 1 to 3 goals per subject in the first sessions.</p>
        ) : (
          <ul className="space-y-5">
            {activeGoals.map((g) => (
              <li key={g.id}>
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-medium">{g.title}</p>
                    <p className="text-xs text-zinc-500">
                      {g.subject}
                      {g.target_date && `, aiming for ${g.target_date}`}
                    </p>
                  </div>
                  {isStaff && (
                    <form action={closeGoal} className="flex gap-2">
                      <input type="hidden" name="goal_id" value={g.id} />
                      <input type="hidden" name="student_id" value={id} />
                      <button name="status" value="achieved" className="text-xs text-teal-700 underline">
                        Achieved
                      </button>
                      <button name="status" value="stopped" className="text-xs text-zinc-500 underline">
                        Stop
                      </button>
                    </form>
                  )}
                </div>
                <ul className="mt-2 space-y-2">
                  {g.goal_skills.map(({ skill }) =>
                    skill ? (
                      <li key={skill.id} className="text-sm">
                        <p>{skillLabel(skill)}</p>
                        <LevelBar level={levelBySkill.get(skill.id) ?? "not_started"} />
                      </li>
                    ) : null,
                  )}
                </ul>
              </li>
            ))}
          </ul>
        )}
        {closedGoals.length > 0 && (
          <p className="mt-4 text-xs text-zinc-500">
            Finished goals: {closedGoals.map((g) => `${g.title} (${g.status})`).join("; ")}
          </p>
        )}
      </Card>

      {isStaff && (
        <Card
          title="Write a session note"
          description={
            <>
              About three minutes, within 24 hours of the session.
            </>
          }
        >
          <SessionNoteForm studentId={id} skills={noteSkills} />
        </Card>
      )}

      {isStaff && (
        <Card title="Add a goal">
          {frameworkIds.length === 0 ? (
            <p className="text-sm">An admin needs to set this student&apos;s curriculum first.</p>
          ) : (
            <>
              <form method="get" className="mb-4 flex items-end gap-3">
                <label className="block flex-1 space-y-1">
                  <span className="text-sm font-medium">Subject</span>
                  <select
                    name="subject"
                    defaultValue={chosenSubject}
                    className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"
                  >
                    <option value="" disabled>
                      Choose…
                    </option>
                    {subjects.map((s) => (
                      <option key={s} value={s}>
                        {s}
                      </option>
                    ))}
                  </select>
                </label>
                <Button type="submit">Show skills</Button>
              </form>
              {chosenSubject && (
                <AddGoalForm
                  studentId={id}
                  subject={chosenSubject}
                  skills={subjectSkills.map((s) => ({ id: s.id, label: skillLabel(s), levelBand: s.level_band }))}
                />
              )}
            </>
          )}
        </Card>
      )}

      <Card title="Recent sessions">
        {noteRows.length === 0 ? (
          <p className="text-sm">No sessions recorded yet.</p>
        ) : (
          <ul className="space-y-4 text-sm">
            {noteRows.map((n) => {
              const reflection = reflectionOf(n);
              const staff = staffByNote.get(n.id);
              return (
                <li key={n.id} className="border-t border-zinc-200 pt-3 first:border-0 first:pt-0">
                  <p className="font-medium">
                    {n.session_date}: {ATTENDANCE_NAMES[n.attendance]}
                    {n.minutes ? `, ${n.minutes} min` : ""}
                    {n.tutor?.account?.full_name && ` with ${n.tutor.account.full_name}`}
                  </p>
                  {n.went_well && <p>Went well: {n.went_well}</p>}
                  {n.next_step && <p>Next step: {n.next_step}</p>}
                  {n.homework && <p>Practice: {n.homework}</p>}
                  {n.session_note_skills.length > 0 && (
                    <ul className="mt-1 list-disc pl-5 text-zinc-600">
                      {n.session_note_skills.map((s) => (
                        <li key={s.skill_id}>
                          {s.skill ? skillLabel(s.skill) : "Skill"}:{" "}
                          {s.level_before === s.level_after
                            ? levelName(s.level_after)
                            : `${levelName(s.level_before)} → ${levelName(s.level_after)}`}
                        </li>
                      ))}
                    </ul>
                  )}
                  {reflection && (
                    <p className="mt-1 text-zinc-600">
                      Student&apos;s reflection: {CONFIDENCE_NAMES[reflection.confidence]}
                      {reflection.what_was_hard && `. Hard: ${reflection.what_was_hard}`}
                      {reflection.what_i_will_try && `. Will try: ${reflection.what_i_will_try}`}
                    </p>
                  )}
                  {staff && (
                    <p className="mt-1 rounded bg-amber-50 px-2 py-1 text-amber-900">
                      Staff only: {staff}
                    </p>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </Card>
    </Page>
  );
}

// The four-step scale as a simple bar: filled steps show where the skill is.
function LevelBar({ level }: { level: SkillLevel }) {
  const reached = SKILL_LEVELS.indexOf(level);
  return (
    <div className="mt-1 flex items-center gap-2" aria-label={`Level: ${levelName(level)}`}>
      <div className="flex gap-1">
        {SKILL_LEVELS.slice(1).map((l, i) => (
          <span
            key={l}
            className={`h-2 w-8 rounded-full ${i < reached ? "bg-teal-600" : "bg-zinc-200"}`}
          />
        ))}
      </div>
      <span className="text-xs text-zinc-600">{levelName(level)}</span>
    </div>
  );
}
