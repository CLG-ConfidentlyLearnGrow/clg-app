// Summary: the child details form shared by parents (adding their own child)
// and admins (setting up a family): the rules each field must meet, and
// reading the subjects that were ticked.

// The form-checking library.
import { z } from "zod";
// The list of Australian states.
import { STATES } from "@/lib/checks";
// The list of year levels, and the check that maths subjects are named correctly.
import { YEAR_LEVELS, mathsProblem } from "@/lib/students";

// The rules for each field on the child details form, with plain error messages.
export const childSchema = z.object({
  full_name: z.string().trim().min(1, "Enter your child's name.").max(200), // Name is required, up to 200 letters.
  date_of_birth: z.iso.date("Enter your child's date of birth."), // Must be a real date.
  state: z.enum(STATES, "Choose the state your child lives in."), // Must be one of the Australian states.
  year_level: z.enum(YEAR_LEVELS, "Choose your child's year level. CLG uses it to match the right tutor."), // Must be from the year level list.
  school: z.string().trim().min(1, "Enter your child's school.").max(200), // School is required, up to 200 letters.
  goals: z // The family's end goal for support:
    .string("Tell us what you'd like CLG's support to achieve.") // must be text,
    .trim() // with spaces removed from the ends,
    .min(1, "Tell us what you'd like CLG's support to achieve.") // can't be blank,
    .max(4000, "Please keep the end goal under 4,000 characters."), // and is up to 4,000 letters.
  extra_info: z.string().trim().max(2000, "Please keep other information under 2,000 characters.").optional(), // Optional, up to 2,000 letters.
  learning_needs: z.string().trim().max(2000, "Please keep learning needs under 2,000 characters.").optional(), // Optional, up to 2,000 letters.
  // University or TAFE: the degree or course overall.
  program: z.string().trim().max(300, "Please keep the degree or course name under 300 characters.").optional(), // Optional, up to 300 letters.
}); // End of the child form rules.

// The subjects the family ticked or typed, each with the level the child is
// working at (null = not sure), tidied and without repeats.
// University and TAFE units can also carry a unit code and a link.
export type Wanted = { subject: string; level: string | null; course_code?: string; course_url?: string };
// The rules for the list of subjects sent from the form.
const wantedSchema = z.array(
  z.object({ // Each subject must have:
    subject: z.string().trim().min(1).max(100, "Each subject name must be under 100 characters."), // a name up to 100 letters,
    level: z.enum(YEAR_LEVELS, "Choose a level from the list, or Not sure.").nullable(), // a level from the list, or "not sure",
    course_code: z.string().trim().max(40, "Please keep each unit code under 40 characters.").optional(), // an optional unit code,
    course_url: z // and an optional course link, which is either:
      .union([ // one of two things:
        z.literal(""), // blank,
        z // or
          .url({ protocol: /^https?$/, error: "Each course link must be a web address starting with https://" }) // a proper web address,
          .max(500, "Please keep each course link under 500 characters."), // up to 500 letters.
      ]) // End of the two choices.
      .optional(), // The link can be left out entirely.
  }), // End of one subject's rules.
); // End of the subject list rules.

// Reads and checks the subjects from the form, or gives back a plain error.
export function readSubjects(formData: FormData): Wanted[] | { error: string } {
  let raw: unknown; // Will hold the subjects as sent by the page.
  try { // Reading could fail if the data is damaged.
    raw = JSON.parse(String(formData.get("subjects_json") ?? "[]")); // Turns the hidden field's text into a list.
  } catch { // The text couldn't be read.
    return { error: "Please choose the subjects again." }; // Asks the person to pick again.
  } // End of the reading step.
  const parsed = wantedSchema.safeParse(raw); // Checks the list against the rules above.
  const yearLevel = String(formData.get("year_level") ?? "") || null; // The child's year level, used when a subject's level is "not sure".
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const seen = new Set<string>(); // Subject names already added, to skip repeats.
  const subjects: Wanted[] = []; // The tidied list.
  for (const s of parsed.data) { // Goes through each subject.
    const problem = mathsProblem(s.subject, s.level ?? yearLevel); // Checks maths is named correctly for this level.
    if (problem) return { error: problem }; // Stops with that message if not.
    if (!seen.has(s.subject.toLowerCase())) { // Only adds it if not already in the list (ignoring capitals).
      seen.add(s.subject.toLowerCase()); // Remembers it has been added.
      subjects.push({ // Adds the subject:
        subject: s.subject, // its name,
        level: s.level, // its level,
        ...(s.course_code ? { course_code: s.course_code } : {}), // its unit code, if any,
        ...(s.course_url ? { course_url: s.course_url.trim() } : {}), // and its link, if any.
      }); // End of this subject.
    } // End of the repeat check.
  } // End of the loop over subjects.
  if (subjects.length === 0) return { error: "Choose at least one subject your child wants help with." }; // At least one is needed.
  if (subjects.length > 10) return { error: "Please choose up to 10 subjects." }; // No more than 10.
  return subjects; // Hands back the tidied list.
} // End of readSubjects.

