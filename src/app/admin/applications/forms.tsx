// Summary: the admin forms for one tutor application: the screening record
// (status, interview, referee checks, Working with Children Check verified,
// notes), declining with a reason, and approving (which sends the invite).
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { approveTutorApplication, declineTutorApplication, saveTutorApplication } from "@/app/actions/tutor-applications"; // The server actions for applications.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // Form boxes and lists.
import { DECLINE_REASONS, DECLINE_REASON_NAMES } from "@/lib/tutor-applications"; // The reasons for declining and their words.

// The parts of an application the screening form needs.
export type ScreeningRecord = {
  id: string; // the application's id,
  status: string; // where it's up to,
  interview_on: string | null; // interview date,
  interview_notes: string | null; // interview notes,
  referee_1_checked_on: string | null; // referee 1 checked,
  referee_2_checked_on: string | null; // referee 2 checked,
  referee_notes: string | null; // referee notes,
  wwcc_verified_on: string | null; // check verified,
  admin_notes: string | null; // other notes.
}; // End of the shape.

// The screening record form.
export function ScreeningForm({ app }: { app: ScreeningRecord }) {
  const decided = app.status === "approved" || app.status === "declined"; // Whether it's already been decided (the status can't change then).
  return ( // Shows:
    <ActionForm action={saveTutorApplication} submitLabel="Save screening record">{/* a form that saves the record: */}
      <input type="hidden" name="id" value={app.id} />{/* the application's id, hidden, */}
      {decided ? ( // Already decided:
        <input type="hidden" name="status" value="shortlisted" /> // (the database keeps the decided status; this only fills the box)
      ) : ( // Still open:
        <Select label="Status" name="status" defaultValue={app.status === "new" ? "new" : app.status}>{/* the status list: */}
          <option value="new">New</option>{/* new, */}
          <option value="shortlisted">Shortlisted (interview and referee checks)</option>{/* shortlisted, */}
          <option value="withdrawn">Withdrawn (they pulled out or stopped replying)</option>{/* withdrawn. */}
        </Select> // End of the list.
      )}{/* End of the status. */}
      <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label="Interview date" name="interview_on" type="date" defaultValue={app.interview_on ?? ""} />{/* interview date, */}
        <Field label="Working with Children Check verified on" name="wwcc_verified_on" type="date" defaultValue={app.wwcc_verified_on ?? ""} hint="Checked with the state's screening unit (in SA, the DHS Screening portal)." />{/* check verified, */}
      </div>{/* End of the columns. */}
      <TextArea label="Interview notes" name="interview_notes" rows={4} maxLength={4000} defaultValue={app.interview_notes ?? ""} hint="Their answers to the child-safe questions, and how they explained a topic." />{/* interview notes, */}
      <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label="Referee 1 checked on" name="referee_1_checked_on" type="date" defaultValue={app.referee_1_checked_on ?? ""} />{/* referee 1, */}
        <Field label="Referee 2 checked on" name="referee_2_checked_on" type="date" defaultValue={app.referee_2_checked_on ?? ""} />{/* referee 2. */}
      </div>{/* End of the columns. */}
      <TextArea label="What the referees said" name="referee_notes" rows={4} maxLength={4000} defaultValue={app.referee_notes ?? ""} hint="Who you spoke to, when, and their answers, including the direct question about working with children." />{/* referee notes, */}
      <TextArea label="Other private notes" name="admin_notes" maxLength={4000} defaultValue={app.admin_notes ?? ""} />{/* other notes. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of ScreeningForm.

// The decline form: a reason, an optional note, and whether to email them.
export function DeclineForm({ id }: { id: string }) {
  return ( // Shows:
    <ActionForm action={declineTutorApplication} submitLabel="Decline">{/* a form that declines it: */}
      <input type="hidden" name="id" value={id} />{/* the application's id, hidden, */}
      <Select label="Reason (only admins see this)" name="reason" required defaultValue="">{/* the reason list: */}
        <option value="" disabled>Choose a reason</option>{/* a prompt, */}
        {DECLINE_REASONS.map((r) => <option key={r} value={r}>{DECLINE_REASON_NAMES[r]}</option>)}{/* and each reason. */}
      </Select>{/* End of the list. */}
      <TextArea label="Note (optional, private)" name="note" maxLength={1000} />{/* a note, */}
      <label className="flex items-start gap-2 text-sm">{/* the email choice: */}
        <input type="checkbox" name="send_email" defaultChecked className="mt-1" />{/* a tick box (ticked to start), */}
        <span>Email them a polite &ldquo;not this time&rdquo; (the reason isn&apos;t included).</span>{/* and its words. */}
      </label>{/* End of the line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of DeclineForm.

// The approve button (also used to send the invite again).
export function ApproveForm({ id, again }: { id: string; again: boolean }) {
  return ( // Shows:
    <ActionForm action={approveTutorApplication} submitLabel={again ? "Send invite again" : "Approve and send invite"}>{/* a form that approves it: */}
      <input type="hidden" name="id" value={id} />{/* the application's id, hidden, */}
      <p className="text-sm text-zinc-600">{/* a note: */}
        {again // Already approved:
          ? "Sends a fresh tutor invite link to their email. The old link stops working." // says a new link goes,
          : "Needs the interview and both referee checks recorded first. They'll get the usual tutor invite link. Once they join, they add their checks, which you confirm before they're matched with students."}{/* otherwise what's needed and what happens. */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of ApproveForm.
