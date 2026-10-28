"use client";

import { useActionState } from "react";
import {
  addMaterialSkills,
  deleteDraftMaterial,
  removeMaterialSkill,
  setMaterialStatus,
  updateMaterialDetails,
} from "@/app/actions/materials";
import { ActionForm } from "@/components/action-form";
import { Button, Field, FormMessage, Select, TextArea } from "@/components/ui";
import { initialFormState } from "@/lib/forms";
import { MATERIAL_KINDS, MATERIAL_KIND_NAMES } from "@/lib/materials";
import { SUBJECT_SUGGESTIONS, YEAR_LEVELS } from "@/lib/students";

type Material = {
  id: string;
  title: string;
  kind: string;
  subject: string;
  from_level: string;
  to_level: string;
  description: string | null;
  status: string;
  no_skills_reason: string | null;
};

export type SkillOption = {
  id: string;
  framework: string;
  subject: string;
  level_band: string;
  code: string | null;
  description: string;
  plain_description: string | null;
};

const inputClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none";

export function MaterialDetailsForm({ m }: { m: Material }) {
  return (
    <ActionForm action={updateMaterialDetails} submitLabel="Save details">
      <input type="hidden" name="id" value={m.id} />
      <Field label="Title" name="title" defaultValue={m.title} required maxLength={200} />
      <div className="grid gap-4 sm:grid-cols-2">
        <Select label="Kind" name="kind" defaultValue={m.kind}>
          {MATERIAL_KINDS.map((k) => (
            <option key={k} value={k}>
              {MATERIAL_KIND_NAMES[k]}
            </option>
          ))}
        </Select>
        <label className="block space-y-1">
          <span className="text-sm font-medium text-zinc-800">Subject</span>
          <input name="subject" list="material-subjects-edit" required defaultValue={m.subject} className={inputClass} />
          <datalist id="material-subjects-edit">
            {SUBJECT_SUGGESTIONS.map((s) => (
              <option key={s} value={s} />
            ))}
          </datalist>
        </label>
        <Select label="Suits from" name="from_level" defaultValue={m.from_level}>
          {YEAR_LEVELS.map((y) => (
            <option key={y}>{y}</option>
          ))}
        </Select>
        <Select label="Suits up to" name="to_level" defaultValue={m.to_level}>
          {YEAR_LEVELS.map((y) => (
            <option key={y}>{y}</option>
          ))}
        </Select>
      </div>
      <TextArea label="Note for tutors (optional)" name="description" defaultValue={m.description ?? ""} maxLength={1000} />
    </ActionForm>
  );
}

function skillLabel(s: SkillOption) {
  return (
    <>
      <span className="font-medium">{s.code ?? s.framework}</span>{" "}
      <span className="text-zinc-500">
        ({s.subject}, {s.level_band})
      </span>{" "}
      {s.plain_description || s.description}
    </>
  );
}

// Tick skills from the search results to add them as tags.
export function AddSkillsForm({ id, options }: { id: string; options: SkillOption[] }) {
  const [state, action, pending] = useActionState(addMaterialSkills, initialFormState);
  return (
    <form action={action} className="space-y-3">
      <FormMessage state={state} />
      <input type="hidden" name="id" value={id} />
      <ul className="max-h-96 space-y-1 overflow-y-auto rounded-xl border border-zinc-200 p-2">
        {options.map((s) => (
          <li key={s.id}>
            <label className="flex items-start gap-2 rounded-md px-2 py-1.5 text-sm hover:bg-teal-50">
              <input type="checkbox" name="skill" value={s.id} className="mt-1" />
              <span>{skillLabel(s)}</span>
            </label>
          </li>
        ))}
      </ul>
      <Button type="submit" disabled={pending}>
        {pending ? "Please wait…" : "Add ticked skills"}
      </Button>
    </form>
  );
}

export function TaggedSkill({ id, skill }: { id: string; skill: SkillOption }) {
  const [state, action, pending] = useActionState(removeMaterialSkill, initialFormState);
  return (
    <li className="flex items-start justify-between gap-3 py-2 text-sm">
      <span>
        {skillLabel(skill)}
        {state.error && <span className="mt-1 block text-red-700">{state.error}</span>}
      </span>
      <form action={action}>
        <input type="hidden" name="id" value={id} />
        <input type="hidden" name="skill" value={skill.id} />
        <button type="submit" disabled={pending} className="text-xs text-red-700 underline">
          Remove
        </button>
      </form>
    </li>
  );
}

export function PublishForm({ m, skillCount }: { m: Material; skillCount: number }) {
  const [state, action, pending] = useActionState(setMaterialStatus, initialFormState);
  const [delState, delAction, deleting] = useActionState(deleteDraftMaterial, initialFormState);
  return (
    <div className="space-y-4">
      <FormMessage state={state} />
      <FormMessage state={delState} />
      {m.status !== "published" ? (
        <form action={action} className="space-y-3">
          <input type="hidden" name="id" value={m.id} />
          <input type="hidden" name="status" value="published" />
          {skillCount === 0 && (
            <Field
              label="No curriculum fits? Say why"
              name="no_skills_reason"
              defaultValue={m.no_skills_reason ?? ""}
              maxLength={300}
              hint="Only if there is no curriculum for this, for example study skills or a university unit. Otherwise tag skills above."
            />
          )}
          <Button type="submit" disabled={pending}>
            {pending ? "Please wait…" : m.status === "retired" ? "Publish again" : "Publish to tutors"}
          </Button>
        </form>
      ) : (
        <form action={action}>
          <input type="hidden" name="id" value={m.id} />
          <input type="hidden" name="status" value="retired" />
          <Button type="submit" disabled={pending}>
            {pending ? "Please wait…" : "Retire (hide from tutors)"}
          </Button>
        </form>
      )}
      {m.status === "draft" && (
        <form action={delAction}>
          <input type="hidden" name="id" value={m.id} />
          <button type="submit" disabled={deleting} className="text-sm text-red-700 underline">
            Delete this draft and its files
          </button>
        </form>
      )}
    </div>
  );
}
