// Summary: the parent's form for giving a child aged 16 or over their own login.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { giveMyChildLogin } from "@/app/actions/family-setup"; // The server action that sends the login link.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field } from "@/components/ui"; // A labelled input box.

// A parent gives their child (16 or over) their own login.
export function OwnLoginForm({ studentId, name }: { studentId: string; name: string }) {
  return ( // Shows:
    <ActionForm action={giveMyChildLogin} submitLabel="Send login link">{/* a form that sends the login link: */}
      <input type="hidden" name="student_id" value={studentId} />{/* the child's id (hidden), */}
      <Field // an email box:
        label={`${name}'s own email`} // labelled with the child's name,
        name="email" // its field name,
        type="email" // an email address,
        required // that must be filled in,
        hint={`${name} gets a link to choose a password and sees their own sessions and progress. You can still see everything. Use an email no one uses for CLG yet.`} // and a hint about what happens next.
      />{/* (end of the box) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of OwnLoginForm.
