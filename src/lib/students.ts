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

// Suggestions for the subject box. Tutors can also type their own.
// Maths is split three ways because each is taught very differently.
export const MATHS_SUBJECTS = ["General Maths", "Essential Maths", "Advanced Maths"] as const;
export const PLAIN_MATHS = new Set(["maths", "math", "mathematics"]);

export const SUBJECT_SUGGESTIONS = [
  ...MATHS_SUBJECTS,
  "English",
  "Science",
  "Humanities and Social Sciences",
  "History",
  "Geography",
  "Economics and Business",
  "Digital Technologies",
  "Literacy",
  "Numeracy",
  "Biology",
  "Chemistry",
  "Physics",
  "Psychology",
  "English Literary Studies",
  "Essential English",
  "Research Project",
  "Study skills",
] as const;

// The same subject and level matching the database uses to attach a
// curriculum (private.subject_fits and private.level_fits), so "General
// Maths" finds the Australian Curriculum's "Mathematics".
function normSubject(s: string) {
  return s
    .toLowerCase()
    .trim()
    .replace(/\(.*\)/g, "")
    .replace(/\s+(f|\d+)\s*[-–]\s*\d+$/, "")
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
