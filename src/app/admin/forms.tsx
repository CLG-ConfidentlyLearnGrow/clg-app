"use client";

import {
  assignTutor,
  eraseStudent,
  inviteStaff,
  markTutorLeft,
  placeHold,
  recordCheck,
  setRetentionPeriod,
  setTutorWorkState,
  unlockAccount,
} from "@/app/actions/admin";
import { ActionForm } from "@/components/action-form";
import { Field, Select } from "@/components/ui";
import { CHECK_KINDS, CHECK_NAMES, STATES, STATE_NAMES } from "@/lib/checks";

type Option = { id: string; name: string };

function TutorSelect({ tutors }: { tutors: Option[] }) {
  return (
    <Select label="Tutor" name="tutor_id" required defaultValue="">
      <option value="" disabled>
        Choose…
      </option>
      {tutors.map((t) => (
        <option key={t.id} value={t.id}>
          {t.name}
        </option>
      ))}
    </Select>
  );
}

export function InviteForm({ canInviteAdmins }: { canInviteAdmins: boolean }) {
  return (
    <ActionForm action={inviteStaff} submitLabel="Add">
      <p className="text-sm text-zinc-600">
        New people get an invitation email. If the email already has a CLG account (for example a parent, or you),
        the role is added to that account straight away.
      </p>
      <Field label="Email" name="email" type="email" required />
      <Select label="Role" name="role" defaultValue="tutor">
        <option value="tutor">Tutor</option>
        {canInviteAdmins && <option value="admin">Admin</option>}
      </Select>
    </ActionForm>
  );
}

export function CheckForm({ tutors }: { tutors: Option[] }) {
  return (
    <ActionForm action={recordCheck} submitLabel="Save check">
      <TutorSelect tutors={tutors} />
      <Select label="Check" name="kind" defaultValue="wwcc_sa">
        {CHECK_KINDS.map((k) => (
          <option key={k} value={k}>
            {CHECK_NAMES[k]}
          </option>
        ))}
      </Select>
      <Field label="Card, registration or certificate number (not needed for RRHAN-EC)" name="reference" maxLength={100} />
      <Field
        label="Completed or issued on"
        name="completed_on"
        type="date"
        hint="Required for a police check: it counts for 5 years from this date."
      />
      <Field
        label="Expires on"
        name="expires_on"
        type="date"
        hint="Leave blank for a police check. The app works it out."
      />
      <p className="text-xs text-zinc-500">
        Only save a check after confirming it on the official screening or training record.
      </p>
    </ActionForm>
  );
}

export function WorkStateForm({ tutors }: { tutors: Option[] }) {
  return (
    <ActionForm action={setTutorWorkState} submitLabel="Save">
      <TutorSelect tutors={tutors} />
      <Select label="State the tutor works from" name="work_state" defaultValue="">
        <option value="">Not set</option>
        {STATES.map((s) => (
          <option key={s} value={s}>
            {STATE_NAMES[s]}
          </option>
        ))}
      </Select>
      <p className="text-xs text-zinc-500">The tutor will also need that state&apos;s check.</p>
    </ActionForm>
  );
}

export function AssignForm({ studentId, tutors }: { studentId: string; tutors: Option[] }) {
  return (
    <ActionForm action={assignTutor} submitLabel="Assign tutor">
      <input type="hidden" name="student_id" value={studentId} />
      <TutorSelect tutors={tutors} />
      <Field label="Subject" name="subject" required maxLength={100} />
    </ActionForm>
  );
}

export function UnlockForm() {
  return (
    <ActionForm action={unlockAccount} submitLabel="Unlock">
      <Field label="Email of locked account" name="email" type="email" required />
    </ActionForm>
  );
}

export function HoldForm({ due }: { due: { value: string; label: string }[] }) {
  return (
    <ActionForm action={placeHold} submitLabel="Place hold">
      <Select label="Keep these records" name="target" required defaultValue="">
        <option value="" disabled>
          Choose…
        </option>
        {due.map((d) => (
          <option key={d.value} value={d.value}>
            {d.label}
          </option>
        ))}
      </Select>
      <Field
        label="Reason"
        name="reason"
        required
        maxLength={300}
        hint="Keep it general, such as 'open complaint'. Concern details belong in the child safety record."
      />
    </ActionForm>
  );
}

export function TutorLeftForm({ tutors }: { tutors: Option[] }) {
  return (
    <ActionForm action={markTutorLeft} submitLabel="Mark as finished">
      <TutorSelect tutors={tutors} />
      <Field label="Last day with CLG" name="ended_on" type="date" required />
      <p className="text-xs text-zinc-500">
        They can no longer be assigned students. Their records are deleted 7 years after this date.
      </p>
    </ActionForm>
  );
}

export function EraseStudentForm({ students }: { students: Option[] }) {
  return (
    <ActionForm action={eraseStudent} submitLabel="Delete permanently">
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
      <Field label="Type the student's full name to confirm" name="confirm_name" required autoComplete="off" />
      <p className="text-xs text-red-700">
        This deletes the student, their learning needs, links and enrolments straight away. It cannot be undone.
      </p>
    </ActionForm>
  );
}

export function RetentionPeriodForm({ rules }: { rules: { kind: string; label: string }[] }) {
  return (
    <ActionForm action={setRetentionPeriod} submitLabel="Save period">
      <Select label="Records" name="kind" defaultValue={rules[0]?.kind}>
        {rules.map((r) => (
          <option key={r.kind} value={r.kind}>
            {r.label}
          </option>
        ))}
      </Select>
      <Field label="Keep for (months)" name="months" type="number" min={1} max={600} required />
      <p className="text-xs text-zinc-500">Check with your lawyer before shortening any period.</p>
    </ActionForm>
  );
}
