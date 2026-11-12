// Summary: admin forms for one material: details, adding and removing skills, and publishing.
//
"use client"; // Runs in the browser, so the forms can react straight away.

import { useActionState } from "react"; // Lets a form run a server action and remember its reply.
import { // The server actions for these forms:
  addMaterialSkills, // add skills,
  deleteDraftMaterial, // delete a draft,
  removeMaterialSkill, // remove a skill,
  setMaterialStatus, // publish or retire,
  updateMaterialDetails, // save details.
} from "@/app/actions/materials"; // (end of the list)
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Button, Field, FormMessage, Select, TextArea } from "@/components/ui"; // The button, input box, reply message, drop-down and larger text box.
import { initialFormState } from "@/lib/forms"; // The starting (empty) form reply.
import { MATERIAL_KINDS, MATERIAL_KIND_NAMES } from "@/lib/materials"; // The kinds of material and their names.
import { SUBJECT_SUGGESTIONS, YEAR_LEVELS } from "@/lib/students"; // Suggested subjects, and the list of year levels.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while sending.

// A material as these forms need it.
type Material = {
  id: string; // its id,
  title: string; // title,
  kind: string; // kind,
  subject: string; // subject,
  from_level: string; // lowest year level,
  to_level: string; // highest year level,
  description: string | null; // note for tutors (if any),
  status: string; // status,
  no_skills_reason: string | null; // and why no skills fit (if given).
}; // End of the shape.

// A curriculum skill that can be tagged.
export type SkillOption = {
  id: string; // its id,
  framework: string; // its curriculum, e.g. "AC9 v9.0",
  subject: string; // the subject,
  level_band: string; // the year level or band,
  code: string | null; // its code (if any),
  description: string; // the official wording,
  plain_description: string | null; // and plain wording for parents (if any).
}; // End of the shape.

const inputClass = // The style for a plain input box:
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"; // (matching the other boxes).

// The form for a material's details.
export function MaterialDetailsForm({ m }: { m: Material }) {
  return ( // Shows:
    <ActionForm action={updateMaterialDetails} submitLabel="Save details">{/* a form that saves the details: */}
      <input type="hidden" name="id" value={m.id} />{/* the material's id (hidden), */}
      <Field label="Title" name="title" defaultValue={m.title} required maxLength={200} />{/* the title, */}
      <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="Kind" name="kind" defaultValue={m.kind}>{/* a drop-down of kinds: */}
          {MATERIAL_KINDS.map((k) => ( // for each kind:
            <option key={k} value={k}>{/* an option: */}
              {MATERIAL_KIND_NAMES[k]}{/* its name. */}
            </option> // (end of the option)
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <label className="block space-y-1">{/* A label: */}
          <span className="text-sm font-medium text-zinc-800">Subject</span>{/* "Subject", */}
          <input name="subject" list="material-subjects-edit" required defaultValue={m.subject} className={inputClass} />{/* a text box with suggestions (must be filled in), */}
          <datalist id="material-subjects-edit">{/* the suggestions list: */}
            {SUBJECT_SUGGESTIONS.map((s) => ( // for each suggested subject:
              <option key={s} value={s} /> // an option.
            ))}{/* End of the loop. */}
          </datalist>{/* End of the suggestions. */}
        </label>{/* End of the label. */}
        <Select label="Suits from" name="from_level" defaultValue={m.from_level}>{/* A drop-down of the lowest year: */}
          {YEAR_LEVELS.map((y) => ( // for each year:
            <option key={y}>{y}</option> // an option.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <Select label="Suits up to" name="to_level" defaultValue={m.to_level}>{/* A drop-down of the highest year: */}
          {YEAR_LEVELS.map((y) => ( // for each year:
            <option key={y}>{y}</option> // an option.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
      </div>{/* End of the columns. */}
      <TextArea label="Note for tutors (optional)" name="description" defaultValue={m.description ?? ""} maxLength={1000} />{/* The note for tutors (optional). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of MaterialDetailsForm.

// Shows a skill's code, subject, level and words.
function skillLabel(s: SkillOption) {
  return ( // Shows:
    <>{/* (a group:) */}
      <span className="font-medium">{s.code ?? s.framework}</span>{" "}{/* the code (or curriculum) in bold, */}
      <span className="text-zinc-500">{/* grey details: */}
        ({s.subject}, {s.level_band}){/* (subject and level), */}
      </span>{" "}{/* (end of the details and a space) */}
      {s.plain_description || s.description}{/* the plain words (or official words). */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of skillLabel.

// Tick skills from the search results to add them as tags.
export function AddSkillsForm({ id, options }: { id: string; options: SkillOption[] }) {
  const [state, action, pending] = useActionState(addMaterialSkills, initialFormState); // The reply, the action to send, and whether it's sending.
  return ( // Shows:
    <form action={action} className="space-y-3">{/* a form: */}
      <FormMessage state={state} />{/* the reply message, */}
      <input type="hidden" name="id" value={id} />{/* the material's id (hidden), */}
      <ul className="max-h-96 space-y-1 overflow-y-auto rounded-xl border border-zinc-200 p-2">{/* a scrolling list: */}
        {options.map((s) => ( // for each skill:
          <li key={s.id}>{/* a list item: */}
            <label className="flex items-start gap-2 rounded-md px-2 py-1.5 text-sm hover:bg-teal-50">{/* a line holding: */}
              <input type="checkbox" name="skill" value={s.id} className="mt-1" />{/* a tick box for this skill, */}
              <span>{skillLabel(s)}</span>{/* and its words. */}
            </label>{/* End of the line. */}
          </li> // End of the list item.
        ))}{/* End of the loop. */}
      </ul>{/* End of the list. */}
      <Button type="submit" disabled={pending}>{/* The button (greyed out while sending): */}
        {pending ? "Please wait…" : "Add ticked skills"}{/* its words change while sending. */}
      </Button>{/* End of the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of AddSkillsForm.

// A tagged skill, with a button to remove it.
export function TaggedSkill({ id, skill }: { id: string; skill: SkillOption }) {
  const [state, action, pending] = useActionState(removeMaterialSkill, initialFormState); // The reply, the action to send, and whether it's sending.
  return ( // Shows:
    <li className="flex items-start justify-between gap-3 py-2 text-sm">{/* a list item in one row: */}
      <span>{/* the words: */}
        {skillLabel(skill)}{/* the skill, */}
        {state.error && <span className="mt-1 block text-red-700">{state.error}</span>}{/* and any error in red. */}
      </span>{/* End of the words. */}
      <form action={action}>{/* A form that removes it: */}
        <input type="hidden" name="id" value={id} />{/* the material's id (hidden), */}
        <input type="hidden" name="skill" value={skill.id} />{/* the skill's id (hidden), */}
        <BusyButton type="submit" disabled={pending} className="text-xs text-red-700 underline">{/* a small red button: */}
          Remove{/* "Remove". */}
        </BusyButton>{/* End of the button. */}
      </form>{/* End of the form. */}
    </li> // End of the list item.
  ); // End of what's shown.
} // End of TaggedSkill.

// Publishing: publish (or publish again), retire, or delete a draft.
export function PublishForm({ m, skillCount }: { m: Material; skillCount: number }) {
  const [state, action, pending] = useActionState(setMaterialStatus, initialFormState); // The publish or retire reply, action and whether it's sending.
  const [delState, delAction, deleting] = useActionState(deleteDraftMaterial, initialFormState); // The delete reply, action and whether it's deleting.
  return ( // Shows:
    <div className="space-y-4">{/* a block with space between parts: */}
      <FormMessage state={state} />{/* the publish reply, */}
      <FormMessage state={delState} />{/* the delete reply, */}
      {m.status !== "published" ? ( // if not published:
        <form action={action} className="space-y-3">{/* a form that publishes it: */}
          <input type="hidden" name="id" value={m.id} />{/* the material's id (hidden), */}
          <input type="hidden" name="status" value="published" />{/* the new status (hidden), */}
          {skillCount === 0 && ( // if no skills are tagged:
            <Field // a box for why:
              label="No curriculum fits? Say why" // its label,
              name="no_skills_reason" // its field name,
              defaultValue={m.no_skills_reason ?? ""} // starting with any reason given before,
              maxLength={300} // up to 300 characters,
              hint="Only if there is no curriculum for this, for example study skills or a university unit. Otherwise tag skills above." // and a hint.
            /> // (end of the box)
          )}{/* End of that part. */}
          <Button type="submit" disabled={pending}>{/* The button (greyed out while sending): */}
            {pending ? "Please wait…" : m.status === "retired" ? "Publish again" : "Publish to tutors"}{/* "Publish again" or "Publish to tutors". */}
          </Button>{/* End of the button. */}
        </form> // End of the form.
      ) : ( // If published:
        <form action={action}>{/* a form that retires it: */}
          <input type="hidden" name="id" value={m.id} />{/* the material's id (hidden), */}
          <input type="hidden" name="status" value="retired" />{/* the new status (hidden), */}
          <Button type="submit" disabled={pending}>{/* the button (greyed out while sending): */}
            {pending ? "Please wait…" : "Retire (hide from tutors)"}{/* "Retire". */}
          </Button>{/* End of the button. */}
        </form> // End of the form.
      )}{/* End of the choice. */}
      {m.status === "draft" && ( // If it's a draft:
        <form action={delAction}>{/* a form that deletes it: */}
          <input type="hidden" name="id" value={m.id} />{/* the material's id (hidden), */}
          <BusyButton type="submit" disabled={deleting} className="text-sm text-red-700 underline">{/* a small red button: */}
            Delete this draft and its files{/* "Delete this draft". */}
          </BusyButton>{/* End of the button. */}
        </form> // End of the form.
      )}{/* End of the draft part. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of PublishForm.
