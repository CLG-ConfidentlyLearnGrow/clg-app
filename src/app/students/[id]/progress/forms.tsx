"use client";

import { addGoal, saveReflection, saveSessionNote } from "@/app/actions/progress";
import { ActionForm } from "@/components/action-form";
import { Field, Select, TextArea } from "@/components/ui";
import {
  ATTENDANCE,
  ATTENDANCE_NAMES,
  CONFIDENCE_NAMES,
  SKILL_LEVEL_NAMES,
  nextLevels,
  type SkillLevel,
} from "@/lib/progress";

export type SkillOption = { id: string; label: string; levelBand: string };
export type GoalSkill = { id: string; label: string; level: SkillLevel; goal: string };

export function AddGoalForm({
  studentId,
  subject,
  skills,
}: {
  studentId: string;
  subject: string;
  skills: SkillOption[];
}) {
  return (
    <ActionForm action={addGoal} submitLabel="Add goal">
      <input type="hidden" name="student_id" value={studentId} />
      <input type="hidden" name="subject" value={subject} />
      <Field
        label="Goal"
        name="title"
        required
        maxLength={200}
        hint='Write it so a parent understands, for example "Solve two-step equations without prompts".'
      />
      <Field label="Aim to reach it by (optional)" name="target_date" type="date" />
      <fieldset className="space-y-1">
        <legend className="mb-1 text-sm font-medium">Skills this goal covers</legend>
        <p className="text-xs text-zinc-500">
          Pick by what the student is ready for, not their year level. The year is shown for context only.
        </p>
        <div className="max-h-72 space-y-1 overflow-y-auto rounded-md border border-zinc-200 p-2 dark:border-zinc-800">
          {skills.map((s) => (
            <label key={s.id} className="flex items-start gap-2 text-sm">
              <input type="checkbox" name="skill_id" value={s.id} className="mt-1" />
              <span>
                <span className="text-zinc-500">{s.levelBand}:</span> {s.label}
              </span>
            </label>
          ))}
        </div>
      </fieldset>
    </ActionForm>
  );
}

export function SessionNoteForm({ studentId, skills }: { studentId: string; skills: GoalSkill[] }) {
  const today = new Date().toISOString().slice(0, 10);
  return (
    <ActionForm action={saveSessionNote} submitLabel="Save note">
      <input type="hidden" name="student_id" value={studentId} />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Field label="Session date" name="session_date" type="date" defaultValue={today} max={today} required />
        <Field label="Minutes" name="minutes" type="number" min={0} max={480} step={5} defaultValue={60} required />
        <Select label="Attendance" name="attendance" defaultValue="attended">
          {ATTENDANCE.map((a) => (
            <option key={a} value={a}>
              {ATTENDANCE_NAMES[a]}
            </option>
          ))}
        </Select>
      </div>

      {skills.length > 0 && (
        <fieldset className="space-y-2">
          <legend className="mb-1 text-sm font-medium">Skills worked on</legend>
          <p className="text-xs text-zinc-500">
            Leave a skill blank if you didn&apos;t work on it. Each skill can stay where it is or move one step.
          </p>
          {skills.map((s) => (
            <label key={s.id} className="block space-y-1 text-sm">
              <span>
                {s.label} <span className="text-zinc-500">({s.goal})</span>
              </span>
              <select
                name={`skill_${s.id}`}
                defaultValue=""
                className="w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
              >
                <option value="">Not worked on today</option>
                {nextLevels(s.level).map((l) => (
                  <option key={l} value={l}>
                    {SKILL_LEVEL_NAMES[l]}
                    {l === s.level ? " (no change)" : ""}
                  </option>
                ))}
              </select>
            </label>
          ))}
        </fieldset>
      )}

      <TextArea
        label="What went well"
        name="went_well"
        maxLength={1000}
        hint="One or two sentences, written to the student. The family sees this as written."
      />
      <TextArea
        label="Next step"
        name="next_step"
        maxLength={500}
        hint="One specific thing for the student to do next, written to them. This matters most."
      />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <Field label="Homework or practice (optional)" name="homework" maxLength={1000} />
        </div>
        <Field label="Due (optional)" name="homework_due" type="date" />
      </div>
      <TextArea
        label="Note for CLG staff only (optional)"
        name="staff_note"
        maxLength={4000}
        rows={2}
        hint="Never shown to the student or family. For a child safety concern, use the reporting route in the child safe policy, not this box."
      />
    </ActionForm>
  );
}

export function ReflectionForm({ studentId, noteId }: { studentId: string; noteId: string }) {
  return (
    <ActionForm action={saveReflection} submitLabel="Send to my tutor">
      <input type="hidden" name="student_id" value={studentId} />
      <input type="hidden" name="note_id" value={noteId} />
      <Select label="How confident do you feel about this work?" name="confidence" defaultValue="" required>
        <option value="" disabled>
          Choose…
        </option>
        {[1, 2, 3, 4].map((n) => (
          <option key={n} value={n}>
            {CONFIDENCE_NAMES[n]}
          </option>
        ))}
      </Select>
      <Field label="What was hard? (optional)" name="what_was_hard" maxLength={500} />
      <Field label="What will you try before next time? (optional)" name="what_i_will_try" maxLength={500} />
    </ActionForm>
  );
}
