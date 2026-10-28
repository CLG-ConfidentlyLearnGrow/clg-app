// The child details form shared by parents (adding their own child) and
// admins (setting up a family): field rules and the ticked subjects.
import { z } from "zod";
import { STATES } from "@/lib/checks";
import { PLAIN_MATHS, YEAR_LEVELS } from "@/lib/students";

export const childSchema = z.object({
  full_name: z.string().trim().min(1, "Enter your child's name.").max(200),
  date_of_birth: z.iso.date("Enter your child's date of birth."),
  state: z.enum(STATES, "Choose the state your child lives in."),
  year_level: z.enum(YEAR_LEVELS, "Choose your child's year level. CLG uses it to match the right tutor."),
  school: z.string().trim().min(1, "Enter your child's school.").max(200),
  goals: z
    .string("Tell us what you'd like CLG's support to achieve.")
    .trim()
    .min(1, "Tell us what you'd like CLG's support to achieve.")
    .max(4000, "Please keep the end goal under 4,000 characters."),
  extra_info: z.string().trim().max(2000, "Please keep other information under 2,000 characters.").optional(),
});

// The subjects the family ticked or typed, each with the level the child is
// working at (null = not sure), tidied and without repeats.
export type Wanted = { subject: string; level: string | null };
const wantedSchema = z.array(
  z.object({
    subject: z.string().trim().min(1).max(100, "Each subject name must be under 100 characters."),
    level: z.enum(YEAR_LEVELS, "Choose a level from the list, or Not sure.").nullable(),
  }),
);

export function readSubjects(formData: FormData): Wanted[] | { error: string } {
  let raw: unknown;
  try {
    raw = JSON.parse(String(formData.get("subjects_json") ?? "[]"));
  } catch {
    return { error: "Please choose the subjects again." };
  }
  const parsed = wantedSchema.safeParse(raw);
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const seen = new Set<string>();
  const subjects: Wanted[] = [];
  for (const s of parsed.data) {
    if (PLAIN_MATHS.has(s.subject.toLowerCase())) {
      return { error: "For Maths, please tick General, Essential or Advanced Maths." };
    }
    if (!seen.has(s.subject.toLowerCase())) {
      seen.add(s.subject.toLowerCase());
      subjects.push(s);
    }
  }
  if (subjects.length === 0) return { error: "Choose at least one subject your child wants help with." };
  if (subjects.length > 10) return { error: "Please choose up to 10 subjects." };
  return subjects;
}

