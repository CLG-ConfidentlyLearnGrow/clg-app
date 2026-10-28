"use client";

import { updateChild } from "@/app/actions/family";
import { ActionForm } from "@/components/action-form";
import { SubjectPicker, type ChosenSubject } from "@/components/subject-picker";
import { Field } from "@/components/ui";
import { StateSelect } from "@/components/state-select";
import { YearLevelSelect } from "@/components/year-level-select";
import { DOB_HINT } from "@/lib/students";
import { GoalFields } from "./add-child-form";

export type ChildDetails = {
  id: string;
  full_name: string;
  date_of_birth: string | null;
  state: string | null;
  year_level: string | null;
  school: string | null;
  goals: string | null;
  extra_info: string | null;
};

export function EditChildForm({ child, subjects }: { child: ChildDetails; subjects: ChosenSubject[] }) {
  return (
    <ActionForm action={updateChild} submitLabel="Save changes">
      <input type="hidden" name="student_id" value={child.id} />
      <Field label="Child's full name" name="full_name" required maxLength={200} defaultValue={child.full_name} />
      {!child.date_of_birth && <Field label="Date of birth" name="date_of_birth" type="date" required hint={DOB_HINT} />}
      {!child.state && <StateSelect label="State your child lives in" />}
      <YearLevelSelect label="Year level at school this year" defaultValue={child.year_level ?? ""} />
      <Field label="School" name="school" required maxLength={200} defaultValue={child.school ?? ""} />
      <SubjectPicker chosen={subjects} />
      <GoalFields goals={child.goals ?? ""} extraInfo={child.extra_info ?? ""} />
      {child.date_of_birth && child.state && (
        <p className="text-xs text-zinc-500">To change the date of birth or state, please contact CLG.</p>
      )}
    </ActionForm>
  );
}
