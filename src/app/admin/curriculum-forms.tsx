// Summary: admin forms for curricula: add one, load its skills, and set a student's curriculum.
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { createFramework, importSkills, setStudentFramework } from "@/app/actions/curriculum"; // The server actions for the three forms.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // The input box, drop-down list and larger text box.

type Option = { id: string; name: string }; // An item in a drop-down: its id and name.

// The form for adding a curriculum.
export function FrameworkForm() {
  return ( // Shows:
    <ActionForm action={createFramework} submitLabel="Add curriculum">{/* a form that adds it: */}
      <Field label="Short code" name="code" required maxLength={30} hint="For example AC9 or SACE." />{/* a short code, */}
      <Field label="Name" name="name" required maxLength={200} hint="For example Australian Curriculum." />{/* its name, */}
      <Field label="Version" name="version" required maxLength={40} hint="For example 9.0." />{/* its version, */}
      <Field label="In use from (optional)" name="starts_on" type="date" />{/* the date it's in use from (optional). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of FrameworkForm.

// The form for loading skills into a curriculum.
export function ImportSkillsForm({ frameworks }: { frameworks: Option[] }) {
  return ( // Shows:
    <ActionForm action={importSkills} submitLabel="Load skills">{/* a form that loads them: */}
      <Select label="Curriculum" name="framework_id" required defaultValue="">{/* a drop-down of curricula: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose…{/* "Choose…", */}
        </option>{/* (end of the option) */}
        {frameworks.map((f) => ( // for each curriculum:
          <option key={f.id} value={f.id}>{/* an option: */}
            {f.name}{/* showing its name. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <TextArea // A text box:
        label="Skills, one per line" // its label,
        name="rows" // its field name,
        rows={8} // eight lines tall,
        required // that must be filled in,
        hint='Columns: code, subject, year or level, official wording, plain wording for parents (optional). Paste from a spreadsheet, or separate with commas and put "quotes" around text containing commas.' // and a hint about the columns.
      />{/* (end of the text box) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of ImportSkillsForm.

// The form for setting which curriculum a student follows.
export function StudentFrameworkForm({ students, frameworks }: { students: Option[]; frameworks: Option[] }) {
  return ( // Shows:
    <ActionForm action={setStudentFramework} submitLabel="Set curriculum">{/* a form that sets it: */}
      <Select label="Student" name="student_id" required defaultValue="">{/* a drop-down of students: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose…{/* "Choose…", */}
        </option>{/* (end of the option) */}
        {students.map((s) => ( // for each student:
          <option key={s.id} value={s.id}>{/* an option: */}
            {s.name}{/* showing their name. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <Select label="Curriculum" name="framework_id" required defaultValue="">{/* A drop-down of curricula: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose…{/* "Choose…", */}
        </option>{/* (end of the option) */}
        {frameworks.map((f) => ( // for each curriculum:
          <option key={f.id} value={f.id}>{/* an option: */}
            {f.name}{/* showing its name. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <p className="text-xs text-zinc-500">A student can have more than one, for example AC9 and SACE.</p>{/* A note that a student can have more than one. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of StudentFrameworkForm.
