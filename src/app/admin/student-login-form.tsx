// Summary: the admin form for giving a student on a parent's account their own login.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { giveStudentLogin } from "@/app/actions/family-setup"; // The server action that sends the login link.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field } from "@/components/ui"; // A labelled input box.

// An admin gives a student on a parent's account their own login.
export function StudentLoginForm({ students }: { students: { id: string; name: string }[] }) {
  if (students.length === 0) { // No students to choose from:
    return <p className="text-sm text-zinc-600">No students aged 16 or over are on a parent&apos;s account.</p>; // says so.
  } // End of that case.
  return ( // Shows:
    <ActionForm action={giveStudentLogin} submitLabel="Send login link">{/* a form that sends the login link: */}
      <label className="block space-y-1">{/* a labelled block: */}
        <span className="text-sm font-medium">Student</span>{/* the label "Student", */}
        <select // a drop-down:
          name="student_id" // its field name,
          required // that must be chosen,
          defaultValue="" // starting on the blank option,
          className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none" // styled like the other boxes.
        >{/* (end of its settings) */}
          <option value="" disabled>{/* a blank first option that can't be picked: */}
            Choose…{/* "Choose…", */}
          </option>{/* (end of the option) */}
          {students.map((s) => ( // for each student:
            <option key={s.id} value={s.id}>{/* an option: */}
              {s.name}{/* showing their name. */}
            </option> // (end of the option)
          ))}{/* End of the students loop. */}
        </select>{/* End of the drop-down. */}
      </label>{/* End of the block. */}
      <Field // An email box:
        label="Student's own email" // its label,
        name="email" // its field name,
        type="email" // an email address,
        required // that must be filled in,
        hint="Must be an email no one uses for CLG yet. The student gets a link to choose a password." // and a hint about what happens next.
      />{/* (end of the box) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of StudentLoginForm.
