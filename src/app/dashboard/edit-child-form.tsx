// Summary: the parent's form for changing a child's details.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { updateChild } from "@/app/actions/family"; // The server action that saves the changes.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { SubjectPicker, type ChosenSubject } from "@/components/subject-picker"; // Boxes to pick subjects, and the type of a chosen subject.
import { Field } from "@/components/ui"; // A labelled input box.
import { StateSelect } from "@/components/state-select"; // A list to pick the state.
import { YearLevelSelect } from "@/components/year-level-select"; // A list to pick the year level.
import { DOB_HINT } from "@/lib/students"; // The hint shown under date of birth.
import { GoalFields } from "./add-child-form"; // The goals, extra information and learning needs boxes.

// A child's details as the form needs them.
export type ChildDetails = {
  id: string; // their id,
  full_name: string; // full name,
  date_of_birth: string | null; // date of birth (if known),
  state: string | null; // state (if known),
  year_level: string | null; // year level (if known),
  school: string | null; // school (if known),
  goals: string | null; // goals (if given),
  extra_info: string | null; // extra information (if given),
  learning_needs: string | null; // learning needs (if given),
  program: string | null; // degree or course (if any).
}; // End of the shape.

// Shows the form filled in with the child's current details.
export function EditChildForm({ child, subjects }: { child: ChildDetails; subjects: ChosenSubject[] }) {
  return ( // Shows:
    <ActionForm action={updateChild} submitLabel="Save changes">{/* a form that saves the changes: */}
      <input type="hidden" name="student_id" value={child.id} />{/* the child's id (hidden), */}
      <Field label="Child's full name" name="full_name" required maxLength={200} defaultValue={child.full_name} />{/* their full name, */}
      {!child.date_of_birth && <Field label="Date of birth" name="date_of_birth" type="date" required hint={DOB_HINT} />}{/* date of birth, only if not set yet, */}
      {!child.state && <StateSelect label="State your child lives in" />}{/* state, only if not set yet, */}
      <YearLevelSelect label="Year level at school this year" defaultValue={child.year_level ?? ""} />{/* year level, */}
      <Field label="School, university or TAFE" name="school" required maxLength={200} defaultValue={child.school ?? ""} />{/* school, university or TAFE, */}
      <SubjectPicker chosen={subjects} program={child.program ?? ""} />{/* subjects, */}
      <GoalFields goals={child.goals ?? ""} extraInfo={child.extra_info ?? ""} learningNeeds={child.learning_needs ?? ""} />{/* goals, extra information and learning needs. */}
      {child.date_of_birth && child.state && ( // If date of birth and state are both set:
        <p className="text-xs text-zinc-500">To change the date of birth or state, please contact CLG.</p> // a note to contact CLG to change them.
      )}{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of EditChildForm.
