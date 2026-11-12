// Summary: words and small helpers for progress tracking, shown in the app:
// skill levels, attendance, confidence, note timings, evidence kinds and
// senior certificate (SACE) areas.
//
// Words for progress tracking, shown in the app.

// The four steps a skill moves through, in order.
export const SKILL_LEVELS = ["not_started", "learning", "secure_with_help", "secure_on_own"] as const;
export type SkillLevel = (typeof SKILL_LEVELS)[number]; // The allowed level codes, for type checking.

// The plain name of each skill level.
export const SKILL_LEVEL_NAMES: Record<SkillLevel, string> = {
  not_started: "Not started", // Hasn't begun this skill.
  learning: "Learning", // Working on it.
  secure_with_help: "Secure with help", // Can do it with support.
  secure_on_own: "Secure on own", // Can do it alone.
}; // End of the level names.

// The ways a student can attend a session.
export const ATTENDANCE = ["attended", "late", "absent", "cut_short"] as const;
export type Attendance = (typeof ATTENDANCE)[number]; // The allowed attendance codes, for type checking.

// The plain name of each attendance code.
export const ATTENDANCE_NAMES: Record<Attendance, string> = {
  attended: "Attended", // Came on time.
  late: "Started late", // Came late.
  absent: "Absent", // Didn't come.
  cut_short: "Cut short", // Session ended early.
}; // End of the attendance names.

// How confident the student says they feel, from 1 to 4.
export const CONFIDENCE_NAMES: Record<number, string> = {
  1: "Not confident yet", // Level 1.
  2: "A little confident", // Level 2.
  3: "Fairly confident", // Level 3.
  4: "Very confident", // Level 4.
}; // End of the confidence names.

// The levels a skill may move to in one session: stay, or one step either way.
export function nextLevels(current: SkillLevel): SkillLevel[] {
  const i = SKILL_LEVELS.indexOf(current); // Where the current level sits in the list.
  return SKILL_LEVELS.filter((_, j) => Math.abs(j - i) <= 1); // Keeps levels no more than one step away.
} // End of nextLevels.

export const levelName = (level: string) => SKILL_LEVEL_NAMES[level as SkillLevel] ?? level; // Turns a level code into its plain name, or shows the code if unknown.

// A session is due a note within 24 hr; after 48 hr admins are told.
export const NOTE_DUE_HOURS = 24; // Hours after a session when its note is due.
export const NOTE_OVERDUE_HOURS = 48; // Hours after a session when admins are told the note is late.

// Sessions in a row with no skill moving before the plan needs a look.
export const STALLED_AFTER_SESSIONS = 4; // Sessions in a row with no skill moving.

// "2 min 20 sec" from seconds.
export function minutesAndSeconds(total: number | null): string {
  if (total === null || total === undefined) return "-"; // No time recorded: shows a dash.
  const m = Math.floor(total / 60); // Whole minutes.
  const s = total % 60; // Leftover seconds.
  return m > 0 ? `${m} min${s ? ` ${s} sec` : ""}` : `${s} sec`; // "2 min 20 sec", "2 min", or "20 sec".
} // End of minutesAndSeconds.

// "5 hr ago", "2 days ago".
export function hoursAgo(hours: number): string {
  if (hours < 48) return `${hours} hr ago`; // Under 2 days: shows hours.
  return `${Math.floor(hours / 24)} days ago`; // Otherwise shows whole days.
} // End of hoursAgo.

// The plain name of each recommendation in a progress review.
export const RECOMMENDATION_NAMES: Record<string, string> = {
  continue: "Continue as we are", // Keep the plan.
  change_focus: "Change the focus", // Work on something else.
  more_sessions: "Add more sessions", // Increase sessions.
  fewer_sessions: "Fewer sessions", // Reduce sessions.
  break: "Take a break", // Pause support.
}; // End of the recommendation names.

// Evidence of learning: what families, students and tutors can upload.
export const EVIDENCE_KINDS = ["graded_work", "school_report", "naplan", "other_assessment", "work_sample"] as const; // The kinds of evidence that can be uploaded.
// School reports and NAPLAN results are uploaded by a parent.
export const PARENT_ONLY_KINDS: readonly string[] = ["school_report", "naplan"]; // Only parents can upload these kinds.
// The plain name of each evidence kind.
export const EVIDENCE_KIND_NAMES: Record<string, string> = {
  graded_work: "Marked school work or test", // Shown name for graded_work.
  school_report: "School report", // Shown name for school_report.
  naplan: "NAPLAN results", // Shown name for naplan.
  other_assessment: "Other assessment", // Shown name for other_assessment.
  work_sample: "Sample of work", // Shown name for work_sample.
  task_sheet: "Task sheet", // Shown name for task_sheet.
  rubric: "Rubric", // Shown name for rubric.
}; // End of the evidence names.

// The compulsory parts of a senior certificate a subject can count towards (SACE).
export const SENIOR_AREA_NAMES: Record<string, string> = {
  eif: "Exploring Identities and Futures", // Exploring Identities and Futures.
  literacy: "Literacy (an English subject)", // The literacy requirement.
  numeracy: "Numeracy (a Maths subject)", // The numeracy requirement.
  aif: "Activating Identities and Futures (or Research Project)", // Activating Identities and Futures.
}; // End of the area names.

// The plain name of each stage of a senior subject.
export const SENIOR_STATUS_NAMES: Record<string, string> = {
  planned: "Planning to take", // Not started yet.
  studying: "Studying now", // Studying it now.
  finished: "Finished", // Completed.
}; // End of the stage names.
