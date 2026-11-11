// Summary: year levels, subject lists and the subject and level matching
// rules used when families choose subjects and when curriculums are attached.
//
// Year levels a student can choose. Keep in step with private.is_year_level
// in supabase/migrations/20261026000900_student_year_level.sql.
export const YEAR_LEVELS = [
  "Foundation", // Foundation.
  "Year 1", // Year 1.
  "Year 2", // Year 2.
  "Year 3", // Year 3.
  "Year 4", // Year 4.
  "Year 5", // Year 5.
  "Year 6", // Year 6.
  "Year 7", // Year 7.
  "Year 8", // Year 8.
  "Year 9", // Year 9.
  "Year 10", // Year 10.
  "Year 11", // Year 11.
  "Year 12", // Year 12.
  "University or TAFE", // University or TAFE.
  "Adult learner", // Adult learner.
] as const; // "as const" keeps the exact values for type checking.

export type YearLevel = (typeof YEAR_LEVELS)[number]; // The allowed year levels, for type checking.

// What families see. The first school year has a different name in each state.
// Each year level's name as families see it.
export const YEAR_LEVEL_NAMES: Record<YearLevel, string> = {
  Foundation: "Foundation (Reception, Prep, Kindergarten, Pre-primary or Transition)", // The first school year's names across the states.
  "Year 1": "Year 1", // Shown as is.
  "Year 2": "Year 2", // Shown as is.
  "Year 3": "Year 3", // Shown as is.
  "Year 4": "Year 4", // Shown as is.
  "Year 5": "Year 5", // Shown as is.
  "Year 6": "Year 6", // Shown as is.
  "Year 7": "Year 7", // Shown as is.
  "Year 8": "Year 8", // Shown as is.
  "Year 9": "Year 9", // Shown as is.
  "Year 10": "Year 10", // Shown as is.
  "Year 11": "Year 11", // Shown as is.
  "Year 12": "Year 12", // Shown as is.
  "University or TAFE": "University or TAFE", // Shown as is.
  "Adult learner": "Adult learner (not currently studying)", // Explains it means not currently studying.
}; // End of the names.

// Subjects families and tutors choose from (Carla, 2 Nov 2026). The list
// depends on the student's year level: Foundation to Year 10 follows the
// Australian Curriculum, Years 11 and 12 follow SACE. Anyone can also type
// another subject.
const byName = (a: string, b: string) => a.localeCompare(b); // Sorts text A to Z the way people expect.

// Subjects offered from Foundation to Year 10.
export const JUNIOR_SUBJECTS = [
  "Digital Technologies", // Digital Technologies.
  "Economics and Business", // Economics and Business.
  "English", // English.
  "Humanities and Social Sciences", // Humanities and Social Sciences.
  "Mathematics", // Mathematics.
  "Science", // Science.
  "Study skills", // Study skills.
] as const; // "as const" keeps these fixed.

// Maths in Years 11 and 12 is four separate SACE subjects.
// The four SACE maths subjects:
export const SENIOR_MATHS = [
  "Mathematics: Essential", // Essential,
  "Mathematics: General", // General,
  "Mathematics: Methods", // Methods,
  "Mathematics: Specialist", // Specialist.
] as const; // "as const" keeps these fixed.

// Subjects offered in Years 11 and 12.
export const SENIOR_SUBJECTS = [
  "Activating Identities and Futures (AIF) / Research Project", // Research Project.
  "Biology", // Biology.
  "Chemistry", // Chemistry.
  "Digital Technologies", // Digital Technologies.
  "Economics and Business", // Economics and Business.
  "English", // English.
  ...SENIOR_MATHS, // The four maths subjects.
  "Physics", // Physics.
  "Psychology", // Psychology.
  "Study skills", // Study skills.
] as const; // "as const" keeps these fixed.

// Every subject, A to Z. Used where the year level isn't known, and for
// university, TAFE and adult learners.
export const SUBJECT_SUGGESTIONS: readonly string[] = [...new Set<string>([...JUNIOR_SUBJECTS, ...SENIOR_SUBJECTS])].sort(byName); // Joins both lists, removes repeats, sorts A to Z.

const SENIOR_LEVELS = new Set(["Year 11", "Year 12"]); // Year 11 and Year 12.
const JUNIOR_LEVELS = new Set<string>(YEAR_LEVELS.slice(0, YEAR_LEVELS.indexOf("Year 10") + 1)); // Foundation up to and including Year 10.

// The subjects to offer a student in this year level, A to Z.
export function subjectsFor(yearLevel?: string | null): readonly string[] {
  if (yearLevel && JUNIOR_LEVELS.has(yearLevel)) return [...JUNIOR_SUBJECTS].sort(byName); // Foundation to Year 10: the junior list.
  if (yearLevel && SENIOR_LEVELS.has(yearLevel)) return [...SENIOR_SUBJECTS].sort(byName); // Years 11 and 12: the senior list.
  return SUBJECT_SUGGESTIONS; // Anything else: every subject.
} // End of subjectsFor.

// "Maths" on its own is ambiguous: Foundation to Year 10 is "Mathematics";
// Years 11 and 12 choose one of the four SACE maths subjects. Returns a plain
// message when the subject doesn't suit the levels, or null when it's fine.
const MATHS_WORDS = new Set(["maths", "math"]); // "Maths" and "math" on their own.
// Checks a maths subject name suits the student's highest level.
export function mathsProblem(subject: string, highestLevel?: string | null): string | null {
  const s = subject.trim().toLowerCase(); // The subject in lower case, without spaces at the ends.
  if (MATHS_WORDS.has(s)) { // Just "maths" or "math":
    return "Choose Mathematics for Foundation to Year 10, or Mathematics: Essential, General, Methods or Specialist for Years 11 and 12."; // asks them to pick the right maths subject.
  } // End of that case.
  if (s === "mathematics" && highestLevel && !JUNIOR_LEVELS.has(highestLevel)) { // "Mathematics" for Year 11 or above:
    return "Mathematics covers Foundation to Year 10. For Year 11 and above, choose Mathematics: Essential, General, Methods or Specialist."; // asks them to pick a SACE maths subject.
  } // End of that case.
  return null; // Otherwise fine.
} // End of mathsProblem.

// The same subject and level matching the database uses to attach a
// curriculum (private.subject_fits and private.level_fits), so "General
// Maths" finds the Australian Curriculum's "Mathematics".
function normSubject(s: string) {
  return s // Starting from the name,
    .toLowerCase() // lower case,
    .trim() // no spaces at the ends,
    .replace(/\(.*\)/g, "") // drops anything in brackets,
    .replace(/\s+(f|\d+)\s*[-–]\s*\d+$/, "") // drops a year range at the end (e.g. "F-10", "7–10"),
    .replace(/^mathematics:\s*(essential|general|methods|specialist)$/, "$1 mathematics") // "Mathematics: General" becomes "general mathematics",
    .replace(/^methods mathematics$/, "mathematical methods") // "methods mathematics" becomes "mathematical methods",
    .replace(/\bmaths?\b/g, "mathematics") // "maths" or "math" become "mathematics",
    .replace(/^humanities and social sciences$/, "hass") // Humanities and Social Sciences becomes "hass",
    .replace(/\s+/g, " ") // collapses spaces,
    .trim(); // and trims again.
} // End of normSubject.

// True if a requested subject matches a curriculum's subject.
export function subjectFits(requested: string, curriculum: string) {
  const req = normSubject(requested); // The tidied request.
  const cur = normSubject(curriculum); // The tidied curriculum subject.
  return ( // True when:
    req !== "" && // the request isn't blank, and
    (cur === req || // they match exactly,
      cur === req.replace(/^(general|essential|advanced|specialist|foundation) /, "") || // or they match once "general", "essential" and similar are dropped,
      (req === "literacy" && cur === "english") || // or literacy is asked and it's English,
      (req === "numeracy" && cur === "mathematics")) // or numeracy is asked and it's Mathematics.
  ); // End of the test.
} // End of subjectFits.

// True if a student's level matches a curriculum level band.
export function levelFits(level: string | null, band: string) {
  if (!level) return false; // No level: no match.
  const l = level.trim().toLowerCase(); // The level in lower case.
  const b = band.trim().toLowerCase(); // The band in lower case.
  return b === l || b.startsWith(`${l} (`); // Same, or the band is the level with a note in brackets.
} // End of levelFits.

// Shown under every date of birth field.
export const DOB_HINT =
  "We ask for date of birth so we can apply the privacy and child safety protections that suit each age group."; // Why we ask for date of birth.
