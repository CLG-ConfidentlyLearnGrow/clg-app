"use client";

import { addMeAsLearner } from "@/app/actions/learner";
import { ActionForm } from "@/components/action-form";
import { StateSelect } from "@/components/state-select";
import { SubjectPicker } from "@/components/subject-picker";
import { Field, TextArea } from "@/components/ui";
import { YearLevelSelect } from "@/components/year-level-select";
import { DOB_HINT } from "@/lib/students";

export function LearnerForm() {
  return (
    <ActionForm action={addMeAsLearner} submitLabel="Add my student profile">
      <Field label="Your date of birth" name="date_of_birth" type="date" required hint={DOB_HINT} />
      <StateSelect label="State you live in" />
      <YearLevelSelect label="Year level or stage of study" />
      <Field label="School, university or TAFE" name="school" required maxLength={200} />
      <SubjectPicker />
      <TextArea
        label="What would you like CLG's support to achieve? (optional)"
        name="goals"
        rows={3}
        maxLength={4000}
      />
    </ActionForm>
  );
}
