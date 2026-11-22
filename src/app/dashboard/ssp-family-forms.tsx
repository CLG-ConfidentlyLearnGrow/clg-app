// Summary: the family's Student Success Program forms (Carla, 22 Nov 2026):
// a tick box to ask about a place (with an optional message), and a button
// to cancel a request before CLG decides.
//
"use client"; // Runs in the browser, so each form can show its result straight away.

import { askAboutStudentSuccessProgram, cancelStudentSuccessRequest } from "@/app/actions/student-success-program"; // The server actions.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { TextArea } from "@/components/ui"; // The larger text box.

// The tick box to ask about a place.
export function SspAskForm({ studentId, name }: { studentId: string; name: string }) { // Takes the student and their name.
  return ( // Shows:
    <ActionForm action={askAboutStudentSuccessProgram} submitLabel="Send my request">{/* the form: */}
      <input type="hidden" name="student_id" value={studentId} />{/* which student (hidden), */}
      <label className="flex items-start gap-2 text-sm">{/* the tick box and its words: */}
        <input type="checkbox" name="ask" value="yes" required className="mt-1 h-4 w-4 accent-[#a8815b]" />{/* the tick box (must be ticked), */}
        <span>Yes, I would like to ask about a place in the Student Success Program for {name}.</span>{/* what ticking it means. */}
      </label>{/* End of the tick box. */}
      <TextArea label="Anything CLG should know (optional)" name="note" maxLength={500} rows={2} />{/* an optional message. */}
    </ActionForm> // End of the form.
  ); // End of what is shown.
} // End of SspAskForm.

// The button to cancel a request.
export function SspCancelForm({ studentId }: { studentId: string }) { // Takes the student.
  return ( // Shows:
    <ActionForm action={cancelStudentSuccessRequest} submitLabel="Cancel my request">{/* the form: */}
      <input type="hidden" name="student_id" value={studentId} />{/* which student (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what is shown.
} // End of SspCancelForm.
