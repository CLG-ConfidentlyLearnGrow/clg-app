// Summary: the admin forms for the Student Success Program (Carla, 22 Nov
// 2026). One form puts a student in the program or updates their details
// (sessions planned, book-till date, holidays, deposit date, note). The other
// takes them out of the program.
//
"use client"; // Runs in the browser, so each form can show its result straight away.

import { leaveStudentSuccessProgram, saveStudentSuccessProgram } from "@/app/actions/student-success-program"; // The server actions.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // The input box, drop-down list and larger text box.

// What the form already knows about the student's place in the program.
export type SspDetails = { // A program record:
  sessions_planned: number | null; // sessions planned (if known),
  book_until: string | null; // the book-till date (if known),
  deposit_paid_on: string | null; // when the deposit was paid (if known),
  note: string | null; // and a note.
}; // End of the type.

// Shows the program form for one student.
export function SspForm({ studentId, current }: { studentId: string; current: SspDetails | null }) { // Takes the student and their record (none if not in it).
  return ( // Shows:
    <div className="space-y-4">{/* a block: */}
      <ActionForm action={saveStudentSuccessProgram} submitLabel={current ? "Save program details" : "Add to the Student Success Program"}>{/* the save form: */}
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
          <Field label="Deposit paid on (optional)" name="deposit_paid_on" type="date" defaultValue={current?.deposit_paid_on ?? ""} />{/* the deposit date, */}
        </div>{/* End of the columns. */}
        <TextArea label="Note (optional)" name="note" maxLength={500} rows={2} defaultValue={current?.note ?? ""} />{/* a note. */}
      </ActionForm>{/* End of the save form. */}
      {current && ( // If they are in the program:
        <ActionForm action={leaveStudentSuccessProgram} submitLabel="Remove from the program">{/* the remove form: */}
          <input type="hidden" name="student_id" value={studentId} />{/* which student (hidden), */}
          <p className="text-sm text-zinc-600">Removing them ends the study plan given for the program. Term reviews are then offered to the family as usual. Booked sessions stay booked.</p>{/* what removing does. */}
        </ActionForm> // End of the remove form.
      )}{/* End of this part. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of SspForm.
