// Summary: the quiz at the end of a training module. Each question has one
// right answer; all must be right (100%). People can try as often as they
// like, and are told which questions to look at again.
//
"use client"; // Runs in the browser, so the form can show the result straight away.

import { useActionState } from "react"; // Lets a form run a server action and remember its reply.
import { finishModule } from "@/app/actions/training"; // The server action that marks the quiz.
import { Button, FormMessage } from "@/components/ui"; // The button and the reply message.
import { initialFormState } from "@/lib/forms"; // The starting (empty) form reply.

// One question as the quiz shows it (no answer included).
export type QuizQuestion = { id: string; prompt: string; options: string[] }; // its id, the question and the choices.

// Shows the quiz, or a "finish" button for a module with no quiz.
export function QuizForm({ moduleId, questions, done }: { moduleId: string; questions: QuizQuestion[]; done: boolean }) { // Takes the module, its questions, and whether it's already done.
  const [state, action, pending] = useActionState(finishModule, initialFormState); // The reply, the form's sender, and whether it's busy.
  return ( // Shows:
    <form action={action} className="space-y-6">{/* the form: */}
      <input type="hidden" name="module_id" value={moduleId} />{/* the module's id (hidden), */}
      <input type="hidden" name="question_count" value={questions.length} />{/* how many questions (hidden), */}
      {questions.map((q, i) => ( // each question:
        <fieldset key={q.id} className="space-y-2">{/* a group: */}
          <legend className="text-sm font-medium text-zinc-900">{i + 1}. {q.prompt}</legend>{/* the number and question, */}
          {q.options.map((o, j) => ( // each choice:
            <label key={j} className="flex items-start gap-2 rounded-lg border border-zinc-200 px-3 py-2 text-sm hover:bg-zinc-50">{/* a tappable row: */}
              <input type="radio" name={`q${i + 1}`} value={j + 1} required className="mt-0.5" />{/* a round button (counting choices from 1), */}
              <span>{o}</span>{/* and the choice's words. */}
            </label> // End of the row.
          ))}{/* End of the choices. */}
        </fieldset> // End of the group.
      ))}{/* End of the questions. */}
      <FormMessage state={state} />{/* the result: well done, or what to look at again, */}
      <Button type="submit" disabled={pending}>{/* the send button: */}
        {pending ? "Checking…" : questions.length ? (done ? "Check my answers again" : "Check my answers") : done ? "Mark as finished again" : "Mark as finished"}{/* its words. */}
      </Button>{/* End of the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of QuizForm.
