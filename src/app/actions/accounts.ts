// Summary: lets the owner remove one role from an account, or delete the
// account entirely.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireAdminLevel } from "@/lib/auth"; // Makes sure the person is an admin at the right level.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The owner removes one role from an account, or deletes the account. The
// database checks the owner, the typed name, and what must be kept.
// See docs/features/remove-roles-delete-accounts.md.
// The rules for the form:
const schema = z.object({
  email: z.email("Enter the account's email address.").trim().toLowerCase(), // the account's email (tidied to lower case),
  what: z.enum(["admin", "tutor", "parent", "student", "delete"], "Choose what to do."), // what to do: remove one role, or delete,
  confirm_name: z.string().trim().min(1, "Type the person's full name to confirm."), // and the person's full name typed to confirm.
}); // End of the rules.

// Removes a role or deletes an account.
export async function removeRoleOrAccount(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner"]); // Owner only.
  const parsed = schema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const { email, what, confirm_name } = parsed.data; // The checked values.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const lookup = await supabase.rpc("admin_find_account", { p_email: email }); // Looks up the account by email.
  const found = ((lookup.data ?? []) as { account_id: string; full_name: string }[])[0]; // The first match (if any).
  if (lookup.error) return { error: "We couldn't check that email. Please try again." }; // Lookup failed: plain message.
  if (!found) return { error: `No CLG account uses ${email}.` }; // No match: says so.

  const result = // Does the chosen step:
    what === "delete" // if deleting,
      ? await supabase.rpc("admin_delete_account", { // deletes the account:
          p_account: found.account_id, // this account,
          p_confirm_name: confirm_name, // with the typed name as a check,
          p_with_students: formData.get("with_students") === "on", // and their students too, if ticked.
        }) // End of the delete.
      : await supabase.rpc("admin_remove_role", { p_account: found.account_id, p_role: what, p_confirm_name: confirm_name }); // otherwise removes just that role.
  if (result.error) { // It failed:
    console.error("Remove role or account failed:", result.error.code, result.error.message); // notes why in the server log,
    const plain = ["22023", "23514", "42501"].includes(result.error.code ?? ""); // true for the database's own plain refusals,
    return { error: plain ? `${result.error.message}.` : "We couldn't do that. Please try again." }; // shows that message, or a general one.
  } // End of the failure case.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { // Tells the admin:
    message: // (the message)
      what === "delete" // if deleted,
        ? `${found.full_name}'s account has been deleted.` // that the account is gone,
        : `${found.full_name} no longer has the ${what} role. Their records are kept under the usual keeping rules.`, // otherwise which role was removed and that records are kept.
  }; // End of the message.
} // End of removeRoleOrAccount.
