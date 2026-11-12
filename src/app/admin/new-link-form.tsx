// Summary: the admin form for sending a family a new login link.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { sendNewLink } from "@/app/actions/family-setup"; // The server action that sends the new link.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field } from "@/components/ui"; // A labelled input box.

// An admin sends a family a new login link when the first one ran out.
export function NewLinkForm() {
  return ( // Shows:
    <ActionForm action={sendNewLink} submitLabel="Send a new link">{/* a form that sends a new link: */}
      <Field // an email box:
        label="Family's or student's email" // its label,
        name="email" // its field name,
        type="email" // an email address,
        required // that must be filled in,
        hint="For accounts that haven't signed in yet. The old link stops working." // and a hint about when to use it.
      />{/* (end of the box) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of NewLinkForm.
