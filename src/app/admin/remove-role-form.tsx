// Summary: the owner's form for removing a role or deleting an account.
//
"use client"; // Runs in the browser, so the form can change as choices are made.

import { useState } from "react"; // Lets the form remember the chosen option.
import { removeRoleOrAccount } from "@/app/actions/accounts"; // The server action that does it.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select } from "@/components/ui"; // A labelled input box and a drop-down list.

// Owner only: take away one role, or delete a whole account.
export function RemoveRoleForm() {
  const [what, setWhat] = useState(""); // The chosen option (blank to start).
  return ( // Shows:
    <ActionForm action={removeRoleOrAccount} submitLabel={what === "delete" ? "Delete account permanently" : "Remove role"}>{/* a form, with stronger button words when deleting: */}
      <Field label="Account email" name="email" type="email" required />{/* the account's email, */}
      <Select label="What to do" name="what" required value={what} onChange={(e) => setWhat(e.target.value)}>{/* a drop-down of what to do, remembering the choice: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose…{/* "Choose…", */}
        </option>{/* (end of the option) */}
        <option value="tutor">Remove tutor role (ends tutor access today)</option>{/* remove tutor role, */}
        <option value="admin">Remove admin role</option>{/* remove admin role, */}
        <option value="parent">Remove parent role (they stop seeing their children)</option>{/* remove parent role, */}
        <option value="student">Remove student role (their student record is kept, without the login)</option>{/* remove student role, */}
        <option value="delete">Delete the whole account</option>{/* or delete the whole account. */}
      </Select>{/* End of the drop-down. */}
      {what === "delete" && ( // When deleting:
        <label className="flex items-start gap-2 text-sm">{/* a line holding: */}
          <input type="checkbox" name="with_students" className="mt-1" />{/* a tick box, */}
          <span>Also delete their student records: their own, and any children with no other parent. Use this for test accounts.</span>{/* to also delete their student records. */}
        </label> // End of the line.
      )}{/* End of the deleting extra. */}
      <Field label="Type the person's full name to confirm" name="confirm_name" required autoComplete="off" />{/* The full name typed to confirm. */}
      <p className="text-xs text-zinc-600">{/* A small grey note: */}
        {what === "delete" // when deleting,
          ? "This deletes the login and everything linked to it straight away, and can't be undone. Accounts with billing or session records CLG must keep can't be deleted; remove their roles instead." // that it can't be undone and what can't be deleted,
          : "Removing a role keeps their records, which are deleted later under the usual keeping rules. An account with no roles left is deleted after 12 months unused."}{/* otherwise, that records are kept under the keeping rules. */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of RemoveRoleForm.
