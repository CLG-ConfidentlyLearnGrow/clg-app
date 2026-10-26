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
