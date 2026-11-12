// Summary: "Become a learner too". Someone already signed in adds a student
// profile to their own account.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { redirect } from "next/navigation"; // Lets the code send someone to another page.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { readSubjects } from "@/lib/child-form"; // Reads and checks the subjects chosen.
import { STATES } from "@/lib/checks"; // The list of Australian states.
import { saveStudyDetails } from "@/lib/study-details"; // Saves a university or TAFE student's degree and unit details.
import { YEAR_LEVELS } from "@/lib/students"; // The list of year levels.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// "Become a learner too": someone already signed in (a tutor, admin or
// parent) adds a student profile to their own account. The database checks
// they are 16 or over. See docs/features/become-a-learner.md.
// The rules for the learner form:
const learnerSchema = z.object({
  date_of_birth: z.iso.date("Enter your date of birth."), // date of birth (a real date),
  state: z.enum(STATES, "Choose the state you live in."), // state (one of the list),
  year_level: z.enum(YEAR_LEVELS, "Choose your year level or stage of study."), // year level or stage of study (one of the list),
  school: z.string().trim().min(1, "Enter your school, university or TAFE.").max(200), // school, university or TAFE (required, up to 200 letters),
  goals: z.string().trim().max(4000, "Please keep the end goal under 4,000 characters.").optional(), // end goal (optional, up to 4,000 letters),
  program: z.string().trim().max(300, "Please keep the degree or course name under 300 characters.").optional(), // degree or course name (optional, up to 300 letters).
}); // End of the rules.

// Adds a student profile to the signed-in person's account.
export async function addMeAsLearner(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (viewer.roles.includes("student")) redirect("/dashboard/student"); // Already a student: goes to the student dashboard.
  const parsed = learnerSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const picked = readSubjects(formData); // Reads the chosen subjects.
  if ("error" in picked) return { error: picked.error.replace("your child wants", "you want") }; // Shows any subject problem, worded for the person themselves.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: studentId, error } = await supabase.rpc("add_me_as_learner", { // Asks the database to add the student profile:
    p_date_of_birth: parsed.data.date_of_birth, // date of birth,
    p_state: parsed.data.state, // state,
    p_year_level: parsed.data.year_level, // year level,
    p_school: parsed.data.school, // school,
    p_subjects: picked, // subjects,
    p_goals: parsed.data.goals || null, // and end goal (or none).
  }); // End of the request.
  if (error) { // It failed:
    console.error("Add me as learner failed:", error.code, error.message); // notes why in the server log,
    return { error: error.code === "22023" ? `${error.message}.` : "We couldn't add your student profile. Please try again." }; // shows the database's plain message if it gave one, otherwise a general one.
  } // End of the failure case.
  if (typeof studentId === "string") await saveStudyDetails(supabase, studentId, parsed.data.program, picked); // Saves degree and unit details once the profile exists.
  redirect("/dashboard/student"); // Goes to the new student dashboard.
} // End of addMeAsLearner.
