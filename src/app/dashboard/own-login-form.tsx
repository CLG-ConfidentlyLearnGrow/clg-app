"use client";

import { giveMyChildLogin } from "@/app/actions/family-setup";
import { ActionForm } from "@/components/action-form";
import { Field } from "@/components/ui";

// A parent gives their child (16 or over) their own login.
export function OwnLoginForm({ studentId, name }: { studentId: string; name: string }) {
  return (
    <ActionForm action={giveMyChildLogin} submitLabel="Send login link">
      <input type="hidden" name="student_id" value={studentId} />
      <Field
        label={`${name}'s own email`}
        name="email"
        type="email"
        required
        hint={`${name} gets a link to choose a password and sees their own sessions and progress. You can still see everything. Use an email no one uses for CLG yet.`}
      />
    </ActionForm>
  );
}
