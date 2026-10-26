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
