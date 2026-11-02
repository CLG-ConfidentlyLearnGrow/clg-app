"use client";

import { cancelEmergencyAccess, requestEmergencyAccess, setAdminLevel } from "@/app/actions/admin";
import { useActionState } from "react";
import { ActionForm } from "@/components/action-form";
import { initialFormState } from "@/lib/forms";
import { TextArea } from "@/components/ui";

// A short label for an admin level, for example in the staff list.
export function LevelBadge({ level }: { level: string }) {
  const names: Record<string, string> = { owner: "Owner", operations: "Operations", support: "Support", finance: "Finance" };
  return (
    <span className="inline-block rounded-full bg-zinc-100 px-2.5 py-0.5 text-xs font-medium text-zinc-800">
      {names[level] ?? level}
    </span>
  );
}

// The owner changes another admin's level: one small dropdown that saves
// as soon as a level is picked, with a one-word note.
export function SetLevelForm({ accountId, level }: { accountId: string; level: string }) {
  const [state, formAction, pending] = useActionState(setAdminLevel, initialFormState);
  return (
    <form action={formAction} className="flex items-center gap-2">
      <input type="hidden" name="account_id" value={accountId} />
      <select
        name="level"
        defaultValue={level}
        aria-label="Admin level"
        disabled={pending}
        onChange={(e) => e.currentTarget.form?.requestSubmit()}
        className="rounded-full border border-zinc-300 bg-white px-2.5 py-1 text-xs font-medium shadow-sm focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"
      >
        <option value="operations">Operations</option>
        <option value="support">Support</option>
        <option value="finance">Finance</option>
      </select>
      {pending ? (
        <span className="text-xs text-zinc-500">Saving…</span>
      ) : state.error ? (
        <span role="alert" className="text-xs text-red-700">
          {state.error}
        </span>
      ) : state.message ? (
        <span role="status" className="text-xs text-teal-800">
          Saved
        </span>
      ) : null}
    </form>
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
