"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { inviteStaff } from "@/app/actions/admin";
import { requireAdmin, requireAdminLevel } from "@/lib/auth";
import { siteUrl } from "@/lib/env";
import type { FormState } from "@/lib/forms";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

// Staff directory module: job titles, roles and links. Every action checks
// the admin's level here, and the database checks again.

const titleSchema = z.object({
  account_id: z.uuid(),
  job_title: z.string().trim().max(80, "Keep the job title to 80 characters or fewer."),
});

export async function setJobTitle(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = titleSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const { account_id, job_title } = parsed.data;
  if (job_title.length === 1) return { error: "A job title needs at least 2 characters." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("set_staff_job_title", { p_account: account_id, p_title: job_title });
  if (error) {
    const plain = ["42501", "22023"].includes(error.code ?? "");
    return { error: plain ? `${error.message}.` : "Couldn't save the job title. Please try again." };
  }
  revalidatePath("/admin/staff");
  return { message: job_title ? "Saved" : "Removed" };
}

// ---------------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------------

const ROLE_WORDS: Record<string, string> = { tutor: "tutor", admin: "admin", parent: "parent", student: "student" };

const addSchema = z.object({
  account_id: z.uuid(),
  role: z.enum(["tutor", "admin", "parent"], "Choose a role to add."),
  level: z.enum(["operations", "support", "finance"]).optional(),
});

// Owner or operations gives a staff member another role. Only the owner can
// add admins; the database checks this again.
export async function addRole(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = addSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const { account_id, role } = parsed.data;
  const level = role === "admin" ? (parsed.data.level ?? "operations") : null;

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_add_role", { p_account: account_id, p_role: role, p_level: level });
  if (error) {
    const plain = ["42501", "22023", "23505"].includes(error.code ?? "");
    return { error: plain ? `${error.message}.` : "Couldn't add the role. Please try again." };
  }
  revalidatePath("/admin/staff");
  revalidatePath("/admin");
  const extra =
    role === "tutor"
      ? " They'll need confirmed checks before they're matched with students."
      : role === "admin"
        ? " They'll see the admin tools next time they open a page (two-step login needed)."
        : " Any child they add needs an admin to confirm the link.";
  return { message: `Added the ${ROLE_WORDS[role]} role.${extra}` };
}

const removeSchema = z.object({
  account_id: z.uuid(),
  role: z.enum(["tutor", "admin", "parent", "student"], "Choose a role to remove."),
  confirm_name: z.string().trim().min(1, "Type the person's full name to confirm."),
});

// The owner takes away one role. Records are kept under the usual keeping
// rules (see docs/features/remove-roles-delete-accounts.md).
export async function removeRole(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner"]);
  const parsed = removeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const { account_id, role, confirm_name } = parsed.data;

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_remove_role", {
    p_account: account_id,
    p_role: role,
    p_confirm_name: confirm_name,
  });
  if (error) {
    const plain = ["42501", "22023", "23514"].includes(error.code ?? "");
    return { error: plain ? `${error.message}.` : "Couldn't remove the role. Please try again." };
  }
  revalidatePath("/admin/staff");
  revalidatePath("/admin");
  return { message: `Removed the ${ROLE_WORDS[role]} role. Their records are kept under the usual keeping rules.` };
}

// ---------------------------------------------------------------------------
// Links
// ---------------------------------------------------------------------------

const accountSchema = z.object({ account_id: z.uuid() });

// Emails a staff member a link to sign in: a link to choose their password
// if they've never signed in, otherwise a password reset link. If the email
// can't be sent, the admin gets the link to pass on themselves.
export async function sendStaffLoginLink(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = accountSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Something went wrong. Please refresh the page and try again." };

  // Checked with the admin's own access first: only staff in the directory.
  const supabase = await createClient();
  const { data } = await supabase.rpc("staff_directory");
  const person = ((data ?? []) as { account_id: string; full_name: string; email: string | null }[]).find(
    (p) => p.account_id === parsed.data.account_id,
  );
  if (!person) return { error: "That person isn't in the staff directory." };
  if (!person.email) return { error: `We don't have an email for ${person.full_name}.` };
  const email = person.email;

  const admin = createAdminClient();
  const user = await admin.auth.admin.getUserById(person.account_id);
  if (user.error || !user.data.user) return { error: "We couldn't check that account. Please try again." };
  const confirmed = Boolean(user.data.user.email_confirmed_at);
  const neverSignedIn = !user.data.user.last_sign_in_at;
  const redirectTo = `${siteUrl()}/login`;

  const sent = confirmed
    ? await admin.auth.resetPasswordForEmail(email, { redirectTo })
    : await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
  if (!sent.error) {
    return {
      message: neverSignedIn
        ? `We've emailed ${email} a new link to choose a password and sign in.`
        : `We've emailed ${email} a link to set a new password.`,
    };
  }
  console.error("Staff login link email failed:", sent.error.code ?? sent.error.name, sent.error.message);

  const made = await admin.auth.admin.generateLink(
    confirmed ? { type: "recovery", email, options: { redirectTo } } : { type: "invite", email, options: { redirectTo } },
  );
  if (made.error || !made.data.properties?.action_link) {
    console.error("Staff login link failed:", made.error?.code, made.error?.message);
    return { error: "We couldn't make a new link. Please try again." };
  }
  return {
    message: `The email couldn't be sent. Copy this link and send it to ${email} yourself (for example by Teams). It works once, for a short time: ${made.data.properties.action_link}`,
  };
}

const inviteIdSchema = z.object({ id: z.uuid() });

// Sends a new invitation link to someone who hasn't joined yet. Same as
// adding them again under "Add staff": the old link stops working.
export async function resendStaffInvite(prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = inviteIdSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Something went wrong. Please refresh the page and try again." };
  const supabase = await createClient();
  const { data: inv } = await supabase
    .from("invitations")
    .select("email, role, admin_level")
    .eq("id", parsed.data.id)
    .is("accepted_at", null)
    .maybeSingle();
  if (!inv) return { error: "That invitation has been used or cancelled. Refresh the page." };

  const again = new FormData();
  again.set("email", inv.email as string);
  again.set("role", inv.role as string);
  if (inv.role === "admin" && inv.admin_level) again.set("level", inv.admin_level as string);
  const result = await inviteStaff(prev, again);
  revalidatePath("/admin/staff");
  return result;
}
