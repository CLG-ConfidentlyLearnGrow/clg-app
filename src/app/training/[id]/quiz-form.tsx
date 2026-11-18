// Summary: the quiz at the end of a training module. Each question has one
// right answer; all must be right (100%). People can try as often as they
// like, and are told which questions to look at again. Answers can be saved
// part way through and the quiz finished another time (Carla, 18 Nov 2026).
//
"use client"; // Runs in the browser, so the form can show the result straight away.

import { useActionState } from "react"; // Lets a form run a server action and remember its reply.
import { finishModule, saveQuizAnswers } from "@/app/actions/training"; // The server actions that mark the quiz, and save answers for later.
import { Button, FormMessage } from "@/components/ui"; // The button and the reply message.
import { initialFormState } from "@/lib/forms"; // The starting (empty) form reply.

// One question as the quiz shows it (no answer included).
export type QuizQuestion = { id: string; prompt: string; options: string[]; image_url?: string | null; image_alt?: string | null }; // its id, the question, the choices, and any picture (a link that works for one hour) with its description.

// Shows the quiz, or a "finish" button for a module with no quiz.
export function QuizForm({ moduleId, questions, done, saved }: { moduleId: string; questions: QuizQuestion[]; done: boolean; saved: number[] }) { // Takes the module, its questions, whether it's already done, and any answers saved earlier.
  const [state, action, pending] = useActionState(finishModule, initialFormState); // The reply, the form's sender, and whether it's busy.
  const [saveState, saveAction, saving] = useActionState(saveQuizAnswers, initialFormState); // The same for saving answers to finish later.
  return ( // Shows:
    <form action={action} className="space-y-6">{/* the form: */}
      <input type="hidden" name="module_id" value={moduleId} />{/* the module's id (hidden), */}
      <input type="hidden" name="question_count" value={questions.length} />{/* how many questions (hidden), */}
      {questions.map((q, i) => ( // each question:
        <fieldset key={q.id} className="space-y-2">{/* a group: */}
          <legend className="text-sm font-medium text-zinc-900">{i + 1}. {q.prompt}</legend>{/* the number and question, */}
          {q.image_url && ( // a question with a picture (for example a screenshot of the app):
            // eslint-disable-next-line @next/next/no-img-element -- a private link that works for one hour, so the image optimiser cannot cache it
            <img src={q.image_url} alt={q.image_alt ?? ""} className="max-h-96 w-full rounded-lg border border-zinc-200 object-contain" />
          )}{/* End of the picture. */}
          {q.options.map((o, j) => ( // each choice:
            <label key={j} className="flex items-start gap-2 rounded-lg border border-zinc-200 px-3 py-2 text-sm hover:bg-zinc-50">{/* a tappable row: */}
              <input type="radio" name={`q${i + 1}`} value={j + 1} required defaultChecked={saved[i] === j + 1} className="mt-0.5" />{/* a round button (counting choices from 1), ticked if it was saved earlier, */}
              <span>{o}</span>{/* and the choice's words. */}
            </label> // End of the row.
          ))}{/* End of the choices. */}
        </fieldset> // End of the group.
      ))}{/* End of the questions. */}
      <FormMessage state={state} />{/* the result: well done, or what to look at again, */}
      <FormMessage state={saveState} />{/* the reply after saving answers for later, */}
      <div className="flex flex-wrap items-center gap-3">{/* the buttons, side by side: */}
        <Button type="submit" disabled={pending || saving}>{/* the send button: */}
          {pending ? "Checking…" : questions.length ? (done ? "Check my answers again" : "Check my answers") : done ? "Mark as finished again" : "Mark as finished"}{/* its words. */}
        </Button>{/* End of the button. */}
        {questions.length > 0 && !done && ( // A quiz not yet passed:
          <button type="submit" formAction={saveAction} formNoValidate disabled={pending || saving} className="rounded-full border border-teal-700 px-5 py-2.5 text-sm font-medium text-teal-800 transition hover:bg-teal-50 disabled:opacity-50">{/* a second button that saves without checking (unanswered questions are allowed): */}
            {saving ? "Saving…" : "Save my answers and finish later"}{/* its words. */}
          </button> // End of the button.
        )}{/* End of the save button. */}
      </div>{/* End of the buttons. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of QuizForm.
