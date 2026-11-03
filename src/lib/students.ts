// Year levels a student can choose. Keep in step with private.is_year_level
// in supabase/migrations/20261026000900_student_year_level.sql.
export const YEAR_LEVELS = [
  "Foundation",
  "Year 1",
  "Year 2",
  "Year 3",
  "Year 4",
  "Year 5",
  "Year 6",
  "Year 7",
  "Year 8",
  "Year 9",
  "Year 10",
  "Year 11",
  "Year 12",
  "University or TAFE",
  "Adult learner",
] as const;

export type YearLevel = (typeof YEAR_LEVELS)[number];

// What families see. The first school year has a different name in each state.
export const YEAR_LEVEL_NAMES: Record<YearLevel, string> = {
  Foundation: "Foundation (Reception, Prep, Kindergarten, Pre-primary or Transition)",
  "Year 1": "Year 1",
  "Year 2": "Year 2",
  "Year 3": "Year 3",
  "Year 4": "Year 4",
  "Year 5": "Year 5",
  "Year 6": "Year 6",
  "Year 7": "Year 7",
  "Year 8": "Year 8",
  "Year 9": "Year 9",
  "Year 10": "Year 10",
  "Year 11": "Year 11",
  "Year 12": "Year 12",
  "University or TAFE": "University or TAFE",
  "Adult learner": "Adult learner (not currently studying)",
};

// Subjects families and tutors choose from (Carla, 2 Nov 2026). The list
// depends on the student's year level: Foundation to Year 10 follows the
// Australian Curriculum, Years 11 and 12 follow SACE. Anyone can also type
// another subject.
const byName = (a: string, b: string) => a.localeCompare(b);

export const JUNIOR_SUBJECTS = [
  "Digital Technologies",
  "Economics and Business",
  "English",
  "Humanities and Social Sciences",
  "Mathematics",
  "Science",
  "Study skills",
] as const;

// Maths in Years 11 and 12 is four separate SACE subjects.
export const SENIOR_MATHS = [
  "Mathematics: Essential",
  "Mathematics: General",
  "Mathematics: Methods",
  "Mathematics: Specialist",
] as const;

export const SENIOR_SUBJECTS = [
  "Activating Identities and Futures (AIF) / Research Project",
  "Biology",
  "Chemistry",
  "Digital Technologies",
  "Economics and Business",
  "English",
  ...SENIOR_MATHS,
  "Physics",
  "Psychology",
  "Study skills",
] as const;

// Every subject, A to Z. Used where the year level isn't known, and for
// university, TAFE and adult learners.
export const SUBJECT_SUGGESTIONS: readonly string[] = [...new Set<string>([...JUNIOR_SUBJECTS, ...SENIOR_SUBJECTS])].sort(byName);

const SENIOR_LEVELS = new Set(["Year 11", "Year 12"]);
const JUNIOR_LEVELS = new Set<string>(YEAR_LEVELS.slice(0, YEAR_LEVELS.indexOf("Year 10") + 1));

// The subjects to offer a student in this year level, A to Z.
export function subjectsFor(yearLevel?: string | null): readonly string[] {
  if (yearLevel && JUNIOR_LEVELS.has(yearLevel)) return [...JUNIOR_SUBJECTS].sort(byName);
  if (yearLevel && SENIOR_LEVELS.has(yearLevel)) return [...SENIOR_SUBJECTS].sort(byName);
  return SUBJECT_SUGGESTIONS;
}

// "Maths" on its own is ambiguous: Foundation to Year 10 is "Mathematics";
// Years 11 and 12 choose one of the four SACE maths subjects. Returns a plain
// message when the subject doesn't suit the levels, or null when it's fine.
const MATHS_WORDS = new Set(["maths", "math"]);
export function mathsProblem(subject: string, highestLevel?: string | null): string | null {
  const s = subject.trim().toLowerCase();
  if (MATHS_WORDS.has(s)) {
    return "Choose Mathematics for Foundation to Year 10, or Mathematics: Essential, General, Methods or Specialist for Years 11 and 12.";
  }
  if (s === "mathematics" && highestLevel && !JUNIOR_LEVELS.has(highestLevel)) {
    return "Mathematics covers Foundation to Year 10. For Year 11 and above, choose Mathematics: Essential, General, Methods or Specialist.";
  }
  return null;
}

// The same subject and level matching the database uses to attach a
// curriculum (private.subject_fits and private.level_fits), so "General
// Maths" finds the Australian Curriculum's "Mathematics".
function normSubject(s: string) {
  return s
    .toLowerCase()
    .trim()
    .replace(/\(.*\)/g, "")
    .replace(/\s+(f|\d+)\s*[-–]\s*\d+$/, "")
    .replace(/^mathematics:\s*(essential|general|methods|specialist)$/, "$1 mathematics")
    .replace(/^methods mathematics$/, "mathematical methods")
    .replace(/\bmaths?\b/g, "mathematics")
    .replace(/^humanities and social sciences$/, "hass")
    .replace(/\s+/g, " ")
    .trim();
}

export function subjectFits(requested: string, curriculum: string) {
  const req = normSubject(requested);
  const cur = normSubject(curriculum);
  return (
    req !== "" &&
    (cur === req ||
      cur === req.replace(/^(general|essential|advanced|specialist|foundation) /, "") ||
      (req === "literacy" && cur === "english") ||
      (req === "numeracy" && cur === "mathematics"))
  );
}

export function levelFits(level: string | null, band: string) {
  if (!level) return false;
  const l = level.trim().toLowerCase();
  const b = band.trim().toLowerCase();
  return b === l || b.startsWith(`${l} (`);
}

// Shown under every date of birth field.
export const DOB_HINT =
  "We ask for date of birth so we can apply the privacy and child safety protections that suit each age group.";
