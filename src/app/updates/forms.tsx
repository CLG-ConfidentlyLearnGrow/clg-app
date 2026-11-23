// Summary: the forms on the End-of-day updates page (Carla, 22 Nov 2026):
// an admin's update for a day, and the owner's "mark as read" button.
//
"use client"; // Runs in the browser, so each form can show its result straight away.

import { markDayUpdatesRead, saveDayUpdate } from "@/app/actions/day-updates"; // The server actions.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, TextArea } from "@/components/ui"; // The input box and larger text box.

// The update form, filled in with an earlier update for that day if there is one.
export function DayUpdateForm({ day, min, max, did, wentWell, notWell }: { day: string; min: string; max: string; did?: string; wentWell?: string | null; notWell?: string | null }) { // Takes the day, the allowed dates, and any earlier answers.
  return ( // Shows:
    <ActionForm action={saveDayUpdate} submitLabel={did ? "Send corrected update" : "Send update"}>{/* the form: */}
      <Field label="Day" name="work_date" type="date" min={min} max={max} defaultValue={day} required />{/* the day, */}
      <TextArea label="What I did" name="did" rows={4} maxLength={3000} required defaultValue={did ?? ""} hint="One dot point per line." />{/* what they did, */}
      <TextArea label="What went well" name="went_well" rows={3} maxLength={2000} defaultValue={wentWell ?? ""} hint="One dot point per line." />{/* what went well, */}
      <TextArea label="What did not go well" name="not_well" rows={3} maxLength={2000} defaultValue={notWell ?? ""} hint="One dot point per line. Include anything you need help with." />{/* and what did not. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of DayUpdateForm.

// The owner's button to mark the updates shown as read.
export function MarkReadForm({ ids }: { ids: string[] }) { // Takes the updates' ids.
  return ( // Shows:
    <ActionForm action={markDayUpdatesRead} submitLabel="Mark these as read">{/* the form: */}
      {ids.map((id) => <input key={id} type="hidden" name="id" value={id} />)}{/* each update's id (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of MarkReadForm.
