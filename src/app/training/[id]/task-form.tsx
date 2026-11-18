// Summary: the practice task form on a training module. The person writes
// their answer (for example a mock session summary) and sends it to CLG to
// check (Carla, 18 Nov 2026).
//
"use client"; // Runs in the browser, so the form can show its reply straight away.

import { useActionState } from "react"; // Lets a form run a server action and remember its reply.
import { submitTask } from "@/app/actions/training"; // The server action that sends the task.
import { Button, FormMessage, TextArea } from "@/components/ui"; // The button, the reply message and the large text box.
import { initialFormState } from "@/lib/forms"; // The starting (empty) form reply.

// Shows the box to write the task in, and the send button.
export function TaskForm({ moduleId, answer }: { moduleId: string; answer: string }) { // Takes the module and anything written before.
  const [state, action, pending] = useActionState(submitTask, initialFormState); // The reply, the form's sender, and whether it is busy.
  return ( // Shows:
    <form action={action} className="space-y-3">{/* the form: */}
      <input type="hidden" name="module_id" value={moduleId} />{/* the module's id (hidden), */}
      <TextArea label="Your answer" name="answer" rows={10} required minLength={20} maxLength={6000} defaultValue={answer} hint="Write it yourself, without AI tools." />{/* the answer box (with any earlier answer), */}
      <FormMessage state={state} />{/* the reply, */}
      <Button type="submit" disabled={pending}>{pending ? "Sending…" : "Send to CLG to check"}</Button>{/* and the send button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of TaskForm.
