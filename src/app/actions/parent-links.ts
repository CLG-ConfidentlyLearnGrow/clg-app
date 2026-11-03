"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { FRONT_DESK, requireAdminLevel } from "@/lib/auth";
import { makeAccount, sentText } from "@/lib/family-invite";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// CLG links more than one parent or guardian to a student, removes a link,
// and sorts out double-ups (the same child added twice).
// The database checks who may do each of these. See docs/features/link-parents.md.

const RELATIONSHIPS = ["parent", "guardian", "carer", "other"] as const;

const linkSchema = z.object({
  student_id: z.uuid("Choose a student."),
  email: z.email("Enter the parent's email address.").trim().toLowerCase(),
  contact_name: z.string().trim().max(200).optional(),
  relationship: z.enum(RELATIONSHIPS, "Choose how they're related to the student."),
});

type Found = { account_id: string; full_name: string; is_parent: boolean; is_student: boolean };

// Plain words for the database's own error messages.
function plain(error: { code?: string; message: string }, fallback: string) {
  return error.code === "22023" ? `${error.message}.` : fallback;
}

export async function linkParent(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FRONT_DESK);
  const parsed = linkSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const canManage = formData.get("can_manage") === "on";

  const supabase = await createClient();
  const lookup = await supabase.rpc("admin_find_account", { p_email: v.email });
  if (lookup.error) return { error: "We couldn't check that email. Please try again." };
  const found = ((lookup.data ?? []) as Found[])[0];

  let parentId: string;
  let parentName: string;
  let link: string | null = null;
  let isNew = false;
  if (found) {
    parentId = found.account_id;
    parentName = found.full_name;
  } else {
    if (!v.contact_name) {
      return { error: `No one uses ${v.email} for CLG yet. Enter the parent's full name too, and we'll make their account.` };
    }
    const made = await makeAccount(v.email, { signup_as: "parent", full_name: v.contact_name });
    if ("error" in made) return made;
    parentId = made.userId;
    parentName = v.contact_name;
    link = made.link;
    isNew = true;
  }

  const res = await supabase.rpc("admin_link_parent", {
    p_parent: parentId,
    p_student: v.student_id,
    p_relationship: v.relationship,
    p_can_manage: canManage,
  });
  if (res.error) {
    console.error("Linking a parent failed:", res.error.code, res.error.message);
    const start = isNew ? `The account for ${v.email} was made, but` : "";
    return { error: `${start} we couldn't link them. ${plain(res.error, "Please try again.")}`.trim() };
  }

  revalidatePath("/admin");
  return {
    message: isNew
      ? `Account made for ${parentName} and linked to the student.${sentText(v.email, link)}`
      : `${parentName} is now linked to the student. They'll see them next time they sign in.`,
  };
}

const pairSchema = z.object({ parent_id: z.uuid(), student_id: z.uuid() });

export async function unlinkParent(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FRONT_DESK);
  const parsed = pairSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Something went wrong. Please refresh and try again." };
  const supabase = await createClient();
  const res = await supabase.rpc("admin_unlink_parent", {
    p_parent: parsed.data.parent_id,
    p_student: parsed.data.student_id,
  });
  if (res.error) return { error: plain(res.error, "We couldn't remove the link. Please try again.") };
  revalidatePath("/admin");
  return { message: "Link removed. They no longer see this student." };
}

const mergeSchema = z.object({ keep: z.uuid(), remove: z.uuid() });

export async function mergeStudents(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FRONT_DESK);
  const parsed = mergeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Something went wrong. Please refresh and try again." };
  const supabase = await createClient();
  const res = await supabase.rpc("admin_merge_students", { p_keep: parsed.data.keep, p_remove: parsed.data.remove });
  if (res.error) {
    console.error("Merging students failed:", res.error.code, res.error.message);
    return { error: plain(res.error, "We couldn't merge them. Please try again.") };
  }
  revalidatePath("/admin");
  return { message: "Merged. Every parent now sees the one profile." };
}

const dismissSchema = z.object({ student_id: z.uuid(), other_id: z.uuid() });

export async function dismissDuplicate(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FRONT_DESK);
  const parsed = dismissSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Something went wrong. Please refresh and try again." };
  const supabase = await createClient();
  const res = await supabase.rpc("admin_dismiss_duplicate", {
    p_student: parsed.data.student_id,
    p_other: parsed.data.other_id,
  });
  if (res.error) return { error: "We couldn't save that. Please try again." };
  revalidatePath("/admin");
  return { message: "Noted as different children. They won't be flagged again." };
}
