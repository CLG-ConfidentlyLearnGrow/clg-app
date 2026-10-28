"use client";

import { giveStudentLogin } from "@/app/actions/family-setup";
import { ActionForm } from "@/components/action-form";
import { Field } from "@/components/ui";

// An admin gives a student on a parent's account their own login.
export function StudentLoginForm({ students }: { students: { id: string; name: string }[] }) {
  if (students.length === 0) {
    return <p className="text-sm text-zinc-600">No students aged 16 or over are on a parent&apos;s account.</p>;
  }
  return (
    <ActionForm action={giveStudentLogin} submitLabel="Send login link">
      <label className="block space-y-1">
        <span className="text-sm font-medium">Student</span>
        <select
          name="student_id"
          required
          defaultValue=""
          className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"
        >
          <option value="" disabled>
            Choose…
          </option>
          {students.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </select>
      </label>
      <Field
        label="Student's own email"
        name="email"
        type="email"
        required
        hint="Must be an email no one uses for CLG yet. The student gets a link to choose a password."
      />
    </ActionForm>
  );
}
