"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { ADMIN_LEVEL_NAMES, requireAdmin, requireAdminLevel } from "@/lib/auth";
import { checkDates } from "@/lib/check-dates";
import { CHECK_KINDS, STATES } from "@/lib/checks";
import { siteUrl } from "@/lib/env";
import type { FormState } from "@/lib/forms";
import { emailIsSetUp, sendEmails } from "@/lib/email/send";
import { createClient } from "@/lib/supabase/server";

// Every action re-checks admin access here, and the database checks again.

const inviteSchema = z.object({
  email: z.email("Enter a valid email address.").trim().toLowerCase(),
  role: z.enum(["tutor", "admin"]),
  // Only used for admins. The database refuses anyone but the owner.
  level: z.enum(["operations", "support", "finance"]).optional(),
});

export async function inviteStaff(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = inviteSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const { email, role } = parsed.data;
  const level = role === "admin" ? (parsed.data.level ?? "operations") : null;

  // Done through the admin's own session, so the database decides whether
  // this admin may invite this role.
  const supabase = await createClient();

  // Someone who already has a CLG account (for example a parent who also
  // tutors) gets the role straight away instead of an invitation.
  const existing = await supabase.rpc("grant_staff_role", { p_email: email, p_role: role, p_level: level });
  if (existing.error) {
    const plain = ["42501", "22023", "23505"].includes(existing.error.code ?? "");
    return { error: plain ? `${existing.error.message}.` : "Couldn't add them. Please try again." };
  }
  if (existing.data === true) {
    revalidatePath("/admin");
    return {
      message: `${email} already had a CLG account, so they are now ${role === "admin" ? `an admin (${ADMIN_LEVEL_NAMES[level ?? "operations"]})` : "a tutor"}. They'll see the new tools next time they sign in, after setting up two-step login.`,
    };
  }

  // Everyone else gets CLG's own invite link: for this email and role only,
  // works once, for 7 days. Joining through it gives the role straight away.
  // A new link replaces any earlier one for the same email.
  const made = await supabase.rpc("create_staff_invite_link", { p_email: email, p_role: role, p_level: level });
  if (made.error || typeof made.data !== "string") {
    const plain = ["42501", "22023", "23505"].includes(made.error?.code ?? "");
    if (made.error) console.error("Invite link failed:", made.error.code, made.error.message);
    return { error: plain && made.error ? `${made.error.message}.` : "Couldn't make the invitation. Please try again." };
  }
  const link = `${siteUrl()}/join?t=${made.data}`;
  revalidatePath("/admin");

  const roleWords = role === "admin" ? `an admin (${ADMIN_LEVEL_NAMES[level ?? "operations"]})` : "a tutor";
  const problem = emailIsSetUp()
    ? await sendEmails([
        {
          id: `staff-invite-${made.data.slice(0, 16)}`,
          email,
          first_name: null,
          subject: `You're invited to join CLG Tutoring as ${roleWords}`,
          body:
            role === "tutor"
              ? "CLG Tutoring has invited you to join the CLG app as a tutor. Use the button to choose your name and password. The link works once, for 7 days. Next you'll set up two-step login and add your checks (Working with Children Check, RRHAN-EC and first aid), which CLG confirms before matching you with students."
              : "CLG Tutoring has invited you to join the CLG app as an admin. Use the button to choose your name and password. The link works once, for 7 days. Next you'll set up two-step login.",
          link: `/join?t=${made.data}`,
          button: "Accept invitation",
          footer: `This invitation is only for ${email}. If you weren't expecting it, you can ignore this email.`,
        },
      ])
    : "Email isn't set up yet.";

  if (problem) {
    console.error("Invitation email failed:", problem);
    return {
      message: `The invitation is ready, but the email couldn't be sent. Copy this link and send it to ${email} yourself (for example by email or Teams). It only works for ${email}, once, for 7 days: ${link}`,
    };
  }
  return {
    message: `Invitation sent to ${email}. The link works once, for 7 days. When they join, they're ${roleWords} straight away. If it gets lost, add them again to send a new link (the old one stops working).`,
  };
}

const cancelSchema = z.object({ id: z.uuid() });

// Cancels an invitation nobody has used yet. Its link stops working.
export async function cancelInvitation(formData: FormData) {
  await requireAdmin();
  const parsed = cancelSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return;
  const supabase = await createClient();
  await supabase.from("invitations").delete().eq("id", parsed.data.id).is("accepted_at", null);
  revalidatePath("/admin");
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
  expires_on: z.union([z.iso.date(), z.literal("")]).optional(),
});

export async function recordCheck(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = checkSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const dates = checkDates(v.kind, v.reference, v.completed_on || undefined, v.expires_on || undefined);
  if ("error" in dates) return dates;
  const expiresOn = dates.expiresOn;

  const supabase = await createClient();
  const { error } = await supabase.from("tutor_checks").insert({
    tutor_id: v.tutor_id,
    kind: v.kind,
    reference: v.reference || null,
    completed_on: v.completed_on || null,
    expires_on: expiresOn,
  });
  if (error) return { error: "Couldn't save the check. Please try again." };

  revalidatePath("/admin");
  return { message: "Check saved and marked as verified by you." };
}

const assignSchema = z.object({
  tutor_id: z.uuid("Choose a tutor and subject."),
  student_id: z.uuid("Choose a student."),
  subject: z.string().trim().min(1, "Enter the subject.").max(100),
});

export async function assignTutor(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const [tutor_id, ...rest] = String(formData.get("pick") ?? "").split("|");
  const parsed = assignSchema.safeParse({
    tutor_id,
    subject: rest.join("|"),
    student_id: formData.get("student_id"),
  });
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

// ---------------------------------------------------------------------------
// Keeping and deleting records (see supabase/migrations/*_retention.sql)
// ---------------------------------------------------------------------------

const holdSchema = z.object({
  target: z.string().regex(/^(student|account):[0-9a-f-]{36}$/, "Choose what to hold."),
  reason: z.string().trim().min(3, "Give a short reason.").max(300),
});

// Stops a student or account being deleted automatically, for example while
// a complaint or child safety matter is open.
export async function placeHold(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = holdSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const [kind, id] = parsed.data.target.split(":");

  const supabase = await createClient();
  const { error } = await supabase
    .from("retention_holds")
    .insert({ [kind === "student" ? "student_id" : "account_id"]: id, reason: parsed.data.reason });
  if (error) return { error: "Couldn't place the hold." };

  revalidatePath("/admin");
  return { message: "Hold placed. These records won't be deleted until it is released." };
}

export async function releaseHold(formData: FormData) {
  await requireAdmin();
  const id = z.uuid().safeParse(formData.get("hold_id"));
  if (!id.success) return;
  const supabase = await createClient();
  await supabase.from("retention_holds").update({ released_at: new Date().toISOString() }).eq("id", id.data);
  revalidatePath("/admin");
}

const tutorLeftSchema = z.object({
  tutor_id: z.uuid("Choose a tutor."),
  ended_on: z.iso.date("Enter the date they finished."),
});

// Marks a tutor as no longer working with CLG. This stops new assignments
// and starts the 7-year clock for their records.
export async function markTutorLeft(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = tutorLeftSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase
    .from("tutor_profiles")
    .update({ active: false, ended_on: parsed.data.ended_on })
    .eq("account_id", parsed.data.tutor_id);
  if (error) return { error: "Couldn't update the tutor." };

  revalidatePath("/admin");
  return { message: "Tutor marked as finished." };
}

const eraseSchema = z.object({
  student_id: z.uuid("Choose a student."),
  confirm_name: z.string().trim().min(1, "Type the student's full name to confirm."),
});

// Deletes a student's records straight away when the family asks. Owner only.
export async function eraseStudent(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = eraseSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.rpc("erase_student", {
    p_student: parsed.data.student_id,
    p_confirm_name: parsed.data.confirm_name,
  });
  if (error) {
    // The database gives a plain reason: wrong name, a hold, or not the owner.
    return { error: error.message || "Couldn't erase the student." };
  }

  revalidatePath("/admin");
  return { message: "The student's records have been deleted." };
}

const periodSchema = z.object({
  kind: z.enum(["student_records", "unused_accounts", "former_tutors", "activity_log"]),
  months: z.coerce.number().int().min(1, "At least 1 month.").max(600),
});

// Changes how long a kind of record is kept. Owner only; the database
// enforces this and logs the change.
export async function setRetentionPeriod(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = periodSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("retention_rules")
    .update({ keep_for: `${parsed.data.months} months` })
    .eq("kind", parsed.data.kind)
    .select("kind");
  if (error || !data?.length) return { error: "Couldn't change the period. Only the owner can do this." };

  revalidatePath("/admin");
  return { message: "Period saved. It applies from tonight's run." };
}

// A tutor's own check entry: confirm it after checking the official record,
// or send it back with a reason the tutor will see.
export async function confirmCheck(formData: FormData) {
  await requireAdmin();
  const id = z.uuid().safeParse(formData.get("check_id"));
  if (!id.success) return;
  const supabase = await createClient();
  await supabase.rpc("confirm_tutor_check", { p_check: id.data });
  revalidatePath("/admin");
}

export async function declineCheck(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z
    .object({ check_id: z.uuid(), reason: z.string().trim().min(3, "Give the tutor a short reason.").max(300) })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("decline_tutor_check", { p_check: parsed.data.check_id, p_reason: parsed.data.reason });
  if (error) return { error: "Couldn't send it back. Please try again." };
  revalidatePath("/admin");
  return { message: "Sent back to the tutor with your reason." };
}

// ---------------------------------------------------------------------------
// Admin levels
// ---------------------------------------------------------------------------

const levelSchema = z.object({
  account_id: z.uuid(),
  level: z.enum(["operations", "support", "finance"], "Choose a level."),
});

// The owner changes another admin's level. The database checks it's the
// owner, and that nobody changes the owner's own level.
export async function setAdminLevel(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = levelSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_admin_level", {
    p_account: parsed.data.account_id,
    p_level: parsed.data.level,
  });
  if (error) {
    const plain = ["42501", "22023"].includes(error.code ?? "");
    return { error: plain ? `${error.message}.` : "Couldn't change the level. Please try again." };
  }
  revalidatePath("/admin");
  return { message: `Level changed to ${ADMIN_LEVEL_NAMES[parsed.data.level]}. It applies the next time they open a page.` };
}

// The owner's (or another admin's) name and email, read with the admin's
// own access, which the database allows for the owner and operations.
async function nameAndEmail(accountId: string) {
  const supabase = await createClient();
  const [account, contact] = await Promise.all([
    supabase.from("accounts").select("full_name").eq("id", accountId).maybeSingle(),
    supabase.from("account_private").select("email").eq("account_id", accountId).maybeSingle(),
  ]);
  return { name: account.data?.full_name ?? "", email: contact.data?.email ?? null };
}

function adelaideTime(iso: string) {
  return new Date(iso).toLocaleString("en-AU", {
    timeZone: "Australia/Adelaide",
    weekday: "long",
    day: "numeric",
    month: "long",
    hour: "numeric",
    minute: "2-digit",
  });
}

const requestSchema = z.object({
  reason: z
    .string()
    .trim()
    .min(10, "Please write why you need owner access (at least 10 characters).")
    .max(1000, "Please keep the reason under 1000 characters."),
});

// An Operations admin asks for emergency owner access. The owner is emailed
// straight away with the reason, and can cancel within 48 hours.
export async function requestEmergencyAccess(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireAdmin();
  const parsed = requestSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const supabase = await createClient();
  const { data: id, error } = await supabase.rpc("request_emergency_owner_access", { p_reason: parsed.data.reason });
  if (error || typeof id !== "string") {
    const plain = ["42501", "22023", "23505"].includes(error?.code ?? "");
    return { error: plain && error ? `${error.message}.` : "Couldn't send the request. Please try again." };
  }
  revalidatePath("/admin");

  const { data: row } = await supabase.from("emergency_owner_access").select("starts_at").eq("id", id).maybeSingle();
  const startsAt = row?.starts_at ? adelaideTime(row.starts_at) : "in 48 hours";
  const { data: owners } = await supabase.from("admin_profiles").select("account_id").eq("level", "owner");
  const ownerContacts = await Promise.all((owners ?? []).map((o) => nameAndEmail(o.account_id)));
  const emails = ownerContacts
    .filter((o) => o.email)
    .map((o) => ({
      id: `emergency-access-${id}-${o.email}`,
      email: o.email as string,
      first_name: o.name.split(" ")[0] || null,
      subject: `${viewer.fullName || "An admin"} has asked for emergency owner access`,
      body: `${viewer.fullName || "An Operations admin"} has asked for owner access to the CLG app because you may be unreachable. Their reason: "${parsed.data.reason}". If you do nothing, they get owner powers from ${startsAt} (Adelaide time) for 7 days. If you don't want this, open the app and press Cancel under Admin > Staff and accounts.`,
      link: "/admin?section=staff",
      button: "Review the request",
      footer: "You get this email because you are the owner of the CLG app.",
    }));
  const problem = emails.length === 0 ? "No owner email found." : emailIsSetUp() ? await sendEmails(emails) : "Email isn't set up yet.";
  if (problem) {
    console.error("Emergency access email failed:", problem);
    return {
      message: `Request sent. The owner will see it in the app, but the email to them couldn't be sent, so please also try to reach them another way. Your access starts ${startsAt} unless they cancel.`,
    };
  }
  return { message: `Request sent and the owner has been emailed. Your access starts ${startsAt} unless they cancel, and lasts 7 days.` };
}

const cancelRequestSchema = z.object({ id: z.uuid() });

// The owner cancels emergency access (or the person who asked withdraws it).
// The person who asked is emailed when someone else cancels it.
export async function cancelEmergencyAccess(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireAdminLevel(["owner", "operations"]);
  const parsed = cancelRequestSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Something went wrong. Please refresh the page." };
  const supabase = await createClient();
  const { data: askedBy, error } = await supabase.rpc("cancel_emergency_owner_access", { p_id: parsed.data.id });
  if (error) {
    const plain = ["42501", "22023"].includes(error.code ?? "");
    return { error: plain ? `${error.message}.` : "Couldn't cancel it. Please try again." };
  }
  revalidatePath("/admin");
  if (typeof askedBy === "string" && askedBy !== viewer.id) {
    const who = await nameAndEmail(askedBy);
    if (who.email && emailIsSetUp()) {
      const problem = await sendEmails([
        {
          id: `emergency-access-cancelled-${parsed.data.id}`,
          email: who.email,
          first_name: who.name.split(" ")[0] || null,
          subject: "Your emergency owner access was cancelled",
          body: `${viewer.fullName || "The owner"} has cancelled your request for emergency owner access in the CLG app. Your own admin access hasn't changed.`,
          link: "/admin",
          button: "Open the app",
        },
      ]);
      if (problem) console.error("Emergency access cancel email failed:", problem);
    }
  }
  return { message: "Emergency owner access cancelled." };
}
