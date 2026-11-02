"use client";

import { useState } from "react";
import { removeRoleOrAccount } from "@/app/actions/accounts";
import { ActionForm } from "@/components/action-form";
import { Field, Select } from "@/components/ui";

// Owner only: take away one role, or delete a whole account.
export function RemoveRoleForm() {
  const [what, setWhat] = useState("");
  return (
    <ActionForm action={removeRoleOrAccount} submitLabel={what === "delete" ? "Delete account permanently" : "Remove role"}>
      <Field label="Account email" name="email" type="email" required />
      <Select label="What to do" name="what" required value={what} onChange={(e) => setWhat(e.target.value)}>
        <option value="" disabled>
          Choose…
        </option>
        <option value="tutor">Remove tutor role (ends tutor access today)</option>
        <option value="admin">Remove admin role</option>
        <option value="parent">Remove parent role (they stop seeing their children)</option>
        <option value="student">Remove student role (their student record is kept, without the login)</option>
        <option value="delete">Delete the whole account</option>
      </Select>
      {what === "delete" && (
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" name="with_students" className="mt-1" />
          <span>Also delete their student records: their own, and any children with no other parent. Use this for test accounts.</span>
        </label>
      )}
      <Field label="Type the person's full name to confirm" name="confirm_name" required autoComplete="off" />
      <p className="text-xs text-zinc-600">
        {what === "delete"
          ? "This deletes the login and everything linked to it straight away, and can't be undone. Accounts with billing or session records CLG must keep can't be deleted; remove their roles instead."
          : "Removing a role keeps their records, which are deleted later under the usual keeping rules. An account with no roles left is deleted after 12 months unused."}
      </p>
    </ActionForm>
  );
}
