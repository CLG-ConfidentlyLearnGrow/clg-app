// Summary: the forms on the Learnings page (Carla, 22 Nov 2026): writing or
// changing a learning, removing or suggesting one, and the approvers'
// adapt and decline forms.
//
"use client"; // Runs in the browser, so each form can show its result straight away.

import { adoptLearning, declineLearning, removeLearning, removeTeamLearning, saveLearning, saveTeamLearning, suggestLearning } from "@/app/actions/learnings"; // The server actions.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, TextArea } from "@/components/ui"; // The input box and larger text box.

// Which save each words form uses.
const SAVERS = { mine: saveLearning, adopt: adoptLearning, team: saveTeamLearning } as const; // own learning, adapt a suggestion, or change a team learning.

// The words form: a title and the learning.
export function LearningForm({ mode, id, title, body, submitLabel }: { mode: keyof typeof SAVERS; id?: string; title?: string; body?: string; submitLabel: string }) { // Takes which save, the learning (if any), its words, and the button words.
  return ( // Shows:
    <ActionForm action={SAVERS[mode]} submitLabel={submitLabel}>{/* the form: */}
      <input type="hidden" name="id" value={id ?? ""} />{/* which learning (hidden), */}
      <Field label="Short title" name="title" maxLength={200} required defaultValue={title ?? ""} />{/* the title, */}
      <TextArea label="What was learned" name="body" rows={3} maxLength={3000} required defaultValue={body ?? ""} hint="No students' or families' names." />{/* and the learning. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LearningForm.

// Which one-button action each simple form uses.
const BUTTONS = { remove: removeLearning, suggest: suggestLearning, removeTeam: removeTeamLearning } as const; // remove own, suggest own, remove a team learning.

// A one-button form for a learning.
export function LearningButton({ action, id, label }: { action: keyof typeof BUTTONS; id: string; label: string }) { // Takes which action, the learning and the button words.
  return ( // Shows:
    <ActionForm action={BUTTONS[action]} submitLabel={label}>{/* the form: */}
      <input type="hidden" name="id" value={id} />{/* which learning (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LearningButton.

// The approvers' decline form, with a kind note.
export function DeclineLearningForm({ id }: { id: string }) { // Takes the suggestion.
  return ( // Shows:
    <ActionForm action={declineLearning} submitLabel="Decline for now">{/* the form: */}
      <input type="hidden" name="id" value={id} />{/* which suggestion (hidden), */}
      <TextArea label="Note for them (optional)" name="note" rows={2} maxLength={1000} hint="For example: already in the handbook, or what would make it work for everyone." />{/* the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of DeclineLearningForm.
