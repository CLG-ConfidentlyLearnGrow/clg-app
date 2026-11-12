// Summary: one student's progress page. It shows the next step, the roadmap,
// term reviews, uploads, senior subjects, goals and skills, and recent
// sessions. Families can reflect and send notes; the student's tutors and
// admins can write session notes and add goals. The database decides who may
// see and change each part.
//
import { notFound, redirect } from "next/navigation"; // Tools to show "page not found" or send the person to another page.
import { closeGoal } from "@/app/actions/progress"; // The server action that marks a goal achieved or stopped.
import { Button, Card, Page, TextLink } from "@/components/ui"; // Shared page parts: a button, a card, the page frame and a text link.
import { FRONT_DESK, getAdminLevel, needsTwoStep, requireViewer } from "@/lib/auth"; // Sign-in helpers: front-desk admin levels, the admin level, the two-step check, and the signed-in person.
import { CourseDetails } from "@/components/course-details"; // Shows a university or TAFE student's course and units.
import { CourseOverviewForm } from "@/app/admin/course-overview-form"; // The admin's form for writing a unit overview.
import { ATTENDANCE_NAMES, CONFIDENCE_NAMES, SKILL_LEVELS, levelName, type Attendance, type SkillLevel } from "@/lib/progress"; // Progress helpers: attendance and confidence names, the skill levels, a level's name, and their types.
import { YEAR_LEVELS, levelFits, subjectFits } from "@/lib/students"; // Student helpers: the year levels, and checks for whether a level or subject fits.
import { bandCoversYear } from "@/lib/materials"; // Checks whether a material's year band covers a year.
import { localDate, localToday, sessionWhen } from "@/lib/scheduling"; // Scheduling helpers: a local date, today's date, and a session's day and time in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { Roadmap } from "./roadmap"; // The roadmap card.
import { EvidenceCard } from "./evidence"; // The uploads (evidence) card.
import { SeniorCertificateCard } from "./senior-certificate"; // The senior certificate card.
import { TermReviewCard } from "./term-review"; // The term review card.
import { AddGoalForm, FamilyNoteForm, ReflectionForm, SessionNoteForm, type GoalSkill, type NoteSession } from "./forms"; // The forms on this page, and the types they use.
import { StudentMaterialsCard, type StudentMaterial } from "./materials"; // The materials card, and the type for a material.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while it sends.

// A student as the database gives it.
type StudentRow = { // (the shape)
  id: string; // its id,
  full_name: string; // full name,
  year_level: string | null; // year level,
  school: string | null; // school,
  program: string | null; // degree or course,
  goals: string | null; // end goal,
  extra_info: string | null; // other information,
  learning_needs: string | null; // learning needs,
  account_id: string | null; // and their own login (if any).
}; // End of the shape.
// A curriculum skill.
type Skill = { // (the shape)
  id: string; // its id,
  subject: string; // subject,
  level_band: string; // year band,
  description: string; // official wording,
  plain_description: string | null; // and plain wording (if written).
}; // End of the shape.
// A learning goal.
type Goal = { // (the shape)
  id: string; // its id,
  subject: string; // subject,
  title: string; // title,
  target_date: string | null; // date to aim for (if any),
  status: "active" | "achieved" | "stopped"; // whether it's active, achieved or stopped,
  goal_skills: { skill: Skill | null }[]; // and the skills it covers.
}; // End of the shape.
// A note from the family.
type FamilyNote = { // (the shape)
  id: string; // its id,
  kind: "feedback" | "home_progress"; // feedback or progress at home,
  body: string; // the words,
  written_at: string; // when it was written,
  writer: { full_name: string } | null; // and who wrote it.
}; // End of the shape.
const FAMILY_NOTE_NAMES = { feedback: "Feedback", home_progress: "Progress at home" } as const; // The names shown for each kind of family note.
// A booked session still waiting for a note.
type DueSession = { // (the shape)
  session_id: string; // the session,
  student_id: string; // the student,
  subject: string; // the subject,
  starts_at: string; // when it starts,
  minutes: number; // and how long it is.
}; // End of the shape.
type Reflection = { confidence: number; what_was_hard: string | null; what_i_will_try: string | null }; // A student's reflection: confidence, what was hard, and what they'll try.
// A session note as the database gives it.
type Note = { // (the shape)
  id: string; // its id,
  session_date: string; // the session's date,
  minutes: number | null; // minutes,
  attendance: Attendance; // attendance,
  went_well: string | null; // what went well,
  next_step: string | null; // the next step,
  homework: string | null; // homework,
  homework_due: string | null; // when it's due,
  home_tip: string | null; // a tip for home,
  tutor: { account: { full_name: string } | null } | null; // the tutor's name,
  session_note_skills: { skill_id: string; level_before: SkillLevel; level_after: SkillLevel; skill: Skill | null }[]; // the skills worked on and how their levels moved,
  student_reflections: Reflection | Reflection[] | null; // and the student's reflection (one, a list, or none).
}; // End of the shape.

const skillLabel = (s: Skill) => s.plain_description || s.description; // A skill's plain wording if there is one, otherwise the official wording.
const reflectionOf = (n: Note) => // A note's student reflection (the database may give one or a list):
  (Array.isArray(n.student_reflections) ? n.student_reflections[0] : n.student_reflections) ?? null; // takes the first, or nothing.

// One student's progress: their next step, goals and skills, and recent
// sessions. The database decides who may see it (the family, the student's
// current tutors, admins) and what each may change.
export default async function ProgressPage({ params, searchParams }: PageProps<"/students/[id]/progress">) { // The page itself.
  const viewer = await requireViewer(); // The signed-in person (sends them to sign in if not).
  if (needsTwoStep(viewer)) redirect("/mfa"); // Needs two-step sign-in set up: sends them there.
  const { id } = await params; // The student's id from the web address.
  const { subject, view, session, year } = await searchParams; // Choices from the web address: subject, view, session and year.
  const supabase = await createClient(); // Connects to the database.

  const full = await supabase // Reads the student:
    .from("students") // from the students table,
    .select("id, full_name, year_level, school, program, goals, extra_info, learning_needs, account_id") // these details,
    .eq("id", id) // for this student,
    .maybeSingle(); // one row or none.
  // If a newer database update (course name, learning needs) hasn't been run
  // yet, those columns are missing and the query fails. Open the page with
  // the core details rather than showing "page not found".
  let studentRow: StudentRow | null = full.data as StudentRow | null; // The student (or nothing).
  if (full.error) { // If that failed:
    console.error("Progress page: student details", full.error.message); // notes why in the server log,
    const core = await supabase // reads just the core details:
      .from("students") // from the students table,
      .select("id, full_name, year_level, school, goals, extra_info, account_id") // these details,
      .eq("id", id) // for this student,
      .maybeSingle(); // one row or none.
    studentRow = core.data ? { ...core.data, program: null, learning_needs: null } : null; // Fills the missing details with nothing.
  } // End of the fallback.
  if (!studentRow) notFound(); // No student (or not allowed to see): shows "page not found".
  const student = { data: studentRow }; // Keeps the student in the shape the rest of the page expects.

  // Who is the viewer to this student? Someone can be a parent and also
  // staff (Carla is both), so the family view is chosen from the link they
  // came in on, and staff tools only show to this student's own tutors and
  // admins.
  const [familyLink, myAssignment, requested, familyNotes] = await Promise.all([ // Reads four things at once:
    supabase.from("parent_student_links").select("student_id, can_manage").eq("student_id", id).eq("parent_id", viewer.id).maybeSingle(), // the viewer's parent link to this student (if any),
    supabase.from("tutor_assignments").select("id").eq("student_id", id).eq("tutor_id", viewer.id).limit(1), // whether the viewer tutors this student,
    supabase // the subjects the family asked for:
      .from("student_subjects") // from student_subjects,
      .select("id, subject, working_level, course_code, course_url, course_overview") // these details,
      .eq("student_id", id) // for this student,
      .order("added_at"), // oldest first.
    supabase // the notes from home:
      .from("family_notes") // from family_notes,
      .select("id, kind, body, written_at, writer:accounts!family_notes_written_by_fkey(full_name)") // these details and the writer's name,
      .eq("student_id", id) // for this student,
      .order("written_at", { ascending: false }) // newest first,
      .limit(20), // up to 20.
  ]); // End of the reads.
  const isFamilyMember = Boolean(familyLink.data) || student.data.account_id === viewer.id; // True if the viewer is a parent of the student, or the student.
  const isStudentStaff = viewer.roles.includes("admin") || (myAssignment.data ?? []).length > 0; // True if the viewer is an admin or one of the student's tutors.
  const familyView = isFamilyMember && (view === "family" || !isStudentStaff); // Family view if they're family and asked for it (or aren't staff).

  const [frameworks, goals, levels, notes] = await Promise.all([ // Reads four more things at once:
    supabase.from("student_frameworks").select("framework_id").eq("student_id", id), // the student's curricula,
    supabase // the goals:
      .from("learning_goals") // from learning_goals,
      .select( // these details:
        "id, subject, title, target_date, status, goal_skills(skill:curriculum_skills(id, subject, level_band, description, plain_description))", // each goal with its skills,
      ) // (end of the details)
      .eq("student_id", id) // for this student,
      .order("created_at"), // oldest first.
    supabase.from("student_skill_levels").select("skill_id, level").eq("student_id", id), // the student's level on each skill,
    supabase // the session notes:
      .from("session_notes") // from session_notes,
      .select( // these details:
        "id, session_date, minutes, attendance, went_well, next_step, homework, homework_due, home_tip, tutor:tutor_profiles(account:accounts(full_name)), session_note_skills(skill_id, level_before, level_after, skill:curriculum_skills(id, subject, level_band, description, plain_description)), student_reflections(confidence, what_was_hard, what_i_will_try)", // each note with tutor, skills worked on and the student's reflection,
      ) // (end of the details)
      .eq("student_id", id) // for this student,
      .order("session_date", { ascending: false }) // newest session first,
      .order("created_at", { ascending: false }) // then newest written first,
      .limit(10), // up to 10.
  ]); // End of the reads.

  const isStaff = isStudentStaff && !familyView; // Staff tools show to staff who aren't in family view.
  // Admins at owner, operations or support level write university or TAFE
  // course overviews for the tutor (the database checks this too).
  const tertiary = student.data.year_level === "University or TAFE" || student.data.year_level === "Adult learner"; // True for a university, TAFE or adult learner.
  const adminLevel = isStaff && tertiary && viewer.roles.includes("admin") ? await getAdminLevel() : null; // The viewer's admin level (only looked up when it's needed).
  const canWriteOverview = adminLevel !== null && FRONT_DESK.includes(adminLevel); // True if that level may write overviews.
  const isFamily = familyView; // True when showing the family view.
  // Planning the roadmap: the student, a parent who manages them, or staff.
  const canPlan = isStaff || student.data.account_id === viewer.id || Boolean(familyLink.data?.can_manage); // True if the viewer may plan the roadmap.

  // Reading this page counts as seeing its updates and reminders.
  await supabase.rpc("mark_progress_notices_read", { p_student: id }); // Marks this student's progress notices as read.

  // Booked sessions with this student still waiting for a note. The note
  // form starts on the oldest one; "?session=none" writes a note without one.
  const dueRes = isStaff ? await supabase.rpc("list_notes_due") : null; // The sessions waiting for a note (staff only).
  const dueSessions = ((dueRes?.data ?? []) as DueSession[]).filter((d) => d.student_id === id); // Just this student's.
  const chosenDue = // The session the note is for:
    session === "none" ? null : (dueSessions.find((d) => d.session_id === session) ?? dueSessions[0] ?? null); // none if asked, else the one chosen, else the oldest.
  const noteSession: NoteSession | null = chosenDue // The note form's session details:
    ? { // if there is one:
        id: chosenDue.session_id, // its id,
        date: localDate(chosenDue.starts_at), // its date,
        minutes: chosenDue.minutes, // its length,
        label: `${sessionWhen(chosenDue.starts_at)} (${chosenDue.subject})`, // and a label with day, time and subject.
      } // (end of the details)
    : null; // otherwise nothing.
  // Materials that fit this student (staff only): tagged with their goal
  // skills, or for their subjects at the level they work at.
  const materialsRes = isStaff ? await supabase.rpc("materials_for_student", { p_student: id }) : null; // Reads the materials that fit (staff only).
  const studentMaterials = (materialsRes?.data ?? []) as StudentMaterial[]; // The materials.
  const goalRows = (goals.data ?? []) as unknown as Goal[]; // The goals.
  const activeGoals = goalRows.filter((g) => g.status === "active"); // The active ones.
  const closedGoals = goalRows.filter((g) => g.status !== "active"); // The finished ones.
  const levelBySkill = new Map((levels.data ?? []).map((l) => [l.skill_id, l.level as SkillLevel])); // The student's level on each skill, looked up by skill id.
  const noteRows = (notes.data ?? []) as unknown as Note[]; // The session notes.
  // Returns nothing for families: the database never shows them staff notes.
  const staffNotes = // The staff-only notes:
    noteRows.length > 0 // if there are session notes,
      ? await supabase // reads:
          .from("session_staff_notes") // from session_staff_notes,
          .select("note_id, body") // the note and its words,
          .in( // where the note is one of:
            "note_id", // (the list)
            noteRows.map((n) => n.id), // these notes' ids.
          ) // (end of the list)
      : null; // otherwise nothing.
  const staffByNote = new Map((staffNotes?.data ?? []).map((s) => [s.note_id, s.body])); // Each staff note's words, looked up by note id.
  const latest = noteRows.find((n) => n.attendance !== "absent"); // The latest session the student came to.
  // Skills being worked on now: those in the latest session note, or else
  // those on their way (Learning or Secure with help).
  const currentSkillIds = new Set<string>(latest?.session_note_skills.map((k) => k.skill_id) ?? []); // The skills in the latest note.
  if (currentSkillIds.size === 0) { // If there are none:
    for (const [skillId, level] of levelBySkill) { // for each skill level:
      if (level === "learning" || level === "secure_with_help") currentSkillIds.add(skillId); // adds the skills that are learning or secure with help.
    } // End of the loop.
  } // End of the fallback.
  const frameworkIds = (frameworks.data ?? []).map((f) => f.framework_id); // The student's curriculum ids.

  // For adding a goal: subjects in the student's curriculum, then that
  // subject's skills.
  let subjects: string[] = []; // The subjects to choose from.
  let subjectSkills: Skill[] = []; // The chosen subject's skills.
  const chosenSubject = typeof subject === "string" ? subject : ""; // The chosen subject from the web address (or none).
  if (isStaff && frameworkIds.length > 0) { // Staff only, and only if the student has a curriculum:
    const all = await supabase // reads every subject:
      .from("curriculum_skills") // from curriculum_skills,
      .select("subject") // just the subject,
      .in("framework_id", frameworkIds) // in the student's curricula,
      .is("retired_at", null) // not retired,
      .limit(10000); // up to 10,000.
    subjects = [...new Set((all.data ?? []).map((s) => s.subject))].sort(); // Each subject once, in order.
    if (chosenSubject) { // If a subject is chosen:
      const list = await supabase // reads its skills:
        .from("curriculum_skills") // from curriculum_skills,
        .select("id, subject, level_band, description, plain_description") // these details,
        .in("framework_id", frameworkIds) // in the student's curricula,
        .eq("subject", chosenSubject) // for that subject,
        .is("retired_at", null) // not retired,
        .order("sort_order") // in curriculum order,
        .order("level_band") // then by year band,
        .limit(2000); // up to 2,000.
      subjectSkills = (list.data ?? []) as Skill[]; // Keeps the skills.
    } // End of the chosen subject.
  } // End of the staff check.

  // Skills at the level the family gave for this subject (or the school
  // year if they weren't sure) start ticked when adding a goal.
  const startLevel = // The start level:
    (requested.data ?? []).find((r) => r.working_level && subjectFits(r.subject, chosenSubject))?.working_level ?? // the working level given for this subject,
    student.data.year_level; // or else the school year.

  // Skills to choose from when adding a goal, narrowed to one year level
  // (the level given for this subject unless the tutor picks another).
  const chosenYear = // The year to show:
    year === "all" // "all" if asked,
      ? "all" // (all years)
      : typeof year === "string" && (YEAR_LEVELS as readonly string[]).includes(year) // otherwise a year from the web address if it's a real year,
        ? year // (that year)
        : (startLevel ?? "all"); // or else the start level (or all).
  const yearIndex = (YEAR_LEVELS as readonly string[]).indexOf(chosenYear); // Where that year sits in the list (-1 for all).
  const goalSkillChoices = // The skills to offer:
    yearIndex < 0 ? subjectSkills : subjectSkills.filter((s) => bandCoversYear(s.level_band, yearIndex)); // all for "all", otherwise those whose band covers the year.

  const skillNameById = Object.fromEntries( // Each goal skill's words, looked up by skill id:
    activeGoals.flatMap((g) => g.goal_skills.flatMap(({ skill }) => (skill ? [[skill.id, skillLabel(skill)]] : []))), // (from the active goals)
  ) as Record<string, string>; // (as a lookup)

  const noteSkills: GoalSkill[] = []; // The skills for the session note form.
  const seen = new Set<string>(); // Skills already added (so each shows once).
  for (const g of activeGoals) { // For each active goal:
    for (const { skill } of g.goal_skills) { // for each of its skills:
      if (!skill || seen.has(skill.id)) continue; // skips a missing or repeated skill,
      seen.add(skill.id); // marks it as added,
      noteSkills.push({ // adds it:
        id: skill.id, // its id,
        label: skillLabel(skill), // its words,
        level: levelBySkill.get(skill.id) ?? "not_started", // its current level (or not started),
        goal: g.title, // and its goal.
      }); // End of the skill.
    } // End of the skills loop.
  } // End of the goals loop.

  return ( // Shows:
    <Page title={`${student.data.full_name}: progress`}>{/* the page, titled with the student's name, */}
      <p className="text-sm">{/* a small line: */}
        <TextLink href="/dashboard">Back to Home</TextLink>{/* a link back home. */}
      </p>{/* End of the paragraph. */}

      <Card title="Next step">{/* The "Next step" card: */}
        {latest ? ( // if there's a latest session:
          <div className="space-y-2 text-sm">{/* a block: */}
            <p className="text-base font-medium">{latest.next_step}</p>{/* the next step, larger, */}
            {latest.home_tip && ( // if there's a home tip:
              <p>{/* a line: */}
                <strong>Try at home:</strong> {latest.home_tip}{/* "Try at home:" and the tip. */}
              </p> // End of the paragraph.
            )}{/* End of this part. */}
            {latest.homework && ( // If there's homework:
              <p>{/* a line: */}
                <strong>Practice:</strong> {latest.homework}{/* "Practice:" and the homework, */}
                {latest.homework_due && ` (by ${latest.homework_due})`}{/* with its due date, if any. */}
              </p> // End of the paragraph.
            )}{/* End of this part. */}
            <p className="text-zinc-600">{/* A grey line: */}
              <strong>Went well on {latest.session_date}:</strong> {latest.went_well}{/* what went well, and when. */}
            </p>{/* End of the paragraph. */}
          </div> // End of the block.
        ) : ( // Otherwise:
          <p className="text-sm">The next step appears here after the first session note.</p> // says it shows after the first note.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}

      <Roadmap // The roadmap:
        studentId={id} // for this student,
        canPlan={canPlan} // who may plan,
        canRemoveAny={isStaff} // staff may remove any step,
        viewerId={viewer.id} // the viewer,
        isStudentSelf={student.data.account_id === viewer.id} // and whether the viewer is the student.
      />{/* (end of the roadmap) */}

      <TermReviewCard studentId={id} viewerId={viewer.id} isStaff={isStaff} isFamily={isFamily} />{/* The term review card. */}

      <EvidenceCard // The uploads card:
        studentId={id} // for this student,
        viewerId={viewer.id} // the viewer,
        today={localToday()} // today's date,
        canUpload={canPlan} // who may upload,
        canRemoveAny={viewer.roles.includes("admin") || student.data.account_id === viewer.id || Boolean(familyLink.data?.can_manage)} // who may remove any upload (admins, the student, a managing parent),
        canAddReports={viewer.roles.includes("admin") || Boolean(familyLink.data?.can_manage) || student.data.account_id === viewer.id} // who may add school reports (the same people),
        isStaff={isStaff} // whether staff,
        goalSkills={noteSkills} // and the goal skills.
      />{/* (end of the uploads card) */}

      <SeniorCertificateCard // The senior certificate card:
        studentId={id} // for this student,
        yearLevel={student.data.year_level} // their year level,
        canPlan={canPlan} // who may plan,
        thisYear={Number(localToday().slice(0, 4))} // and this year.
      />{/* (end of the card) */}

      {isFamily && latest && !reflectionOf(latest) && ( // For family, if the latest note has no reflection yet:
        <Card // a card:
          title="How did it go?" // titled "How did it go?",
          description={ // with a note:
            <>{/* (a group) */}
              A few seconds of thinking back helps learning stick. Younger students can answer with a parent.{/* on why reflecting helps. */}
            </> // End of the group.
          } // (end of the note)
        >{/* (end of the card's settings) */}
          <ReflectionForm studentId={id} noteId={latest.id} />{/* The reflection form. */}
        </Card> // End of the card.
      )}{/* End of this part. */}

      {isFamily && ( // For family:
        <Card // a card:
          title="Tell the tutor" // titled "Tell the tutor",
          description="Share feedback, or how practice is going at home. The tutor and CLG will see it." // with a note on who sees it.
        >{/* (end of the card's settings) */}
          <FamilyNoteForm studentId={id} />{/* The family note form. */}
        </Card> // End of the card.
      )}{/* End of this part. */}

      {isStaff && ( // For staff:
        <Card title="What the family asked for">{/* a card of what the family asked for: */}
          <div className="space-y-2 text-sm">{/* a block: */}
            <p>{/* a line: */}
              <strong>Subjects:</strong>{" "}{/* "Subjects:" and a space, */}
              {(requested.data ?? []).length > 0 // if any were given,
                ? (requested.data ?? []) // lists them:
                    .map((r) => `${r.subject} (${r.working_level ? `working at ${r.working_level}` : "level unsure"})`) // each subject with its working level (or "level unsure"),
                    .join(", ") // separated by commas,
                : "None given"}{/* otherwise "None given". */}
            </p>{/* End of the paragraph. */}
            {student.data.school && ( // If there's a school:
              <p>{/* a line: */}
                <strong>School, university or TAFE:</strong> {student.data.school}{/* "School, university or TAFE:" and its name. */}
              </p> // End of the paragraph.
            )}{/* End of this part. */}
            <CourseDetails // The course and units:
              program={student.data.program} // the degree or course,
              units={requested.data ?? []} // the units,
              overviewForm={ // the overview form:
                canWriteOverview // if the viewer may write overviews,
                  ? (u) => <CourseOverviewForm subjectId={u.id} overview={u.course_overview} /> // a form for each unit,
                  : undefined // otherwise none.
              } // (end of the form setting)
            />{/* (end of the element) */}
            <p>{/* A line: */}
              <strong>End goal:</strong> {student.data.goals || "None given"}{/* the end goal (or "None given"). */}
            </p>{/* End of the paragraph. */}
            {student.data.learning_needs && ( // If there are learning needs:
              <p>{/* a line: */}
                <strong>Learning needs:</strong> {student.data.learning_needs}{/* "Learning needs:" and the needs. */}
              </p> // End of the paragraph.
            )}{/* End of this part. */}
            {student.data.extra_info && ( // If there's other information:
              <p>{/* a line: */}
                <strong>Other information:</strong> {student.data.extra_info}{/* "Other information:" and the information. */}
              </p> // End of the paragraph.
            )}{/* End of this part. */}
          </div>{/* End of the block. */}
        </Card> // End of the card.
      )}{/* End of this part. */}

      <Card title="Goals and skills">{/* The "Goals and skills" card: */}
        {activeGoals.length === 0 ? ( // if there are no active goals:
          <p className="text-sm">No goals set yet. The tutor sets 1 to 3 goals per subject in the first sessions.</p> // says none yet, and how goals get set.
        ) : ( // Otherwise:
          <ul className="space-y-5">{/* a list: */}
            {activeGoals.map((g) => ( // for each goal:
              <li key={g.id}>{/* a list item: */}
                <div className="flex items-start justify-between gap-3">{/* a row: */}
                  <div>{/* a block: */}
                    <p className="font-medium">{g.title}</p>{/* the goal's title, */}
                    <p className="text-xs text-zinc-500">{/* a small grey line: */}
                      {g.subject}{/* the subject, */}
                      {g.target_date && `, aiming for ${g.target_date}`}{/* and the date aiming for, if any. */}
                    </p>{/* End of the paragraph. */}
                  </div>{/* End of the block. */}
                  {isStaff && ( // For staff:
                    <form action={closeGoal} className="flex gap-2">{/* a small form that closes the goal: */}
                      <input type="hidden" name="goal_id" value={g.id} />{/* the goal (hidden), */}
                      <input type="hidden" name="student_id" value={id} />{/* the student (hidden), */}
                      <BusyButton name="status" value="achieved" className="text-xs text-teal-700 underline">{/* a button that marks it achieved: */}
                        Achieved{/* "Achieved". */}
                      </BusyButton>{/* (end of the button) */}
                      <BusyButton name="status" value="stopped" className="text-xs text-zinc-500 underline">{/* a button that stops it: */}
                        Stop{/* "Stop". */}
                      </BusyButton>{/* (end of the button) */}
                    </form> // End of the form.
                  )}{/* End of this part. */}
                </div>{/* End of the block. */}
                {(() => { // Works out the skills to show:
                  // Show the skills being worked on now; the rest open on a tap.
                  const all = g.goal_skills.flatMap(({ skill }) => (skill ? [skill] : [])); // the goal's skills,
                  let now = all.filter((k) => currentSkillIds.has(k.id)); // those being worked on now,
                  if (now.length === 0) { // if none:
                    const next = all.find((k) => levelBySkill.get(k.id) !== "secure_on_own"); // the first not yet secure on their own,
                    now = next ? [next] : []; // just that one (if any).
                  } // End of the fallback.
                  const rest = all.filter((k) => !now.includes(k)); // The rest.
                  const item = (k: Skill) => ( // How one skill shows:
                    <li key={k.id} className="text-sm">{/* a list item: */}
                      <p>{skillLabel(k)}</p>{/* the skill's words, */}
                      <LevelBar level={levelBySkill.get(k.id) ?? "not_started"} />{/* and its level bar. */}
                    </li> // End of the item.
                  ); // End of item.
                  return ( // Shows:
                    <>{/* (a group) */}
                      <ul className="mt-2 space-y-2">{now.map(item)}</ul>{/* the skills now, */}
                      {rest.length > 0 && ( // if there are others:
                        <details className="mt-2">{/* an open-and-close box: */}
                          <summary className="cursor-pointer text-xs text-teal-800">{/* its title: */}
                            {now.length === 0 ? `Show all ${rest.length} skills` : `Show the other ${rest.length} skill${rest.length === 1 ? "" : "s"} in this goal`}{/* how many others there are. */}
                          </summary>{/* End of the title. */}
                          <ul className="mt-2 space-y-2">{rest.map(item)}</ul>{/* The other skills. */}
                        </details> // End of the box.
                      )}{/* End of this part. */}
                    </> // End of the group.
                  ); // End of what's shown.
                })()}{/* (runs straight away) */}
              </li> // End of the goal.
            ))}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of this part. */}
        <p className="mt-4 text-xs text-zinc-500">{/* A small grey note: */}
          The tutor chooses the skills, starting from the level the student seems to be at. They may change in the
          first three sessions as the tutor gets to know the student.{/* (how the tutor chooses skills) */}
        </p>{/* End of the paragraph. */}
        {closedGoals.length > 0 && ( // If there are finished goals:
          <p className="mt-4 text-xs text-zinc-500">{/* a small grey line: */}
            Finished goals: {closedGoals.map((g) => `${g.title} (${g.status})`).join("; ")}{/* lists them with how they ended. */}
          </p> // End of the paragraph.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}

      {isStaff && <StudentMaterialsCard materials={studentMaterials} skillNames={skillNameById} />}{/* For staff: the materials card. */}

      {isStaff && ( // For staff:
        <Card // a card:
          title="Write a session note" // titled "Write a session note",
          description={ // with a note:
            <>{/* (a group) */}
              About three minutes, within 24 hours of the session.{/* on how long and how soon. */}
            </> // End of the group.
          } // (end of the note)
        >{/* (end of the card's settings) */}
          {dueSessions.length > 0 && ( // If sessions are waiting for a note:
            <div className="mb-5 text-sm">{/* a block: */}
              <p className="font-medium">Sessions waiting for a note</p>{/* its heading, */}
              <ul className="mt-1 space-y-1">{/* a list: */}
                {dueSessions.map((d) => ( // for each waiting session:
                  <li key={d.session_id}>{/* a list item: */}
                    {d.session_id === chosenDue?.session_id ? ( // if it's the one being written,
                      <strong>{sessionWhen(d.starts_at)} (writing now)</strong> // says so in bold,
                    ) : ( // otherwise:
                      <TextLink href={`/students/${id}/progress?session=${d.session_id}`}>{/* a link to write it: */}
                        {sessionWhen(d.starts_at)}{/* its day and time. */}
                      </TextLink> // End of the link.
                    )}{/* End of this part. */}
                  </li> // End of the list item.
                ))}{/* End of the loop. */}
                <li>{/* A last list item: */}
                  {chosenDue ? ( // if a session is chosen,
                    <TextLink href={`/students/${id}/progress?session=none`}>A session that wasn&apos;t booked in the app</TextLink> // a link to write a note for a session not booked in the app,
                  ) : ( // otherwise:
                    <strong>A session that wasn&apos;t booked in the app (writing now)</strong> // says that's the one being written.
                  )}{/* End of this part. */}
                </li>{/* End of the list item. */}
              </ul>{/* End of the list. */}
            </div> // End of the block.
          )}{/* End of this part. */}
          <SessionNoteForm // The session note form:
            key={noteSession?.id ?? "none"} // (starts fresh when the session changes)
            studentId={id} // for this student,
            skills={noteSkills} // the goal skills,
            materials={studentMaterials.map((m) => ({ id: m.material_id, title: m.title, kind: m.kind, skillIds: m.goal_skill_ids }))} // the materials that fit,
            session={noteSession} // the session (if any),
            today={localToday()} // and today's date.
          />{/* (end of the form) */}
        </Card> // End of the card.
      )}{/* End of this part. */}

      {isStaff && ( // For staff:
        <Card title="Add a goal">{/* the "Add a goal" card: */}
          {frameworkIds.length === 0 ? ( // if the student has no curriculum:
            <p className="text-sm">An admin needs to set this student&apos;s curriculum first.</p> // says an admin must set one.
          ) : ( // Otherwise:
            <>{/* (a group) */}
              <form method="get" className="mb-4 flex items-end gap-3">{/* a small form that reloads the page with the choices: */}
                <label className="block flex-1 space-y-1">{/* a label: */}
                  <span className="text-sm font-medium">Subject</span>{/* "Subject", */}
                  <select // a drop-down:
                    name="subject" // sent as subject,
                    defaultValue={chosenSubject} // starting at the chosen subject,
                    className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none" // styled like the other boxes.
                  >{/* (end of the settings) */}
                    <option value="" disabled>{/* a blank first choice that can't be picked: */}
                      Choose…{/* "Choose…". */}
                    </option>{/* End of the choice. */}
                    {subjects.map((s) => ( // For each subject:
                      <option key={s} value={s}>{/* a choice: */}
                        {s}{/* its name. */}
                      </option> // End of the choice.
                    ))}{/* End of the loop. */}
                  </select>{/* End of the drop-down. */}
                </label>{/* End of the label. */}
                <label className="block space-y-1">{/* A label: */}
                  <span className="text-sm font-medium">Year level</span>{/* "Year level", */}
                  <select // a drop-down:
                    name="year" // sent as year,
                    defaultValue={chosenYear} // starting at the chosen year,
                    className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none" // styled like the other boxes.
                  >{/* (end of the settings) */}
                    <option value="all">All years</option>{/* an "All years" choice, */}
                    {YEAR_LEVELS.map((y) => ( // for each year level:
                      <option key={y} value={y}>{/* a choice: */}
                        {y}{/* its name. */}
                      </option> // End of the choice.
                    ))}{/* End of the loop. */}
                  </select>{/* End of the drop-down. */}
                </label>{/* End of the label. */}
                <Button type="submit">Show skills</Button>{/* The button that shows the skills. */}
              </form>{/* End of the form. */}
              {chosenSubject && ( // If a subject is chosen:
                <AddGoalForm // the add goal form:
                  studentId={id} // for this student,
                  subject={chosenSubject} // this subject,
                  skills={goalSkillChoices.map((s) => ({ // the skills to offer:
                    id: s.id, // each one's id,
                    label: skillLabel(s), // words,
                    levelBand: s.level_band, // year band,
                    ticked: levelFits(startLevel, s.level_band), // and whether it starts ticked (it fits the start level).
                  }))} // (end of the skills)
                  startLevel={startLevel} // and the start level.
                /> // (end of the form)
              )}{/* End of this part. */}
            </> // End of the group.
          )}{/* End of this part. */}
        </Card> // End of the card.
      )}{/* End of this part. */}

      {(familyNotes.data ?? []).length > 0 && ( // If there are notes from home:
        <Card collapsible title="Notes from home">{/* a card that can fold away: */}
          <ul className="space-y-3 text-sm">{/* a list: */}
            {(familyNotes.data as unknown as FamilyNote[]).map((n) => ( // for each note:
              <li key={n.id} className="border-t border-zinc-200 pt-3 first:border-0 first:pt-0">{/* a list item: */}
                <p className="text-xs text-zinc-500">{/* a small grey line: */}
                  {FAMILY_NOTE_NAMES[n.kind]}, {n.written_at.slice(0, 10)}{/* the kind and date, */}
                  {n.writer?.full_name && `, from ${n.writer.full_name}`}{/* and who wrote it. */}
                </p>{/* End of the paragraph. */}
                <p className="whitespace-pre-line">{n.body}</p>{/* The note, keeping its line breaks. */}
              </li> // End of the list item.
            ))}{/* End of the loop. */}
          </ul>{/* End of the list. */}
        </Card> // End of the card.
      )}{/* End of this part. */}

      <Card collapsible title="Recent sessions">{/* The "Recent sessions" card (can fold away): */}
        {noteRows.length === 0 ? ( // if there are none:
          <p className="text-sm">No sessions recorded yet.</p> // says so.
        ) : ( // Otherwise:
          <ul className="space-y-4 text-sm">{/* a list: */}
            {noteRows.map((n) => { // for each note:
              const reflection = reflectionOf(n); // the student's reflection,
              const staff = staffByNote.get(n.id); // the staff-only note,
              return ( // shows:
                <li key={n.id} className="border-t border-zinc-200 pt-3 first:border-0 first:pt-0">{/* a list item: */}
                  <p className="font-medium">{/* a line: */}
                    {n.session_date}: {ATTENDANCE_NAMES[n.attendance]}{/* the date and attendance, */}
                    {n.minutes ? `, ${n.minutes} min` : ""}{/* the minutes, */}
                    {n.tutor?.account?.full_name && ` with ${n.tutor.account.full_name}`}{/* and the tutor's name. */}
                  </p>{/* End of the paragraph. */}
                  {n.went_well && <p>Went well: {n.went_well}</p>}{/* What went well. */}
                  {n.next_step && <p>Next step: {n.next_step}</p>}{/* The next step. */}
                  {n.homework && <p>Practice: {n.homework}</p>}{/* The homework. */}
                  {n.home_tip && <p>Try at home: {n.home_tip}</p>}{/* The home tip. */}
                  {n.session_note_skills.length > 0 && ( // If skills were worked on:
                    <ul className="mt-1 list-disc pl-5 text-zinc-600">{/* a list: */}
                      {n.session_note_skills.map((s) => ( // for each skill:
                        <li key={s.skill_id}>{/* a list item: */}
                          {s.skill ? skillLabel(s.skill) : "Skill"}:{" "}{/* the skill's words and a space, */}
                          {s.level_before === s.level_after // if its level didn't change,
                            ? levelName(s.level_after) // the level,
                            : `${levelName(s.level_before)} → ${levelName(s.level_after)}`}{/* otherwise the old level and the new one. */}
                        </li> // End of the list item.
                      ))}{/* End of the loop. */}
                    </ul> // End of the list.
                  )}{/* End of this part. */}
                  {reflection && ( // If the student reflected:
                    <p className="mt-1 text-zinc-600">{/* a grey line: */}
                      Student&apos;s reflection: {CONFIDENCE_NAMES[reflection.confidence]}{/* their confidence, */}
                      {reflection.what_was_hard && `. Hard: ${reflection.what_was_hard}`}{/* what was hard, */}
                      {reflection.what_i_will_try && `. Will try: ${reflection.what_i_will_try}`}{/* and what they'll try. */}
                    </p> // End of the paragraph.
                  )}{/* End of this part. */}
                  {staff && ( // If there's a staff note:
                    <p className="mt-1 rounded bg-amber-50 px-2 py-1 text-amber-900">{/* an amber line: */}
                      Staff only: {staff}{/* "Staff only:" and the note. */}
                    </p> // End of the paragraph.
                  )}{/* End of this part. */}
                </li> // End of the list item.
              ); // End of what's shown.
            })}{/* End of the note. */}
          </ul> // End of the list.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of ProgressPage.

// The four-step scale as a simple bar: filled steps show where the skill is.
function LevelBar({ level }: { level: SkillLevel }) { // (takes the skill's level)
  const reached = SKILL_LEVELS.indexOf(level); // How many steps it has reached.
  return ( // Shows:
    <div className="mt-1 flex items-center gap-2" aria-label={`Level: ${levelName(level)}`}>{/* a row (read aloud as the level): */}
      <div className="flex gap-1">{/* a row of steps: */}
        {SKILL_LEVELS.slice(1).map((l, i) => ( // for each step after "not started":
          <span // a short bar:
            key={l} // (a bar)
            className={`h-2 w-8 rounded-full ${i < reached ? "bg-teal-600" : "bg-zinc-200"}`} // filled if reached, grey if not.
          /> // (end of the element)
        ))}{/* End of the loop. */}
      </div>{/* End of the steps. */}
      <span className="text-xs text-zinc-600">{levelName(level)}</span>{/* The level's name. */}
    </div> // End of the row.
  ); // End of what's shown.
} // End of LevelBar.
