"use client";

import { addChild } from "@/app/actions/family";
import { ActionForm } from "@/components/action-form";
import { StateSelect } from "@/components/state-select";
import { Field } from "@/components/ui";

export function AddChildForm() {
  return (
    <ActionForm action={addChild} submitLabel="Add child">
      <Field label="Child's full name" name="full_name" required maxLength={200} />
      <Field label="Date of birth" name="date_of_birth" type="date" required />
      <StateSelect label="State your child lives in" />
      <Field label="Year level (optional)" name="year_level" maxLength={40} />
      <Field label="School (optional)" name="school" maxLength={200} />
    </ActionForm>
  );
}
