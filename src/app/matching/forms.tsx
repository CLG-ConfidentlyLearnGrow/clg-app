// Summary: small forms for the Matching page (Carla, 16 Nov 2026): the
// "Ask the family" button beside a missing detail, and the "waiting since"
// date for students who were on CLG's waitlist before the app.
//
"use client"; // Marks this file as code that runs in the browser.

import { useActionState } from "react"; // React's form helper.
import { askFamily, setWaitingSince } from "@/app/actions/scheduling-extra"; // The two server actions.
import { ActionForm } from "@/components/action-form"; // A shared form with a save button and messages.
import { Field } from "@/components/ui"; // A labelled field.
import { initialFormState } from "@/lib/forms"; // The empty starting reply.

// The "Ask the family" button: a small inline form that sends the ask and
// shows the reply next to it.
export function AskFamilyButton({ studentId, item }: { studentId: string; item: string }) { // Takes the student and the missing item.
  const [state, formAction, pending] = useActionState(askFamily, initialFormState); // Runs the action and keeps its reply and busy state.
  return ( // What is shown:
    <form action={formAction} className="inline-flex flex-wrap items-center gap-2">{/* an inline form: */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <input type="hidden" name="item" value={item} />{/* the missing item (hidden), */}
      {state.message ? ( // once sent:
        <span className="text-xs text-teal-800">{state.message}</span> // the success message,
      ) : ( // before sending:
        <button // the button:
          type="submit" // sends the form,
          disabled={pending} // switched off while sending,
          className="rounded-full border border-zinc-300 bg-white px-3 py-0.5 text-xs hover:bg-zinc-50 disabled:opacity-60" // small and outlined.
        >{/* (end of the button's settings) */}
          {pending ? "Asking…" : "Ask the family"}{/* its words. */}
        </button> // End of the button.
      )}{/* (end of the sent check) */}
      {state.error && <span className="text-xs text-red-700">{state.error}</span>}{/* any error, in red. */}
    </form> // End of the form.
  ); // End of what is shown.
} // End of AskFamilyButton.

// The "waiting since" date: when the student first joined CLG's waitlist, if
// that was before they were added to the app. Empty clears it.
export function WaitingSinceForm({ studentId, subject, current }: { studentId: string; subject: string; current: string }) { // Takes the student, subject and current date (or empty).
  return ( // What is shown:
    <ActionForm action={setWaitingSince} submitLabel="Save date">{/* the form, saving with setWaitingSince: */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <input type="hidden" name="subject" value={subject} />{/* the subject (hidden), */}
      <Field label="Waiting since (leave empty to use the date they were added)" name="since" type="date" defaultValue={current} />{/* the date. */}
    </ActionForm> // End of the form.
  ); // End of what is shown.
} // End of WaitingSinceForm.
