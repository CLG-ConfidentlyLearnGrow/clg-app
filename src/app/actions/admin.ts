"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth";
import { CHECK_KINDS, NEEDS_REFERENCE, STATES } from "@/lib/checks";
import { siteUrl } from "@/lib/env";
import type { FormState } from "@/lib/forms";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

// Every action re-checks admin access here, and the database checks again.

const inviteSchema = z.object({
  email: z.email("Enter a valid email address.").trim().toLowerCase(),
  role: z.enum(["tutor", "admin"]),
});

export async function inviteStaff(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireAdmin();
  const parsed = inviteSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const { email, role } = parsed.data;

  // Recorded through the admin's own session, so the database decides
  // whether this admin may invite this role.
  const supabase = await createClient();
  const invitation = await supabase
    .from("invitations")
    .insert({ email, role, invited_by: viewer.id })
    .select("id")
    .single();
  if (invitation.error) {
    return { error: "Couldn't create the invitation. They may already be invited, or only the owner can invite admins." };
  }

  const sent = await createAdminClient().auth.admin.inviteUserByEmail(email, {
    redirectTo: `${siteUrl()}/auth/confirm?next=/set-password`,
  });
  if (sent.error) {
    await supabase.from("invitations").delete().eq("id", invitation.data.id);
    return { error: "The invitation email couldn't be sent. They may already have an account." };
  }

  revalidatePath("/admin");
  return { message: `Invitation sent to ${email}.` };
}

export async function verifyParentLink(formData: FormData) {
  await requireAdmin();
  const ids = z
    .object({ parent_id: z.uuid(), student_id: z.uuid() })
    .safeParse(Object.fromEntries(formData));
  if (!ids.success) return;

  const supabase = await createClient();
  await supabase
    .from("parent_student_links")
    .update({ verified_at: new Date().toISOString() })
    .eq("parent_id", ids.data.parent_id)
    .eq("student_id", ids.data.student_id);
  revalidatePath("/admin");
}

const checkSchema = z.object({
  tutor_id: z.uuid("Choose a tutor."),
  kind: z.enum(CHECK_KINDS),
  reference: z.string().trim().max(100).optional(),
  completed_on: z.union([z.iso.date(), z.literal("")]).optional(),
  expires_on: z.iso.date("Enter the expiry date."),
});

export async function recordCheck(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = checkSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  if (NEEDS_REFERENCE.has(v.kind) && !v.reference) return { error: "Enter the card or registration number." };
  if (new Date(v.expires_on) < new Date()) return { error: "That check has already expired." };

  const supabase = await createClient();
  const { error } = await supabase.from("tutor_checks").insert({
    tutor_id: v.tutor_id,
    kind: v.kind,
    reference: v.reference || null,
    completed_on: v.completed_on || null,
    expires_on: v.expires_on,
  });
  if (error) return { error: "Couldn't save the check. Please try again." };

  revalidatePath("/admin");
  return { message: "Check saved and marked as verified by you." };
}

const assignSchema = z.object({
  tutor_id: z.uuid("Choose a tutor."),
  student_id: z.uuid("Choose a student."),
  subject: z.string().trim().min(1, "Enter the subject.").max(100),
});

export async function assignTutor(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = assignSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.from("tutor_assignments").insert(parsed.data);
  // The database explains why an assignment isn't allowed (checks missing,
  // parent link not yet verified).
  if (error) return { error: error.code === "23514" ? error.message : "Couldn't assign the tutor." };

  revalidatePath("/admin");
  return { message: "Tutor assigned." };
}

export async function unlockAccount(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z.email().trim().toLowerCase().safeParse(formData.get("email"));
  if (!parsed.success) return { error: "Enter a valid email address." };

  const supabase = await createClient();
  const account = await supabase
    .from("account_private")
    .select("account_id")
    .eq("email", parsed.data)
    .maybeSingle();
  if (!account.data) return { error: "No account with that email." };

  const { error } = await supabase.rpc("admin_unlock_account", { p_account: account.data.account_id });
  if (error) return { error: "Couldn't unlock the account." };
  return { message: "Account unlocked." };
}

const workStateSchema = z.object({
  tutor_id: z.uuid("Choose a tutor."),
  work_state: z.union([z.enum(STATES), z.literal("")]),
});

// The state a tutor works from adds that state's check to what they need.
export async function setTutorWorkState(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = workStateSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase
    .from("tutor_work_settings")
    .update({ work_state: parsed.data.work_state || null })
    .eq("tutor_id", parsed.data.tutor_id);
  if (error) return { error: "Couldn't save the tutor's work state." };

  revalidatePath("/admin");
  return { message: "Work state saved." };
}
