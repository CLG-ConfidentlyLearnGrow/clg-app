// Summary: parents add a child, or change a child's details and subjects.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { childSchema, readSubjects } from "@/lib/child-form"; // The child form rules, and reading the chosen subjects.
import { giveParentalConsent } from "@/lib/consent"; // Records the parent's consent for a child.
import { saveStudyDetails } from "@/lib/study-details"; // Saves a university or TAFE student's degree and unit details.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// A parent adds their child.
export async function addChild(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("parent")) return { error: "Only parents can add a child." }; // Only parents can add a child.

  const parsed = childSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the child rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const subjects = readSubjects(formData); // Reads the chosen subjects.
  if ("error" in subjects) return subjects; // Shows any subject problem.

  if (formData.get("parental_consent") !== "on") { // The consent box wasn't ticked:
    return { error: "Please tick the box to confirm you're the parent or guardian and agree." }; // asks them to tick it.
  } // End of that check.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: studentId, error } = await supabase.rpc("add_my_child", { // Asks the database to add the child:
    p_full_name: parsed.data.full_name, // name,
    p_date_of_birth: parsed.data.date_of_birth, // date of birth,
    p_state: parsed.data.state, // state,
    p_year_level: parsed.data.year_level, // year level,
    p_school: parsed.data.school, // school,
    p_subjects: subjects, // subjects,
    p_goals: parsed.data.goals, // end goal,
    p_extra_info: parsed.data.extra_info || undefined, // and other information (if any).
  }); // End of the request.
  if (error) return { error: "We couldn't add your child. Please check the details and try again." }; // Failed: plain message.
  if (parsed.data.learning_needs && typeof studentId === "string") { // If learning needs were given:
    await supabase.from("students").update({ learning_needs: parsed.data.learning_needs }).eq("id", studentId); // saves them on the new child.
  } // End of learning needs.
  if (typeof studentId === "string") await saveStudyDetails(supabase, studentId, parsed.data.program, subjects); // Saves degree and unit details.
  // If this fails, the parent is asked again on their next visit.
  if (typeof studentId === "string") await giveParentalConsent([studentId]); // Records the parent's consent for this child.

  revalidatePath("/dashboard", "layout"); // Refreshes the dashboard and everything under it.
  return { message: `${parsed.data.full_name} has been added. CLG will confirm the details before a tutor is assigned.` }; // Tells the parent what happens next.
} // End of addChild.

// A parent changes a child's details. Date of birth and state can only be
// changed by CLG (the database enforces this), since they decide which
// child safety rules apply.
// The rules for the edit form:
const editSchema = z.object({
  student_id: z.uuid(), // which child,
  full_name: childSchema.shape.full_name, // name (same rule as adding),
  year_level: childSchema.shape.year_level, // year level,
  school: childSchema.shape.school, // school,
  goals: childSchema.shape.goals, // end goal,
  extra_info: childSchema.shape.extra_info, // other information,
  learning_needs: childSchema.shape.learning_needs, // learning needs,
  program: childSchema.shape.program, // degree or course.
  // Only sent when CLG set up the child without them; the family fills them
  // in once (the database refuses later changes).
  date_of_birth: childSchema.shape.date_of_birth.optional(), // date of birth (optional),
  state: childSchema.shape.state.optional(), // state (optional).
}); // End of the rules.

// A parent (or admin) saves changes to a child's details and subjects.
export async function updateChild(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("parent") && !viewer.roles.includes("admin")) { // Not a parent or admin:
    return { error: "Only a parent can change these details." }; // explains only a parent can.
  } // End of that check.
  const parsed = editSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const subjects = readSubjects(formData); // Reads the chosen subjects.
  if ("error" in subjects) return subjects; // Shows any subject problem.
  const v = parsed.data; // A short name for the checked values.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: updated, error } = await supabase // Saves the details:
    .from("students") // in the students table,
    .update({ // changing:
      full_name: v.full_name, // name,
      year_level: v.year_level, // year level,
      school: v.school, // school,
      goals: v.goals, // end goal,
      extra_info: v.extra_info || null, // other information (or none),
      learning_needs: v.learning_needs || null, // learning needs (or none),
      ...(v.date_of_birth ? { date_of_birth: v.date_of_birth } : {}), // date of birth, only if sent,
      ...(v.state ? { state: v.state } : {}), // state, only if sent.
    }) // End of the changes.
    .eq("id", v.student_id) // for this child,
    .select("id"); // and reports which row changed.
  if (error || !updated?.length) return { error: "We couldn't save the changes. Please try again." }; // Nothing saved: plain message.

  // Bring the subject list in line with what's ticked, and update levels.
  const { data: current } = await supabase // Reads the saved subjects:
    .from("student_subjects") // from the student subjects table,
    .select("id, subject, working_level") // id, name and level,
    .eq("student_id", v.student_id); // for this child.
  const wanted = new Map(subjects.map((s) => [s.subject.toLowerCase(), s])); // The ticked subjects, by lower-case name.
  const have = new Map((current ?? []).map((c) => [c.subject.toLowerCase(), c])); // The saved subjects, by lower-case name.
  const remove = (current ?? []).filter((c) => !wanted.has(c.subject.toLowerCase())).map((c) => c.id); // Saved subjects no longer ticked: to remove.
  const add = subjects.filter((s) => !have.has(s.subject.toLowerCase())); // Ticked subjects not saved yet: to add.
  const relevel = subjects.filter((s) => { // Subjects whose level changed:
    const c = have.get(s.subject.toLowerCase()); // finds the saved one,
    return c && c.working_level !== s.level; // and keeps it if its level differs.
  }); // End of the filter.
  const failed = { error: "Details saved, but we couldn't update the subjects. Please try again." }; // The message if any subject change fails.
  if (remove.length) { // Some to remove:
    const { error: e } = await supabase.from("student_subjects").delete().in("id", remove); // deletes them,
    if (e) return failed; // failed: stops with the message.
  } // End of removing.
  if (add.length) { // Some to add:
    const { error: e } = await supabase // adds them:
      .from("student_subjects") // to the student subjects table,
      .insert(add.map((s) => ({ student_id: v.student_id, subject: s.subject, working_level: s.level }))); // each with this child, its name and level.
    if (e) return failed; // failed: stops with the message.
  } // End of adding.
  for (const s of relevel) { // For each changed level:
    const { error: e } = await supabase // saves it:
      .from("student_subjects") // in the student subjects table,
      .update({ working_level: s.level }) // the new level,
      .eq("id", have.get(s.subject.toLowerCase())!.id); // for that saved subject.
    if (e) return failed; // failed: stops with the message.
  } // End of the levels loop.
  if (!(await saveStudyDetails(supabase, v.student_id, v.program, subjects))) return failed; // Saves degree and unit details; stops if that fails.

  revalidatePath("/dashboard", "layout"); // Refreshes the dashboard and everything under it.
  return { message: "Saved." }; // Tells the person it worked.
} // End of updateChild.
