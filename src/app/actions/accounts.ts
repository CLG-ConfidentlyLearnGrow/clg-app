"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdminLevel } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// The owner removes one role from an account, or deletes the account. The
// database checks the owner, the typed name, and what must be kept.
// See docs/features/remove-roles-delete-accounts.md.
const schema = z.object({
  email: z.email("Enter the account's email address.").trim().toLowerCase(),
  what: z.enum(["admin", "tutor", "parent", "student", "delete"], "Choose what to do."),
  confirm_name: z.string().trim().min(1, "Type the person's full name to confirm."),
});

export async function removeRoleOrAccount(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner"]);
  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const { email, what, confirm_name } = parsed.data;

  const supabase = await createClient();
  const lookup = await supabase.rpc("admin_find_account", { p_email: email });
  const found = ((lookup.data ?? []) as { account_id: string; full_name: string }[])[0];
  if (lookup.error) return { error: "We couldn't check that email. Please try again." };
  if (!found) return { error: `No CLG account uses ${email}.` };

  const result =
    what === "delete"
      ? await supabase.rpc("admin_delete_account", {
          p_account: found.account_id,
          p_confirm_name: confirm_name,
          p_with_students: formData.get("with_students") === "on",
        })
      : await supabase.rpc("admin_remove_role", { p_account: found.account_id, p_role: what, p_confirm_name: confirm_name });
  if (result.error) {
    console.error("Remove role or account failed:", result.error.code, result.error.message);
    const plain = ["22023", "23514", "42501"].includes(result.error.code ?? "");
    return { error: plain ? `${result.error.message}.` : "We couldn't do that. Please try again." };
  }

  revalidatePath("/admin");
  return {
    message:
      what === "delete"
        ? `${found.full_name}'s account has been deleted.`
        : `${found.full_name} no longer has the ${what} role. Their records are kept under the usual keeping rules.`,
  };
}
