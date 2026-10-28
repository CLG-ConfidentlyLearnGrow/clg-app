import { notFound, redirect } from "next/navigation";
import { closeGoal } from "@/app/actions/progress";
import { Button, Card, Page, TextLink } from "@/components/ui";
import { needsTwoStep, requireViewer } from "@/lib/auth";
import { ATTENDANCE_NAMES, CONFIDENCE_NAMES, SKILL_LEVELS, levelName, type Attendance, type SkillLevel } from "@/lib/progress";
import { YEAR_LEVELS, levelFits, subjectFits } from "@/lib/students";
import { bandCoversYear } from "@/lib/materials";
import { localDate, localToday, sessionWhen } from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";
import { Roadmap } from "./roadmap";
import { EvidenceCard } from "./evidence";
import { SeniorCertificateCard } from "./senior-certificate";
import { TermReviewCard } from "./term-review";
import { AddGoalForm, FamilyNoteForm, ReflectionForm, SessionNoteForm, type GoalSkill, type NoteSession } from "./forms";
import { StudentMaterialsCard, type StudentMaterial } from "./materials";

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
type FamilyNote = {
  id: string;
  kind: "feedback" | "home_progress";
  body: string;
  written_at: string;
  writer: { full_name: string } | null;
};
const FAMILY_NOTE_NAMES = { feedback: "Feedback", home_progress: "Progress at home" } as const;
type DueSession = {
  session_id: string;
  student_id: string;
  subject: string;
  starts_at: string;
  minutes: number;
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
  home_tip: string | null;
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
  const { subject, view, session, year } = await searchParams;
  const supabase = await createClient();

  const student = await supabase
    .from("students")
    .select("id, full_name, year_level, goals, extra_info, account_id")
    .eq("id", id)
    .maybeSingle();
  if (!student.data) notFound();

  // Who is the viewer to this student? Someone can be a parent and also
  // staff (Carla is both), so the family view is chosen from the link they
  // came in on, and staff tools only show to this student's own tutors and
  // admins.
  const [familyLink, myAssignment, requested, familyNotes] = await Promise.all([
    supabase.from("parent_student_links").select("student_id, can_manage").eq("student_id", id).eq("parent_id", viewer.id).maybeSingle(),
    supabase.from("tutor_assignments").select("id").eq("student_id", id).eq("tutor_id", viewer.id).limit(1),
    supabase.from("student_subjects").select("subject, working_level").eq("student_id", id).order("added_at"),
    supabase
      .from("family_notes")
      .select("id, kind, body, written_at, writer:accounts!family_notes_written_by_fkey(full_name)")
      .eq("student_id", id)
      .order("written_at", { ascending: false })
      .limit(20),
  ]);
  const isFamilyMember = Boolean(familyLink.data) || student.data.account_id === viewer.id;
  const isStudentStaff = viewer.roles.includes("admin") || (myAssignment.data ?? []).length > 0;
  const familyView = isFamilyMember && (view === "family" || !isStudentStaff);

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
        "id, session_date, minutes, attendance, went_well, next_step, homework, homework_due, home_tip, tutor:tutor_profiles(account:accounts(full_name)), session_note_skills(skill_id, level_before, level_after, skill:curriculum_skills(id, subject, level_band, description, plain_description)), student_reflections(confidence, what_was_hard, what_i_will_try)",
      )
      .eq("student_id", id)
      .order("session_date", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(10),
  ]);

  const isStaff = isStudentStaff && !familyView;
  const isFamily = familyView;
  // Planning the roadmap: the student, a parent who manages them, or staff.
  const canPlan = isStaff || student.data.account_id === viewer.id || Boolean(familyLink.data?.can_manage);

  // Reading this page counts as seeing its updates and reminders.
  await supabase.rpc("mark_progress_notices_read", { p_student: id });

  // Booked sessions with this student still waiting for a note. The note
  // form starts on the oldest one; "?session=none" writes a note without one.
  const dueRes = isStaff ? await supabase.rpc("list_notes_due") : null;
  const dueSessions = ((dueRes?.data ?? []) as DueSession[]).filter((d) => d.student_id === id);
  const chosenDue =
    session === "none" ? null : (dueSessions.find((d) => d.session_id === session) ?? dueSessions[0] ?? null);
  const noteSession: NoteSession | null = chosenDue
    ? {
        id: chosenDue.session_id,
        date: localDate(chosenDue.starts_at),
        minutes: chosenDue.minutes,
        label: `${sessionWhen(chosenDue.starts_at)} (${chosenDue.subject})`,
      }
    : null;
  // Materials that fit this student (staff only): tagged with their goal
  // skills, or for their subjects at the level they work at.
  const materialsRes = isStaff ? await supabase.rpc("materials_for_student", { p_student: id }) : null;
  const studentMaterials = (materialsRes?.data ?? []) as StudentMaterial[];
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
  // Skills being worked on now: those in the latest session note, or else
  // those on their way (Learning or Secure with help).
  const currentSkillIds = new Set<string>(latest?.session_note_skills.map((k) => k.skill_id) ?? []);
  if (currentSkillIds.size === 0) {
    for (const [skillId, level] of levelBySkill) {
      if (level === "learning" || level === "secure_with_help") currentSkillIds.add(skillId);
    }
  }
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

  // Skills at the level the family gave for this subject (or the school
  // year if they weren't sure) start ticked when adding a goal.
  const startLevel =
    (requested.data ?? []).find((r) => r.working_level && subjectFits(r.subject, chosenSubject))?.working_level ??
    student.data.year_level;

  // Skills to choose from when adding a goal, narrowed to one year level
  // (the level given for this subject unless the tutor picks another).
  const chosenYear =
    year === "all"
      ? "all"
      : typeof year === "string" && (YEAR_LEVELS as readonly string[]).includes(year)
        ? year
        : (startLevel ?? "all");
  const yearIndex = (YEAR_LEVELS as readonly string[]).indexOf(chosenYear);
  const goalSkillChoices =
    yearIndex < 0 ? subjectSkills : subjectSkills.filter((s) => bandCoversYear(s.level_band, yearIndex));

  const skillNameById = Object.fromEntries(
    activeGoals.flatMap((g) => g.goal_skills.flatMap(({ skill }) => (skill ? [[skill.id, skillLabel(skill)]] : []))),
  ) as Record<string, string>;

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
            {latest.home_tip && (
              <p>
                <strong>Try at home:</strong> {latest.home_tip}
              </p>
            )}
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

      <Roadmap
        studentId={id}
        canPlan={canPlan}
        canRemoveAny={isStaff}
        viewerId={viewer.id}
        isStudentSelf={student.data.account_id === viewer.id}
      />

      <TermReviewCard studentId={id} viewerId={viewer.id} isStaff={isStaff} isFamily={isFamily} />

      <EvidenceCard
        studentId={id}
        viewerId={viewer.id}
        today={localToday()}
        canUpload={canPlan}
        canRemoveAny={viewer.roles.includes("admin") || student.data.account_id === viewer.id || Boolean(familyLink.data?.can_manage)}
        canAddReports={viewer.roles.includes("admin") || Boolean(familyLink.data?.can_manage) || student.data.account_id === viewer.id}
        isStaff={isStaff}
        goalSkills={noteSkills}
      />

      <SeniorCertificateCard
        studentId={id}
        yearLevel={student.data.year_level}
        canPlan={canPlan}
        thisYear={Number(localToday().slice(0, 4))}
      />

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

      {isFamily && (
        <Card
          title="Tell the tutor"
          description="Share feedback, or how practice is going at home. The tutor and CLG will see it."
        >
          <FamilyNoteForm studentId={id} />
        </Card>
      )}

      {isStaff && (
        <Card title="What the family asked for">
          <div className="space-y-2 text-sm">
            <p>
              <strong>Subjects:</strong>{" "}
              {(requested.data ?? []).length > 0
                ? (requested.data ?? [])
                    .map((r) => `${r.subject} (${r.working_level ? `working at ${r.working_level}` : "level unsure"})`)
                    .join(", ")
                : "None given"}
            </p>
            <p>
              <strong>End goal:</strong> {student.data.goals || "None given"}
            </p>
            {student.data.extra_info && (
              <p>
                <strong>Other information:</strong> {student.data.extra_info}
              </p>
            )}
          </div>
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
                {(() => {
                  // Show the skills being worked on now; the rest open on a tap.
                  const all = g.goal_skills.flatMap(({ skill }) => (skill ? [skill] : []));
                  let now = all.filter((k) => currentSkillIds.has(k.id));
                  if (now.length === 0) {
                    const next = all.find((k) => levelBySkill.get(k.id) !== "secure_on_own");
                    now = next ? [next] : [];
                  }
                  const rest = all.filter((k) => !now.includes(k));
                  const item = (k: Skill) => (
                    <li key={k.id} className="text-sm">
                      <p>{skillLabel(k)}</p>
                      <LevelBar level={levelBySkill.get(k.id) ?? "not_started"} />
                    </li>
                  );
                  return (
                    <>
                      <ul className="mt-2 space-y-2">{now.map(item)}</ul>
                      {rest.length > 0 && (
                        <details className="mt-2">
                          <summary className="cursor-pointer text-xs text-teal-800">
                            {now.length === 0 ? `Show all ${rest.length} skills` : `Show the other ${rest.length} skill${rest.length === 1 ? "" : "s"} in this goal`}
                          </summary>
                          <ul className="mt-2 space-y-2">{rest.map(item)}</ul>
                        </details>
                      )}
                    </>
                  );
                })()}
              </li>
            ))}
          </ul>
        )}
        <p className="mt-4 text-xs text-zinc-500">
          The tutor chooses the skills, starting from the level the student seems to be at. They may change in the
          first three sessions as the tutor gets to know the student.
        </p>
        {closedGoals.length > 0 && (
          <p className="mt-4 text-xs text-zinc-500">
            Finished goals: {closedGoals.map((g) => `${g.title} (${g.status})`).join("; ")}
          </p>
        )}
      </Card>

      {isStaff && <StudentMaterialsCard materials={studentMaterials} skillNames={skillNameById} />}

      {isStaff && (
        <Card
          title="Write a session note"
          description={
            <>
              About three minutes, within 24 hours of the session.
            </>
          }
        >
          {dueSessions.length > 0 && (
            <div className="mb-5 text-sm">
              <p className="font-medium">Sessions waiting for a note</p>
              <ul className="mt-1 space-y-1">
                {dueSessions.map((d) => (
                  <li key={d.session_id}>
                    {d.session_id === chosenDue?.session_id ? (
                      <strong>{sessionWhen(d.starts_at)} (writing now)</strong>
                    ) : (
                      <TextLink href={`/students/${id}/progress?session=${d.session_id}`}>
                        {sessionWhen(d.starts_at)}
                      </TextLink>
                    )}
                  </li>
                ))}
                <li>
                  {chosenDue ? (
                    <TextLink href={`/students/${id}/progress?session=none`}>A session that wasn&apos;t booked in the app</TextLink>
                  ) : (
                    <strong>A session that wasn&apos;t booked in the app (writing now)</strong>
                  )}
                </li>
              </ul>
            </div>
          )}
          <SessionNoteForm
            key={noteSession?.id ?? "none"}
            studentId={id}
            skills={noteSkills}
            materials={studentMaterials.map((m) => ({ id: m.material_id, title: m.title, kind: m.kind, skillIds: m.goal_skill_ids }))}
            session={noteSession}
            today={localToday()}
          />
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
                <label className="block space-y-1">
                  <span className="text-sm font-medium">Year level</span>
                  <select
                    name="year"
                    defaultValue={chosenYear}
                    className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"
                  >
                    <option value="all">All years</option>
                    {YEAR_LEVELS.map((y) => (
                      <option key={y} value={y}>
                        {y}
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
                  skills={goalSkillChoices.map((s) => ({
                    id: s.id,
                    label: skillLabel(s),
                    levelBand: s.level_band,
                    ticked: levelFits(startLevel, s.level_band),
                  }))}
                  startLevel={startLevel}
                />
              )}
            </>
          )}
        </Card>
      )}

      {(familyNotes.data ?? []).length > 0 && (
        <Card collapsible title="Notes from home">
          <ul className="space-y-3 text-sm">
            {(familyNotes.data as unknown as FamilyNote[]).map((n) => (
              <li key={n.id} className="border-t border-zinc-200 pt-3 first:border-0 first:pt-0">
                <p className="text-xs text-zinc-500">
                  {FAMILY_NOTE_NAMES[n.kind]}, {n.written_at.slice(0, 10)}
                  {n.writer?.full_name && `, from ${n.writer.full_name}`}
                </p>
                <p className="whitespace-pre-line">{n.body}</p>
              </li>
            ))}
          </ul>
        </Card>
      )}

      <Card collapsible title="Recent sessions">
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
                  {n.home_tip && <p>Try at home: {n.home_tip}</p>}
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
