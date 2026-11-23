// Summary: the forms on the Meetings page (Carla, 22 Nov 2026): the request
// form for staff, accepting an offered time or cancelling, and Carla's forms
// to confirm a time, offer another, answer without a meeting, or mark a
// meeting as held.
//
"use client"; // Runs in the browser, so each form can show its result straight away.

import { acceptMeetingTime, answerMeetingRequest, cancelMeetingRequest, confirmMeeting, markMeetingHeld, sendMeetingRequest } from "@/app/actions/meetings"; // The server actions.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // The input box, drop-down and larger text box.

// The request form: About, Context, Goal, urgency, length, how, and 2 or 3 times.
export function MeetingRequestForm({ min }: { min: string }) { // Takes the earliest time allowed (now, Adelaide time).
  return ( // Shows:
    <ActionForm action={sendMeetingRequest} submitLabel="Send to Carla">{/* the form: */}
      <Field label="About" name="about" maxLength={200} required hint="A few words, for example: planning for a new student." />{/* what it is about, */}
      <TextArea label="Context" name="context" rows={3} maxLength={3000} required hint="What Carla needs to know first. Use first names or initials only for students." />{/* the background, */}
      <TextArea label="Goal" name="goal" rows={2} maxLength={1000} required hint="What you want to come away with." />{/* the goal, */}
      <div className="grid gap-4 sm:grid-cols-3">{/* three choices side by side on wider screens: */}
        <Select label="How urgent?" name="urgency" defaultValue="this_week" required>{/* urgency: */}
          <option value="urgent">Urgent (today or tomorrow)</option>{/* urgent, */}
          <option value="this_week">This week</option>{/* this week, */}
          <option value="no_rush">No rush</option>{/* or no rush. */}
        </Select>{/* End of urgency. */}
        <Select label="How long?" name="length" defaultValue="30" required>{/* length: */}
          <option value="15">15 minutes</option>{/* 15, */}
          <option value="30">30 minutes</option>{/* 30, */}
          <option value="45">45 minutes</option>{/* 45, */}
          <option value="60">1 hour</option>{/* or 60 minutes. */}
        </Select>{/* End of length. */}
        <Select label="How to meet?" name="how" defaultValue="online" required>{/* how: */}
          <option value="online">Online (Teams)</option>{/* online, */}
          <option value="phone">Phone</option>{/* phone, */}
          <option value="in_person">In person</option>{/* or in person. */}
        </Select>{/* End of how. */}
      </div>{/* End of the choices. */}
      <p className="text-sm text-zinc-600">Suggest 2 or 3 times you can do (Adelaide time). If you are not sure whether it is urgent, choose urgent.</p>{/* the times note, */}
      <div className="grid gap-4 sm:grid-cols-3">{/* three times side by side on wider screens: */}
        <Field label="Time 1" name="time1" type="datetime-local" min={min} required />{/* first time, */}
        <Field label="Time 2" name="time2" type="datetime-local" min={min} required />{/* second time, */}
        <Field label="Time 3 (optional)" name="time3" type="datetime-local" min={min} />{/* third time. */}
      </div>{/* End of the times. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of MeetingRequestForm.

// Accepts the different time Carla offered.
export function AcceptTimeForm({ id }: { id: string }) { // Takes the request.
  return ( // Shows:
    <ActionForm action={acceptMeetingTime} submitLabel="Accept this time">{/* the form: */}
      <input type="hidden" name="id" value={id} />{/* which request (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AcceptTimeForm.

// Cancels a request, with an optional note.
export function CancelMeetingForm({ id }: { id: string }) { // Takes the request.
  return ( // Shows:
    <ActionForm action={cancelMeetingRequest} submitLabel="Cancel this meeting">{/* the form: */}
      <input type="hidden" name="id" value={id} />{/* which request (hidden), */}
      <Field label="Reason (optional)" name="note" maxLength={1000} />{/* and an optional reason. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of CancelMeetingForm.

// Carla confirms one of the suggested times, or offers a different one.
export function ConfirmMeetingForm({ id, options, min }: { id: string; options: { value: string; label: string }[]; min: string }) { // Takes the request, its suggested times, and the earliest time allowed.
  return ( // Shows:
    <ActionForm action={confirmMeeting} submitLabel="Confirm or offer this time">{/* the form: */}
      <input type="hidden" name="id" value={id} />{/* which request (hidden), */}
      <fieldset className="space-y-1">{/* the choices: */}
        <legend className="text-sm font-medium text-zinc-800">Choose a time</legend>{/* the heading, */}
        {options.map((o, i) => ( // Each suggested time:
          <label key={o.value} className="flex items-center gap-2 text-sm"><input type="radio" name="pick" value={o.value} defaultChecked={i === 0} />{o.label}</label> // a round choice with the time in words,
        ))}{/* End of the suggested times. */}
        <label className="flex items-center gap-2 text-sm"><input type="radio" name="pick" value="other" />A different time (they will be asked to accept it)</label>{/* or a different time. */}
      </fieldset>{/* End of the choices. */}
      <Field label="Different time (Adelaide time)" name="other" type="datetime-local" min={min} />{/* the different time, */}
      <TextArea label="Note (optional)" name="note" rows={2} maxLength={2000} hint="For example: what to bring, or the Teams link." />{/* and an optional note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of ConfirmMeetingForm.

// Carla answers without a meeting.
export function AnswerMeetingForm({ id }: { id: string }) { // Takes the request.
  return ( // Shows:
    <ActionForm action={answerMeetingRequest} submitLabel="Answer without a meeting">{/* the form: */}
      <input type="hidden" name="id" value={id} />{/* which request (hidden), */}
      <TextArea label="Your answer" name="note" rows={3} maxLength={2000} required hint="When a short answer is enough, so no meeting is needed." />{/* the answer. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AnswerMeetingForm.

// Carla marks a confirmed meeting as held.
export function HeldMeetingForm({ id }: { id: string }) { // Takes the request.
  return ( // Shows:
    <ActionForm action={markMeetingHeld} submitLabel="Mark as held">{/* the form: */}
      <input type="hidden" name="id" value={id} />{/* which request (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of HeldMeetingForm.
