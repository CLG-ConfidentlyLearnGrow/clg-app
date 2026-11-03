"use client";

import { dismissDuplicate, linkParent, mergeStudents, unlinkParent } from "@/app/actions/parent-links";
import { ActionForm } from "@/components/action-form";
import { Empty, Field, Select } from "@/components/ui";

type StudentOption = { id: string; name: string; born: string | null };

export type ParentLinkRow = {
  student_id: string;
  student_name: string;
  parent_id: string;
  parent_name: string;
  relationship: string;
  can_manage: boolean;
  confirmed: boolean;
};

export type DuplicateRow = {
  student_id: string;
  full_name: string;
  date_of_birth: string | null;
  parents: string | null;
  added_at: string;
  other_student_id: string;
  other_full_name: string;
  other_date_of_birth: string | null;
  other_parents: string | null;
  other_added_at: string;
};

function born(date: string | null) {
  return date ? `born ${new Date(date).toLocaleDateString("en-AU")}` : "no date of birth yet";
}

// Link another parent or guardian to a student already in the app.
export function LinkParentForm({ students }: { students: StudentOption[] }) {
  if (students.length === 0) return <Empty>No students yet.</Empty>;
  return (
    <ActionForm action={linkParent} submitLabel="Link parent">
      <Select label="Student" name="student_id" required defaultValue="">
        <option value="" disabled>
          Choose…
        </option>
        {students.map((s) => (
          <option key={s.id} value={s.id}>
            {s.name} ({born(s.born)})
          </option>
        ))}
      </Select>
      <Field
        label="Parent's or guardian's email"
        name="email"
        type="email"
        required
        hint="If they already have a CLG account (for example they're also a tutor), we use it. If not, we make one and send them a link."
      />
      <Field
        label="Their full name (only needed if they're new to CLG)"
        name="contact_name"
        maxLength={200}
        autoComplete="off"
      />
      <Select label="Relationship to the student" name="relationship" required defaultValue="parent">
        <option value="parent">Parent</option>
        <option value="guardian">Guardian</option>
        <option value="carer">Carer</option>
        <option value="other">Other</option>
      </Select>
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" name="can_manage" defaultChecked className="mt-1" />
        <span>
          Can change the student&apos;s details and bookings. Untick for someone who should only see progress (for example a
          parent a court order limits).
        </span>
      </label>
    </ActionForm>
  );
}

// Every student's parents, with a way to remove a link made by mistake.
export function ParentLinkList({ rows }: { rows: ParentLinkRow[] }) {
  if (rows.length === 0) return <Empty>No parent links yet.</Empty>;
  const byStudent = new Map<string, ParentLinkRow[]>();
  for (const r of rows) byStudent.set(r.student_id, [...(byStudent.get(r.student_id) ?? []), r]);
  return (
    <ul className="divide-y divide-zinc-100 text-sm">
      {[...byStudent.values()].map((links) => (
        <li key={links[0].student_id} className="py-3 first:pt-0 last:pb-0">
          <p className="font-medium">{links[0].student_name}</p>
          <ul className="mt-1 space-y-2">
            {links.map((l) => (
              <li key={l.parent_id} className="rounded-lg border border-zinc-200 p-3">
                <p>
                  {l.parent_name} ({l.relationship}
                  {l.can_manage ? "" : ", can only see"}
                  {l.confirmed ? "" : ", waiting for CLG"})
                </p>
                <details className="mt-1">
                  <summary className="cursor-pointer text-xs text-teal-800 underline">Remove this link</summary>
                  <div className="mt-2">
                    <ActionForm action={unlinkParent} submitLabel="Remove link">
                      <input type="hidden" name="parent_id" value={l.parent_id} />
                      <input type="hidden" name="student_id" value={l.student_id} />
                      <p className="text-xs text-zinc-600">
                        {l.parent_name} will stop seeing {l.student_name}. Their account stays.
                      </p>
                    </ActionForm>
                  </div>
                </details>
              </li>
            ))}
          </ul>
        </li>
      ))}
    </ul>
  );
}

// Students that look like the same child added twice.
export function DuplicateList({ rows }: { rows: DuplicateRow[] }) {
  if (rows.length === 0) return <Empty>No possible double-ups.</Empty>;
  return (
    <ul className="space-y-4 text-sm">
      {rows.map((d) => {
        const older = d.added_at <= d.other_added_at;
        const keep = older
          ? { id: d.student_id, name: d.full_name }
          : { id: d.other_student_id, name: d.other_full_name };
        const remove = older
          ? { id: d.other_student_id, name: d.other_full_name }
          : { id: d.student_id, name: d.full_name };
        return (
          <li key={`${d.student_id}-${d.other_student_id}`} className="rounded-xl border border-amber-200 bg-amber-50 p-4">
            <ol className="list-decimal space-y-1 pl-5">
              <li>
                <strong>{d.full_name}</strong>, {born(d.date_of_birth)}. Parents: {d.parents ?? "none"}. Added{" "}
                {new Date(d.added_at).toLocaleDateString("en-AU")}.
              </li>
              <li>
                <strong>{d.other_full_name}</strong>, {born(d.other_date_of_birth)}. Parents: {d.other_parents ?? "none"}.
                Added {new Date(d.other_added_at).toLocaleDateString("en-AU")}.
              </li>
            </ol>
            <p className="mt-2 text-zinc-700">
              If this is the same child, merge them: the older profile is kept, every parent is linked to it, and the
              newer one is deleted. If the older one has no history yet but the newer one does (for example a tutor or
              bookings), keep the newer one instead. Check with the family first if you&apos;re not sure the second adult should see this
              child.
            </p>
            <div className="mt-3 flex flex-wrap gap-4">
              <ActionForm action={mergeStudents} submitLabel="Same child: merge">
                <input type="hidden" name="keep" value={keep.id} />
                <input type="hidden" name="remove" value={remove.id} />
              </ActionForm>
              <ActionForm action={mergeStudents} submitLabel="Same child: keep the newer one">
                <input type="hidden" name="keep" value={remove.id} />
                <input type="hidden" name="remove" value={keep.id} />
              </ActionForm>
              <ActionForm action={dismissDuplicate} submitLabel="Different children">
                <input type="hidden" name="student_id" value={d.student_id} />
                <input type="hidden" name="other_id" value={d.other_student_id} />
              </ActionForm>
            </div>
          </li>
        );
      })}
    </ul>
  );
}
