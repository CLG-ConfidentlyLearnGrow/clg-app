"use client";

import { sendNewLink } from "@/app/actions/family-setup";
import { ActionForm } from "@/components/action-form";
import { Field } from "@/components/ui";

// An admin sends a family a new login link when the first one ran out.
export function NewLinkForm() {
  return (
    <ActionForm action={sendNewLink} submitLabel="Send a new link">
      <Field
        label="Family's or student's email"
        name="email"
        type="email"
        required
        hint="For accounts that haven't signed in yet. The old link stops working."
      />
    </ActionForm>
  );
}
