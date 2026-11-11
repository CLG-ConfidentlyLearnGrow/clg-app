// Summary: admin forms and lists for parent links and possible double-up students.
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { dismissDuplicate, linkParent, mergeStudents, unlinkParent } from "@/app/actions/parent-links"; // The server actions for these forms.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Empty, Field, Select } from "@/components/ui"; // The "nothing yet" note, input box and drop-down list.

type StudentOption = { id: string; name: string; born: string | null }; // A student to choose: id, name and date of birth.

// A parent link as the database gives it.
export type ParentLinkRow = {
  student_id: string; // the student,
  student_name: string; // their name,
  parent_id: string; // the parent,
  parent_name: string; // their name,
  relationship: string; // the relationship,
  can_manage: boolean; // whether they can change details,
  confirmed: boolean; // and whether CLG has confirmed it.
}; // End of the shape.

// A pair of students that may be the same child.
export type DuplicateRow = {
  student_id: string; // the first student,
  full_name: string; // their name,
  date_of_birth: string | null; // date of birth,
  parents: string | null; // parents,
  added_at: string; // when added;
  other_student_id: string; // the second student,
  other_full_name: string; // their name,
  other_date_of_birth: string | null; // date of birth,
  other_parents: string | null; // parents,
  other_added_at: string; // when added.
}; // End of the shape.

// Writes a date of birth in words, or says there isn't one.
function born(date: string | null) {
  return date ? `born ${new Date(date).toLocaleDateString("en-AU")}` : "no date of birth yet"; // e.g. "born 3/5/2014".
} // End of born.

// Link another parent or guardian to a student already in the app.
export function LinkParentForm({ students }: { students: StudentOption[] }) {
  if (students.length === 0) return <Empty>No students yet.</Empty>; // No students: says so.
  return ( // Shows:
    <ActionForm action={linkParent} submitLabel="Link parent">{/* a form that links the parent: */}
      <Select label="Student" name="student_id" required defaultValue="">{/* a drop-down of students: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose…{/* "Choose…", */}
        </option>{/* (end of the option) */}
        {students.map((s) => ( // for each student:
          <option key={s.id} value={s.id}>{/* an option: */}
            {s.name} ({born(s.born)}){/* their name and date of birth. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <Field // The email box:
        label="Parent's or guardian's email" // its label,
        name="email" // its field name,
        type="email" // an email address,
        required // that must be filled in,
        hint="If they already have a CLG account (for example they're also a tutor), we use it. If not, we make one and send them a link." // and a hint about new and existing accounts.
      />{/* (end of the box) */}
      <Field // The name box:
        label="Their full name (only needed if they're new to CLG)" // its label,
        name="contact_name" // its field name,
        maxLength={200} // up to 200 characters,
        autoComplete="off" // no browser autofill.
      />{/* (end of the box) */}
      <Select label="Relationship to the student" name="relationship" required defaultValue="parent">{/* A drop-down of relationship: */}
        <option value="parent">Parent</option>{/* parent, */}
        <option value="guardian">Guardian</option>{/* guardian, */}
        <option value="carer">Carer</option>{/* carer, */}
        <option value="other">Other</option>{/* other. */}
      </Select>{/* End of the drop-down. */}
      <label className="flex items-start gap-2 text-sm">{/* A line holding: */}
        <input type="checkbox" name="can_manage" defaultChecked className="mt-1" />{/* a tick box (ticked to start), */}
        <span>{/* (the words:) */}
          Can change the student&apos;s details and bookings. Untick for someone who should only see progress (for example a
          parent a court order limits).{/* whether they can change details, or only see progress. */}
        </span>{/* (end of the words) */}
      </label>{/* End of the line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LinkParentForm.

// Every student's parents, with a way to remove a link made by mistake.
export function ParentLinkList({ rows }: { rows: ParentLinkRow[] }) {
  if (rows.length === 0) return <Empty>No parent links yet.</Empty>; // None: says so.
  const byStudent = new Map<string, ParentLinkRow[]>(); // The links grouped by student.
  for (const r of rows) byStudent.set(r.student_id, [...(byStudent.get(r.student_id) ?? []), r]); // Adds each link to its student's group.
  return ( // Shows:
    <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
      {[...byStudent.values()].map((links) => ( // for each student:
        <li key={links[0].student_id} className="py-3 first:pt-0 last:pb-0">{/* a list item: */}
          <p className="font-medium">{links[0].student_name}</p>{/* the student's name, */}
          <ul className="mt-1 space-y-2">{/* a list: */}
            {links.map((l) => ( // for each parent:
              <li key={l.parent_id} className="rounded-lg border border-zinc-200 p-3">{/* a bordered box: */}
                <p>{/* a line: */}
                  {l.parent_name} ({l.relationship}{/* the parent's name and relationship, */}
                  {l.can_manage ? "" : ", can only see"}{/* whether they can only see, */}
                  {l.confirmed ? "" : ", waiting for CLG"}){/* and whether CLG still has to confirm. */}
                </p>{/* End of the line. */}
                <details className="mt-1">{/* A section that opens when clicked: */}
                  <summary className="cursor-pointer text-xs text-teal-800 underline">Remove this link</summary>{/* its heading "Remove this link", */}
                  <div className="mt-2">{/* a block: */}
                    <ActionForm action={unlinkParent} submitLabel="Remove link">{/* a form that removes it: */}
                      <input type="hidden" name="parent_id" value={l.parent_id} />{/* which parent (hidden), */}
                      <input type="hidden" name="student_id" value={l.student_id} />{/* which student (hidden), */}
                      <p className="text-xs text-zinc-600">{/* a small note: */}
                        {l.parent_name} will stop seeing {l.student_name}. Their account stays.{/* what removing does. */}
                      </p>{/* End of the note. */}
                    </ActionForm>{/* End of the form. */}
                  </div>{/* End of the block. */}
                </details>{/* End of the section. */}
              </li> // End of the box.
            ))}{/* End of the parents loop. */}
          </ul>{/* End of the list. */}
        </li> // End of the list item.
      ))}{/* End of the students loop. */}
    </ul> // End of the list.
  ); // End of what's shown.
} // End of ParentLinkList.

// Students that look like the same child added twice.
export function DuplicateList({ rows }: { rows: DuplicateRow[] }) {
  if (rows.length === 0) return <Empty>No possible double-ups.</Empty>; // None: says so.
  return ( // Shows:
    <ul className="space-y-4 text-sm">{/* a list: */}
      {rows.map((d) => { // for each pair:
        const older = d.added_at <= d.other_added_at; // true if the first was added first.
        const keep = older // The one to keep (the older):
          ? { id: d.student_id, name: d.full_name } // the first,
          : { id: d.other_student_id, name: d.other_full_name }; // or the second.
        const remove = older // The one to remove (the newer):
          ? { id: d.other_student_id, name: d.other_full_name } // the second,
          : { id: d.student_id, name: d.full_name }; // or the first.
        return ( // Shows:
          <li key={`${d.student_id}-${d.other_student_id}`} className="rounded-xl border border-amber-200 bg-amber-50 p-4">{/* an amber box: */}
            <ol className="list-decimal space-y-1 pl-5">{/* a numbered list: */}
              <li>{/* the first student: */}
                <strong>{d.full_name}</strong>, {born(d.date_of_birth)}. Parents: {d.parents ?? "none"}. Added{" "}{/* name, date of birth, parents, and */}
                {new Date(d.added_at).toLocaleDateString("en-AU")}.{/* when added. */}
              </li>{/* (end of the first) */}
              <li>{/* The second student: */}
                <strong>{d.other_full_name}</strong>, {born(d.other_date_of_birth)}. Parents: {d.other_parents ?? "none"}.
                Added {new Date(d.other_added_at).toLocaleDateString("en-AU")}.{/* when added. */}
              </li>{/* (end of the second) */}
            </ol>{/* End of the list. */}
            <p className="mt-2 text-zinc-700">{/* A line: */}
              If this is the same child, merge them: the older profile is kept, every parent is linked to it, and the
              newer one is deleted. If the older one has no history yet but the newer one does (for example a tutor or
              bookings), keep the newer one instead. Check with the family first if you&apos;re not sure the second adult should see this
              child.{/* what merging does, and when to keep the newer one. */}
            </p>{/* End of the line. */}
            <div className="mt-3 flex flex-wrap gap-4">{/* A row of buttons: */}
              <ActionForm action={mergeStudents} submitLabel="Same child: merge">{/* a form that merges, keeping the older: */}
                <input type="hidden" name="keep" value={keep.id} />{/* (the one to keep) */}
                <input type="hidden" name="remove" value={remove.id} />{/* (the one to remove) */}
              </ActionForm>{/* End of the form. */}
              <ActionForm action={mergeStudents} submitLabel="Same child: keep the newer one">{/* A form that merges, keeping the newer: */}
                <input type="hidden" name="keep" value={remove.id} />{/* (the one to keep) */}
                <input type="hidden" name="remove" value={keep.id} />{/* (the one to remove) */}
              </ActionForm>{/* End of the form. */}
              <ActionForm action={dismissDuplicate} submitLabel="Different children">{/* A form that marks them as different children: */}
                <input type="hidden" name="student_id" value={d.student_id} />{/* (the first) */}
                <input type="hidden" name="other_id" value={d.other_student_id} />{/* (the second) */}
              </ActionForm>{/* End of the form. */}
            </div>{/* End of the row. */}
          </li> // End of the box.
        ); // End of what's shown for this pair.
      })}{/* End of the pairs loop. */}
    </ul> // End of the list.
  ); // End of what's shown.
} // End of DuplicateList.
