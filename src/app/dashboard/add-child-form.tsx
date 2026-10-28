"use client";

import { addChild } from "@/app/actions/family";
import { DOB_HINT } from "@/lib/students";
import { ActionForm } from "@/components/action-form";
import { StateSelect } from "@/components/state-select";
import { SubjectPicker } from "@/components/subject-picker";
import { Field, TextArea } from "@/components/ui";
import { YearLevelSelect } from "@/components/year-level-select";

export function AddChildForm() {
  return (
    <ActionForm action={addChild} submitLabel="Add child">
      <Field label="Child's full name" name="full_name" required maxLength={200} />
      <Field label="Date of birth" name="date_of_birth" type="date" required hint={DOB_HINT} />
      <StateSelect label="State your child lives in" />
      <YearLevelSelect label="Year level at school this year" />
      <Field
        label="School"
        name="school"
        required
        maxLength={200}
        hint='If your child is home-schooled, write "Home schooled".'
      />
      <SubjectPicker />
      <GoalFields />
    </ActionForm>
  );
}

// The end goal and anything else the family wants CLG to know.
export function GoalFields({
  goals = "",
  extraInfo = "",
  optional = false,
}: {
  goals?: string;
  extraInfo?: string;
  optional?: boolean;
}) {
  return (
    <>
      <TextArea
        label={optional ? "What would they like CLG's support to achieve? (optional)" : "What would you like CLG's support to achieve?"}
        name="goals"
        required={!optional}
        rows={3}
        maxLength={4000}
        defaultValue={goals}
        hint="For example: feel confident in maths before high school, or reach a B in Year 12 Chemistry."
      />
      <TextArea
        label="Anything else you'd like us to know? (optional)"
        name="extra_info"
        rows={3}
        maxLength={2000}
        defaultValue={extraInfo}
        hint="For example, interests, how your child learns best, or times that suit. Please don't include medical details here; CLG will ask privately if needed."
      />
    </>
  );
}
