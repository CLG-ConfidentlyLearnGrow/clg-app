"use client";

import { createFramework, importSkills, setStudentFramework } from "@/app/actions/curriculum";
import { ActionForm } from "@/components/action-form";
import { Field, Select, TextArea } from "@/components/ui";

type Option = { id: string; name: string };

export function FrameworkForm() {
  return (
    <ActionForm action={createFramework} submitLabel="Add curriculum">
      <Field label="Short code" name="code" required maxLength={30} hint="For example AC9 or SACE." />
      <Field label="Name" name="name" required maxLength={200} hint="For example Australian Curriculum." />
      <Field label="Version" name="version" required maxLength={40} hint="For example 9.0." />
      <Field label="In use from (optional)" name="starts_on" type="date" />
    </ActionForm>
  );
}

export function ImportSkillsForm({ frameworks }: { frameworks: Option[] }) {
  return (
    <ActionForm action={importSkills} submitLabel="Load skills">
      <Select label="Curriculum" name="framework_id" required defaultValue="">
        <option value="" disabled>
          Choose…
        </option>
        {frameworks.map((f) => (
          <option key={f.id} value={f.id}>
            {f.name}
          </option>
        ))}
      </Select>
      <TextArea
        label="Skills, one per line"
        name="rows"
        rows={8}
        required
        hint='Columns: code, subject, year or level, official wording, plain wording for parents (optional). Paste from a spreadsheet, or separate with commas and put "quotes" around text containing commas.'
      />
    </ActionForm>
  );
}

export function StudentFrameworkForm({ students, frameworks }: { students: Option[]; frameworks: Option[] }) {
  return (
    <ActionForm action={setStudentFramework} submitLabel="Set curriculum">
      <Select label="Student" name="student_id" required defaultValue="">
        <option value="" disabled>
          Choose…
        </option>
        {students.map((s) => (
          <option key={s.id} value={s.id}>
            {s.name}
          </option>
        ))}
      </Select>
      <Select label="Curriculum" name="framework_id" required defaultValue="">
        <option value="" disabled>
          Choose…
        </option>
        {frameworks.map((f) => (
          <option key={f.id} value={f.id}>
            {f.name}
          </option>
        ))}
      </Select>
      <p className="text-xs text-zinc-500">A student can have more than one, for example AC9 and SACE.</p>
    </ActionForm>
  );
}
