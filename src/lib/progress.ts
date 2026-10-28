// Words for progress tracking, shown in the app.

export const SKILL_LEVELS = ["not_started", "learning", "secure_with_help", "secure_on_own"] as const;
export type SkillLevel = (typeof SKILL_LEVELS)[number];

export const SKILL_LEVEL_NAMES: Record<SkillLevel, string> = {
  not_started: "Not started",
  learning: "Learning",
  secure_with_help: "Secure with help",
  secure_on_own: "Secure on own",
};

export const ATTENDANCE = ["attended", "late", "absent", "cut_short"] as const;
export type Attendance = (typeof ATTENDANCE)[number];

export const ATTENDANCE_NAMES: Record<Attendance, string> = {
  attended: "Attended",
  late: "Started late",
  absent: "Absent",
  cut_short: "Cut short",
};

export const CONFIDENCE_NAMES: Record<number, string> = {
  1: "Not confident yet",
  2: "A little confident",
  3: "Fairly confident",
  4: "Very confident",
};

// The levels a skill may move to in one session: stay, or one step either way.
export function nextLevels(current: SkillLevel): SkillLevel[] {
  const i = SKILL_LEVELS.indexOf(current);
  return SKILL_LEVELS.filter((_, j) => Math.abs(j - i) <= 1);
}

export const levelName = (level: string) => SKILL_LEVEL_NAMES[level as SkillLevel] ?? level;

// A session is due a note within 24 hr; after 48 hr admins are told.
export const NOTE_DUE_HOURS = 24;
export const NOTE_OVERDUE_HOURS = 48;

// Sessions in a row with no skill moving before the plan needs a look.
export const STALLED_AFTER_SESSIONS = 4;

// "2 min 20 sec" from seconds.
export function minutesAndSeconds(total: number | null): string {
  if (total === null || total === undefined) return "-";
  const m = Math.floor(total / 60);
  const s = total % 60;
  return m > 0 ? `${m} min${s ? ` ${s} sec` : ""}` : `${s} sec`;
}

// "5 hr ago", "2 days ago".
export function hoursAgo(hours: number): string {
  if (hours < 48) return `${hours} hr ago`;
  return `${Math.floor(hours / 24)} days ago`;
}

export const RECOMMENDATION_NAMES: Record<string, string> = {
  continue: "Continue as we are",
  change_focus: "Change the focus",
  more_sessions: "Add more sessions",
  fewer_sessions: "Fewer sessions",
  break: "Take a break",
};
