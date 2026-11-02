"use client";

import { cancelEmergencyAccess, requestEmergencyAccess, setAdminLevel } from "@/app/actions/admin";
import { ActionForm } from "@/components/action-form";
import { Select, TextArea } from "@/components/ui";

// The owner changes another admin's level.
export function SetLevelForm({ accountId, level }: { accountId: string; level: string }) {
  return (
    <ActionForm action={setAdminLevel} submitLabel="Save">
      <input type="hidden" name="account_id" value={accountId} />
      <Select label="Level" name="level" defaultValue={level}>
        <option value="operations">Operations</option>
        <option value="support">Support</option>
        <option value="finance">Finance</option>
      </Select>
    </ActionForm>
  );
}

// An Operations admin asks for emergency owner access. A reason is required.
export function EmergencyRequestForm() {
  return (
    <ActionForm action={requestEmergencyAccess} submitLabel="Ask for owner access">
      <p className="text-sm text-zinc-600">
        The owner is emailed straight away with your reason. If they don&apos;t cancel within 48 hr, you get owner
        access for 7 days, then it ends by itself. Everything you do with it is recorded.
      </p>
      <TextArea
        label="Why do you need owner access?"
        name="reason"
        required
        minLength={10}
        maxLength={1000}
        hint="For example: what needs doing, and why the owner can't be reached."
      />
    </ActionForm>
  );
}

// Cancel a request (owner), end running access early (owner), or withdraw
// your own request.
export function EmergencyCancelForm({ id, label }: { id: string; label: string }) {
  return (
    <ActionForm action={cancelEmergencyAccess} submitLabel={label}>
      <input type="hidden" name="id" value={id} />
    </ActionForm>
  );
}
