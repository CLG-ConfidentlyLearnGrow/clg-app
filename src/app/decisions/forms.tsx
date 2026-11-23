// Summary: the forms on the Decision steps page (Carla, 22 Nov 2026):
// moving a step (Carla), adding a note (Carla, or Operations for tutors),
// adding to your own decisions log, and changing the kinds of problem (Carla).
//
"use client"; // Runs in the browser, so each form can show its result straight away.

import { addDecisionLog, addDecisionNote, moveDecisionStep, saveDecisionKind } from "@/app/actions/decisions"; // The server actions.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // The input box, drop-down and larger text box.
import { stepLabel } from "@/lib/decision-steps"; // The step names.

// The five steps as choices in a drop-down.
function StepOptions() { // No inputs.
  return <>{[1, 2, 3, 4, 5].map((n) => <option key={n} value={n}>{stepLabel(n)}</option>)}</>; // One choice per step.
} // End of StepOptions.

// Carla moves a person's step for one kind of problem.
export function MoveStepForm({ person, kind, step }: { person: string; kind: string; step: number }) { // Takes the person, the kind and the current step.
  return ( // Shows:
    <ActionForm action={moveDecisionStep} submitLabel="Save step">{/* the form: */}
      <input type="hidden" name="person" value={person} />{/* who (hidden), */}
      <input type="hidden" name="kind" value={kind} />{/* which kind (hidden), */}
      <Select label="New step" name="step" defaultValue={String(step)}><StepOptions /></Select>{/* the step, */}
      <Field label="Short note (why it moved)" name="note" maxLength={1000} />{/* and the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of MoveStepForm.

// Carla, or Operations for tutors, adds a note to a record.
export function NoteForm({ person, kinds }: { person: string; kinds: { id: string; title: string }[] }) { // Takes the person and their kinds of problem.
  return ( // Shows:
    <ActionForm action={addDecisionNote} submitLabel="Add note">{/* the form: */}
      <input type="hidden" name="person" value={person} />{/* who (hidden), */}
      <Select label="About which kind of problem? (optional)" name="kind" defaultValue="">{/* the kind: */}
        <option value="">General</option>{/* none, */}
        {kinds.map((k) => <option key={k.id} value={k.id}>{k.title}</option>)}{/* or one of theirs. */}
      </Select>{/* End of the kind. */}
      <TextArea label="Note" name="body" rows={2} maxLength={2000} required hint="They can read notes on their own record." />{/* the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of NoteForm.

// A staff member adds to their own decisions log.
export function LogForm({ kinds }: { kinds: { id: string; title: string }[] }) { // Takes their kinds of problem.
  return ( // Shows:
    <ActionForm action={addDecisionLog} submitLabel="Record decision">{/* the form: */}
      <Select label="Kind of problem (optional)" name="kind" defaultValue="">{/* the kind: */}
        <option value="">Something else</option>{/* none, */}
        {kinds.map((k) => <option key={k.id} value={k.id}>{k.title}</option>)}{/* or one of theirs. */}
      </Select>{/* End of the kind. */}
      <TextArea label="The problem" name="problem" rows={2} maxLength={2000} required hint="One or two sentences, and who it affects. First names or initials only." />{/* the problem, */}
      <TextArea label="Options you considered" name="options" rows={2} maxLength={2000} required hint="At least three." />{/* the options, */}
      <TextArea label="The one you chose, and why" name="choice" rows={2} maxLength={2000} required />{/* the choice, */}
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="done" defaultChecked />It is done</label>{/* and whether it is done. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LogForm.

// Carla adds or changes a kind of problem.
export function KindForm({ kind }: { kind?: { id: string; audience: string; title: string; start_step: number; goal_step: number; goal_note: string | null; active: boolean } }) { // Takes the kind (blank for a new one).
  return ( // Shows:
    <ActionForm action={saveDecisionKind} submitLabel={kind ? "Save changes" : "Add kind of problem"}>{/* the form: */}
      <input type="hidden" name="id" value={kind?.id ?? ""} />{/* which kind (hidden), */}
      <Select label="For" name="audience" defaultValue={kind?.audience ?? "admin"}><option value="admin">Admin staff</option><option value="tutor">Tutors</option></Select>{/* who it is for, */}
      <Field label="Kind of problem" name="title" maxLength={300} required defaultValue={kind?.title ?? ""} />{/* the words, */}
      <div className="grid gap-4 sm:grid-cols-3">{/* side by side on wider screens: */}
        <Select label="Starts at" name="start" defaultValue={String(kind?.start_step ?? 1)}><StepOptions /></Select>{/* the starting step, */}
        <Select label="Goal" name="goal" defaultValue={String(kind?.goal_step ?? 3)}><StepOptions /></Select>{/* the goal step, */}
        <Field label="Goal note (optional)" name="goal_note" maxLength={200} defaultValue={kind?.goal_note ?? ""} hint="For example: later." />{/* extra words for the goal. */}
      </div>{/* End of the row. */}
      {kind && <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="active" defaultChecked={kind.active} />In use (untick to hide it, keeping past records)</label>}{/* whether it is in use (changes only). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of KindForm.
