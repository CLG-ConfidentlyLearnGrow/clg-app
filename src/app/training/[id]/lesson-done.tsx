// Summary: the "Done, save my place" button under each training lesson.
// It marks the lesson as done so the person can stop and carry on another
// time, and shows "Done" once it is saved (Carla, 18 Nov 2026).
//
"use client"; // Runs in the browser, so the button can show its reply straight away.

import { useActionState } from "react"; // Lets a form run a server action and remember its reply.
import { markLessonDone } from "@/app/actions/training"; // The server action that saves the lesson as done.
import { FormMessage } from "@/components/ui"; // The reply message.
import { initialFormState } from "@/lib/forms"; // The starting (empty) form reply.

// Shows "Done" for a finished lesson, or the button that marks it done.
export function LessonDone({ moduleId, lessonId, done }: { moduleId: string; lessonId: string; done: boolean }) { // Takes the module, the lesson, and whether it is already done.
  const [state, action, pending] = useActionState(markLessonDone, initialFormState); // The reply, the form's sender, and whether it is busy.
  if (done) return <p className="text-sm font-medium text-teal-800">✓ Done</p>; // Already done: says so.
  return ( // Otherwise shows:
    <form action={action} className="space-y-2 border-t border-zinc-100 pt-4">{/* a small form under the lesson: */}
      <input type="hidden" name="module_id" value={moduleId} />{/* the module's id (hidden), */}
      <input type="hidden" name="lesson_id" value={lessonId} />{/* the lesson's id (hidden), */}
      <FormMessage state={state} />{/* the reply, */}
      <button type="submit" disabled={pending} className="rounded-full border border-teal-700 px-4 py-1.5 text-sm font-medium text-teal-800 transition hover:bg-teal-50 disabled:opacity-50">{/* and the button: */}
        {pending ? "Saving…" : "Done, save my place"}{/* its words. */}
      </button>{/* End of the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of LessonDone.
