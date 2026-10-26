"use client";

import { assignTutor, inviteStaff, recordCheck, unlockAccount } from "@/app/actions/admin";
import { ActionForm } from "@/components/action-form";
import { Field, Select } from "@/components/ui";

type Option = { id: string; name: string };

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
      <Select label="Tutor" name="tutor_id" required defaultValue="">
        <option value="" disabled>Choose…</option>
        {tutors.map((t) => (
          <option key={t.id} value={t.id}>{t.name}</option>
        ))}
      </Select>
      <Select label="Check" name="kind" defaultValue="wwcc">
        <option value="wwcc">Working With Children Check</option>
        <option value="rrhan_ec_fundamentals">RRHAN-EC Fundamentals</option>
        <option value="rrhan_ec_masterclass">RRHAN-EC Masterclass</option>
      </Select>
      <Field label="Number (required for WWCC)" name="reference" maxLength={100} />
      <Field label="Completed on (optional)" name="completed_on" type="date" />
      <Field label="Expires on" name="expires_on" type="date" required />
      <p className="text-xs text-zinc-500">
        Only save a check after confirming it on the official screening or training record.
      </p>
    </ActionForm>
  );
}

export function AssignForm({ tutors, students }: { tutors: Option[]; students: Option[] }) {
  return (
    <ActionForm action={assignTutor} submitLabel="Assign tutor">
      <Select label="Tutor" name="tutor_id" required defaultValue="">
        <option value="" disabled>Choose…</option>
        {tutors.map((t) => (
          <option key={t.id} value={t.id}>{t.name}</option>
        ))}
      </Select>
      <Select label="Student" name="student_id" required defaultValue="">
        <option value="" disabled>Choose…</option>
        {students.map((s) => (
          <option key={s.id} value={s.id}>{s.name}</option>
        ))}
      </Select>
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
