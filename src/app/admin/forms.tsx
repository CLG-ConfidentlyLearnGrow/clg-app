"use client";

import { assignTutor, inviteStaff, recordCheck, setTutorWorkState, unlockAccount } from "@/app/actions/admin";
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
    <ActionForm action={inviteStaff} submitLabel="Send invitation">
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
      <Field label="Card or registration number (not needed for RRHAN-EC)" name="reference" maxLength={100} />
      <Field label="Completed on (optional)" name="completed_on" type="date" />
      <Field label="Expires on" name="expires_on" type="date" required />
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
