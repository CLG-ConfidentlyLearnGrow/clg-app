// Summary: admin forms: invite staff, record checks, tutor work state, assign tutors, unlock accounts,
// holds, tutors leaving, erasing a student, keeping periods and sending a check back.
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { // The server actions for these forms:
  declineCheck, // send a check back,
  assignTutor, // assign a tutor,
  eraseStudent, // erase a student,
  inviteStaff, // invite staff,
  markTutorLeft, // mark a tutor as finished,
  placeHold, // place a hold,
  recordCheck, // record a check,
  setRetentionPeriod, // change a keeping period,
  setTutorWorkState, // set a tutor's work state,
  unlockAccount, // unlock an account.
} from "@/app/actions/admin"; // (end of the list)
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select } from "@/components/ui"; // The input box and drop-down list.
import { CHECK_KINDS, CHECK_NAMES, STATES, STATE_NAMES } from "@/lib/checks"; // Check kinds and names, and states and their names.
import { useState } from "react"; // Lets the invite form remember the chosen role.

type Option = { id: string; name: string }; // An item in a drop-down: its id and name.

// A drop-down of tutors.
function TutorSelect({ tutors }: { tutors: Option[] }) {
  return ( // Shows:
    <Select label="Tutor" name="tutor_id" required defaultValue="">{/* a drop-down (must be chosen): */}
      <option value="" disabled>{/* a blank first option that can't be picked: */}
        Choose…{/* "Choose…", */}
      </option>{/* (end of the option) */}
      {tutors.map((t) => ( // for each tutor:
        <option key={t.id} value={t.id}>{/* an option: */}
          {t.name}{/* their name. */}
        </option> // (end of the option)
      ))}{/* End of the loop. */}
    </Select> // End of the drop-down.
  ); // End of what's shown.
} // End of TutorSelect.

// The form for inviting a tutor or admin.
export function InviteForm({ canInviteAdmins }: { canInviteAdmins: boolean }) {
  // The admin level only applies to admins, so it is only shown when Admin is chosen.
  const [role, setRole] = useState("tutor"); // The chosen role (tutor to start).
  return ( // Shows:
    <ActionForm action={inviteStaff} submitLabel="Add">{/* a form that sends the invitation: */}
      <p className="text-sm text-zinc-600">{/* a grey note: */}
        New people get an invitation link for this role. When they join through it, they have the role straight
        away, with no approval needed. The link only works for that email, once, for 7 days. If the email already
        has a CLG account (for example a parent, or you), the role is added to that account straight away.{/* how invitations work. */}
      </p>{/* End of the note. */}
      <Field label="Email" name="email" type="email" required />{/* The email box, */}
      <Select label="Role" name="role" value={role} onChange={(e) => setRole(e.target.value)}>{/* a drop-down of roles, remembering the choice: */}
        <option value="tutor">Tutor</option>{/* tutor, */}
        {canInviteAdmins && <option value="admin">Admin</option>}{/* admin, only if this person may invite admins. */}
      </Select>{/* End of the drop-down. */}
      {canInviteAdmins && role === "admin" && ( // If inviting an admin:
        <Select label="Admin level" name="level" defaultValue="operations">{/* a drop-down of admin levels: */}
          <option value="operations">Operations: day-to-day running</option>{/* operations, */}
          <option value="support">Support: families, bookings and login links</option>{/* support, */}
          <option value="finance">Finance: invoices, payments and pay</option>{/* finance. */}
        </Select> // End of the drop-down.
      )}{/* End of that part. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of InviteForm.

// The form for recording a tutor's check.
export function CheckForm({ tutors }: { tutors: Option[] }) {
  return ( // Shows:
    <ActionForm action={recordCheck} submitLabel="Save check">{/* a form that saves the check: */}
      <TutorSelect tutors={tutors} />{/* the tutor, */}
      <Select label="Check" name="kind" defaultValue="wwcc_sa">{/* a drop-down of check kinds: */}
        {CHECK_KINDS.map((k) => ( // for each kind:
          <option key={k} value={k}>{/* an option: */}
            {CHECK_NAMES[k]}{/* its name. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <Field label="Card, registration or certificate number (not needed for RRHAN-EC)" name="reference" maxLength={100} />{/* The card or certificate number, */}
      <Field // the date done:
        label="Completed or issued on" // its label,
        name="completed_on" // its field name,
        type="date" // a date,
        hint="Required for a police check: it counts for 5 years from this date." // and a hint about police checks.
      />{/* (end of the box) */}
      <Field // The expiry date:
        label="Expires on" // its label,
        name="expires_on" // its field name,
        type="date" // a date,
        hint="Leave blank for a police check. The app works it out." // and a hint.
      />{/* (end of the box) */}
      <p className="text-xs text-zinc-500">{/* A small grey note: */}
        Only save a check after confirming it on the official screening or training record.{/* to confirm it on the official record first. */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of CheckForm.

// The form for setting the state a tutor works from.
export function WorkStateForm({ tutors }: { tutors: Option[] }) {
  return ( // Shows:
    <ActionForm action={setTutorWorkState} submitLabel="Save">{/* a form that saves it: */}
      <TutorSelect tutors={tutors} />{/* the tutor, */}
      <Select label="State the tutor works from" name="work_state" defaultValue="">{/* a drop-down of states: */}
        <option value="">Not set</option>{/* not set, */}
        {STATES.map((s) => ( // for each state:
          <option key={s} value={s}>{/* an option: */}
            {STATE_NAMES[s]}{/* its name. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <p className="text-xs text-zinc-500">The tutor will also need that state&apos;s check.</p>{/* A note that they'll need that state's check. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of WorkStateForm.

// Only subjects the tutor teaches at this student's year level are offered.
export function AssignForm({
  studentId, // the student,
  tutors, // and the tutors with the subjects they can teach this student.
}: { // (their types:)
  studentId: string; // an id,
  tutors: { id: string; name: string; subjects: string[] }[]; // a list of tutors with subjects.
}) { // (end of the settings)
  return ( // Shows:
    <ActionForm action={assignTutor} submitLabel="Assign tutor">{/* a form that assigns the tutor: */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <Select label="Tutor and subject" name="pick" required defaultValue="">{/* a drop-down of tutor and subject: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose…{/* "Choose…", */}
        </option>{/* (end of the option) */}
        {tutors.map((t) => ( // for each tutor:
          <optgroup key={t.id} label={t.name}>{/* a group named after them: */}
            {t.subjects.map((s) => ( // for each subject:
              <option key={s} value={`${t.id}|${s}`}>{/* an option, sent as "tutor|subject": */}
                {t.name}: {s}{/* e.g. "Sam: Maths". */}
              </option> // (end of the option)
            ))}{/* End of the subjects loop. */}
          </optgroup> // End of the group.
        ))}{/* End of the tutors loop. */}
      </Select>{/* End of the drop-down. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AssignForm.

// The form for unlocking an account.
export function UnlockForm() {
  return ( // Shows:
    <ActionForm action={unlockAccount} submitLabel="Unlock">{/* a form that unlocks it: */}
      <Field label="Email of locked account" name="email" type="email" required />{/* the account's email. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of UnlockForm.

// The form for placing a hold on records due to be deleted.
export function HoldForm({ due }: { due: { value: string; label: string }[] }) {
  return ( // Shows:
    <ActionForm action={placeHold} submitLabel="Place hold">{/* a form that places the hold: */}
      <Select label="Keep these records" name="target" required defaultValue="">{/* a drop-down of records: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose…{/* "Choose…", */}
        </option>{/* (end of the option) */}
        {due.map((d) => ( // for each record:
          <option key={d.value} value={d.value}>{/* an option: */}
            {d.label}{/* its name. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <Field // The reason box:
        label="Reason" // its label,
        name="reason" // its field name,
        required // that must be filled in,
        maxLength={300} // up to 300 characters,
        hint="Keep it general, such as 'open complaint'. Concern details belong in the child safety record." // and a hint to keep it general.
      />{/* (end of the box) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of HoldForm.

// The form for marking a tutor as finished.
export function TutorLeftForm({ tutors }: { tutors: Option[] }) {
  return ( // Shows:
    <ActionForm action={markTutorLeft} submitLabel="Mark as finished">{/* a form that saves it: */}
      <TutorSelect tutors={tutors} />{/* the tutor, */}
      <Field label="Last day with CLG" name="ended_on" type="date" required />{/* their last day, */}
      <p className="text-xs text-zinc-500">{/* a small grey note: */}
        They can no longer be assigned students. Their records are deleted 7 years after this date.{/* what this means. */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of TutorLeftForm.

// The form for deleting a student's records straight away.
export function EraseStudentForm({ students }: { students: Option[] }) {
  return ( // Shows:
    <ActionForm action={eraseStudent} submitLabel="Delete permanently">{/* a form that deletes them: */}
      <Select label="Student" name="student_id" required defaultValue="">{/* a drop-down of students: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose…{/* "Choose…", */}
        </option>{/* (end of the option) */}
        {students.map((s) => ( // for each student:
          <option key={s.id} value={s.id}>{/* an option: */}
            {s.name}{/* their name. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <Field label="Type the student's full name to confirm" name="confirm_name" required autoComplete="off" />{/* Their full name typed to confirm, */}
      <p className="text-xs text-red-700">{/* a small red warning: */}
        This deletes the student, their learning needs, links and enrolments straight away. It cannot be undone.{/* what's deleted, and that it can't be undone. */}
      </p>{/* End of the warning. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of EraseStudentForm.

// The form for changing how long a kind of record is kept.
export function RetentionPeriodForm({ rules }: { rules: { kind: string; label: string }[] }) {
  return ( // Shows:
    <ActionForm action={setRetentionPeriod} submitLabel="Save period">{/* a form that saves the period: */}
      <Select label="Records" name="kind" defaultValue={rules[0]?.kind}>{/* a drop-down of kinds of record: */}
        {rules.map((r) => ( // for each kind:
          <option key={r.kind} value={r.kind}>{/* an option: */}
            {r.label}{/* its name. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <Field label="Keep for (months)" name="months" type="number" min={1} max={600} required />{/* The number of months, */}
      <p className="text-xs text-zinc-500">Check with your lawyer before shortening any period.</p>{/* and a note to check with a lawyer first. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of RetentionPeriodForm.

// The form for sending a tutor's check back with a reason.
export function DeclineCheckForm({ checkId }: { checkId: string }) {
  return ( // Shows:
    <ActionForm action={declineCheck} submitLabel="Send back">{/* a form that sends it back: */}
      <input type="hidden" name="check_id" value={checkId} />{/* which check (hidden), */}
      <Field // the reason box:
        label="Reason the tutor will see" // its label,
        name="reason" // its field name,
        required // that must be filled in,
        minLength={3} // at least 3 characters,
        maxLength={300} // up to 300,
        hint="For example: the number doesn't match the official record." // and an example.
      />{/* (end of the box) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of DeclineCheckForm.
