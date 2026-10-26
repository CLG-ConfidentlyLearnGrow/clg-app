"use client";

import { addChild } from "@/app/actions/family";
import { ActionForm } from "@/components/action-form";
import { StateSelect } from "@/components/state-select";
import { Field } from "@/components/ui";
import { YearLevelSelect } from "@/components/year-level-select";

export function AddChildForm() {
  return (
    <ActionForm action={addChild} submitLabel="Add child">
      <Field label="Child's full name" name="full_name" required maxLength={200} />
      <Field label="Date of birth" name="date_of_birth" type="date" required />
      <StateSelect label="State your child lives in" />
      <YearLevelSelect label="Year level this year" />
      <Field
        label="School"
        name="school"
        required
        maxLength={200}
        hint='If your child is home-schooled, write "Home schooled".'
      />
    </ActionForm>
  );
}
