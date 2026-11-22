// Summary: the admin forms for the Student Success Program (Carla, 22 Nov
// 2026), shown in Families > Change a student's details. What shows depends
// on where the student is up to: approve a place (which sends the $500
// deposit invoice) or decline a request; change the details of a place;
// withdraw a place still waiting for its deposit; or take a student out of
// the program. Also the small form for the number of places.
//
"use client"; // Runs in the browser, so each form can show its result straight away.

import { // The server actions:
  approveStudentSuccessPlace, // approve a place,
  declineStudentSuccessRequest, // decline a request,
  leaveStudentSuccessProgram, // take a student out,
  saveStudentSuccessDetails, // change a place's details,
  saveStudentSuccessPlaces, // change the number of places,
  withdrawStudentSuccessPlace, // withdraw a place before the deposit is paid.
} from "@/app/actions/student-success-program"; // (end of the actions)
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // The input box, drop-down list and larger text box.

// What the forms know about the student's place in the program.
export type SspRecord = { // A program record:
  status: string; // where they are up to (requested, approved, enrolled, declined, withdrawn or left),
  request_note: string | null; // the family's message when asking (if any),
  sessions_planned: number | null; // sessions planned (if known),
  book_until: string | null; // the book-till date (if known),
  deposit_paid_on: string | null; // when the deposit was paid (if it has been),
  note: string | null; // and CLG's own note.
}; // End of the type.

// The boxes for a place's details (used when approving and when changing).
function PlaceFields({ studentId, current }: { studentId: string; current: SspRecord | null }) { // Takes the student and their record.
  return ( // Shows:
    <>{/* (a group) */}
      <input type="hidden" name="student_id" value={studentId} />{/* which student (hidden), */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label="Sessions planned (optional)" name="sessions" type="number" min={1} max={200} defaultValue={current?.sessions_planned ?? ""} />{/* sessions planned, */}
        <Field label="Book sessions until (optional)" name="book_until" type="date" defaultValue={current?.book_until ?? ""} hint="Also saved as the student's booking length." />{/* the book-till date, */}
        <Select label="Sessions in school holidays?" name="school_holidays" defaultValue="no">{/* school holidays yes or no: */}
          <option value="no">No</option>{/* no, */}
          <option value="yes">Yes</option>{/* yes. */}
        </Select>{/* End of the drop-down. */}
        <Select label="Sessions on public holidays?" name="public_holidays" defaultValue="no">{/* public holidays yes or no: */}
          <option value="no">No</option>{/* no, */}
          <option value="yes">Yes</option>{/* yes. */}
        </Select>{/* End of the drop-down. */}
      </div>{/* End of the columns. */}
      <TextArea label="CLG's note (optional, admins only)" name="note" maxLength={500} rows={2} defaultValue={current?.note ?? ""} />{/* CLG's own note. */}
    </> // End of the group.
  ); // End of what is shown.
} // End of PlaceFields.

// Shows the right program forms for one student.
export function SspForm({ studentId, current }: { studentId: string; current: SspRecord | null }) { // Takes the student and their record (none if they never asked).
  const status = current?.status ?? null; // Where they are up to (nothing if never asked).
  const canApprove = status === null || ["requested", "declined", "withdrawn", "left"].includes(status); // No place yet: a place can be approved.
  return ( // Shows:
    <div className="space-y-4">{/* a block: */}
      {status === "requested" && current?.request_note && ( // If the family left a message with their request:
        <p className="rounded-lg bg-zinc-50 p-3 text-sm text-zinc-700">{/* a grey box: */}
          <span className="font-medium">The family wrote:</span> {current.request_note}{/* their message. */}
        </p> // End of the box.
      )}{/* End of this part. */}
      {canApprove && ( // No place yet:
        <ActionForm action={approveStudentSuccessPlace} submitLabel="Approve the place and send the $500 deposit invoice">{/* the approve form: */}
          <p className="text-sm text-zinc-600">Approving holds one of the places and sends the family the deposit invoice (they pay it in Billing). The student is in the program once it is paid. The family needs billing set up first.</p>{/* what approving does. */}
          <PlaceFields studentId={studentId} current={current} />{/* the details boxes. */}
        </ActionForm> // End of the approve form.
      )}{/* End of this part. */}
      {status === "requested" && ( // A request waiting:
        <ActionForm action={declineStudentSuccessRequest} submitLabel="Decline the request">{/* the decline form: */}
          <input type="hidden" name="student_id" value={studentId} />{/* which student (hidden), */}
          <TextArea label="Reason for the family (optional)" name="reason" maxLength={500} rows={2} hint="The family sees this in the app and by email." />{/* the reason. */}
        </ActionForm> // End of the decline form.
      )}{/* End of this part. */}
      {(status === "approved" || status === "enrolled") && ( // A place held or in use:
        <ActionForm action={saveStudentSuccessDetails} submitLabel="Save program details">{/* the details form: */}
          <PlaceFields studentId={studentId} current={current} />{/* the details boxes. */}
        </ActionForm> // End of the details form.
      )}{/* End of this part. */}
      {status === "approved" && ( // A place waiting for its deposit:
        <ActionForm action={withdrawStudentSuccessPlace} submitLabel="Withdraw the place">{/* the withdraw form: */}
          <input type="hidden" name="student_id" value={studentId} />{/* which student (hidden), */}
          <p className="text-sm text-zinc-600">Withdrawing frees the place and cancels the unpaid deposit invoice. If the invoice is already in Xero, void it there too.</p>{/* what withdrawing does, */}
          <TextArea label="Reason for the family" name="reason" required minLength={5} maxLength={500} rows={2} hint="The family sees this in the app and by email." />{/* the reason. */}
        </ActionForm> // End of the withdraw form.
      )}{/* End of this part. */}
      {status === "enrolled" && ( // In the program:
        <ActionForm action={leaveStudentSuccessProgram} submitLabel="Remove from the program">{/* the remove form: */}
          <input type="hidden" name="student_id" value={studentId} />{/* which student (hidden), */}
          <p className="text-sm text-zinc-600">Removing them frees the place and ends the study plan given for the program. Term reviews are then offered to the family as usual. Booked sessions stay booked. Any refund follows CLG&apos;s terms and is done in Billing.</p>{/* what removing does. */}
        </ActionForm> // End of the remove form.
      )}{/* End of this part. */}
    </div> // End of the block.
  ); // End of what is shown.
} // End of SspForm.

// The form for the number of places and the days to pay the deposit.
export function SspPlacesForm({ spaces, dueDays }: { spaces: number; dueDays: number }) { // Takes the current numbers.
  return ( // Shows:
    <ActionForm action={saveStudentSuccessPlaces} submitLabel="Save places">{/* the form: */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label="Places in the program" name="spaces" type="number" min={0} max={1000} defaultValue={spaces} required />{/* places in total, */}
        <Field label="Days to pay the deposit" name="due_days" type="number" min={1} max={60} defaultValue={dueDays} required />{/* days to pay. */}
      </div>{/* End of the columns. */}
    </ActionForm> // End of the form.
  ); // End of what is shown.
} // End of SspPlacesForm.
