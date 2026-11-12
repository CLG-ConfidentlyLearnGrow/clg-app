// Summary: a ready-made form that sends to a server action, shows the
// action's error or success message, and has one submit button.
//
"use client"; // Marks this file as code that runs in the browser.

import { useActionState, type ReactNode } from "react"; // React's form helper, and the type for "anything that can be shown".
import { Button, FormMessage } from "@/components/ui"; // The main button and the message box.
import { initialFormState, type FormState } from "@/lib/forms"; // The empty starting reply, and the reply's shape.

type Action = (prev: FormState, formData: FormData) => Promise<FormState>; // The shape of a server action: it gets the last reply and the form's data, and gives back a new reply.

// A form wired to a server action, showing its error or success message.
export function ActionForm({
  action, // The server action to run.
  submitLabel, // The words on the button.
  children, // The form's fields.
}: { // The settings' types:
  action: Action; // action is a server action,
  submitLabel: string; // button words are text,
  children: ReactNode; // fields can be anything shown.
}) { // End of the settings.
  const [state, formAction, pending] = useActionState(action, initialFormState); // Runs the action and gives back its latest reply, the form's sender, and whether it's busy.
  return ( // Shows:
    <form action={formAction} className="space-y-4">{/* the form, sending to the action, with space between parts, */}
      <FormMessage state={state} />{/* the error or success message, */}
      {children}{/* the fields, */}
      <Button type="submit" disabled={pending}>{/* the submit button, switched off while busy, */}
        {pending ? "Please wait…" : submitLabel}{/* showing "Please wait…" while busy, otherwise its words. */}
      </Button>{/* End of the Button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of ActionForm.
