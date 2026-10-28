"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import { readSubjects } from "@/lib/child-form";
import { STATES } from "@/lib/checks";
import { YEAR_LEVELS } from "@/lib/students";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// "Become a learner too": someone already signed in (a tutor, admin or
// parent) adds a student profile to their own account. The database checks
// they are 16 or over. See docs/features/become-a-learner.md.
const learnerSchema = z.object({
  date_of_birth: z.iso.date("Enter your date of birth."),
  state: z.enum(STATES, "Choose the state you live in."),
  year_level: z.enum(YEAR_LEVELS, "Choose your year level or stage of study."),
  school: z.string().trim().min(1, "Enter your school, university or TAFE.").max(200),
  goals: z.string().trim().max(4000, "Please keep the end goal under 4,000 characters.").optional(),
});

export async function addMeAsLearner(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  if (viewer.roles.includes("student")) redirect("/dashboard/student");
  const parsed = learnerSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const picked = readSubjects(formData);
  if ("error" in picked) return { error: picked.error.replace("your child wants", "you want") };

  const supabase = await createClient();
  const { error } = await supabase.rpc("add_me_as_learner", {
    p_date_of_birth: parsed.data.date_of_birth,
    p_state: parsed.data.state,
    p_year_level: parsed.data.year_level,
    p_school: parsed.data.school,
    p_subjects: picked,
    p_goals: parsed.data.goals || null,
  });
  if (error) {
    console.error("Add me as learner failed:", error.code, error.message);
    return { error: error.code === "22023" ? `${error.message}.` : "We couldn't add your student profile. Please try again." };
  }
  redirect("/dashboard/student");
}
