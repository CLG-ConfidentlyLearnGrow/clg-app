"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requireAdmin, requireViewer } from "@/lib/auth";
import { childSchema, readSubjects, type Wanted } from "@/lib/child-form";
import { siteUrl } from "@/lib/env";
import { POLICY_VERSION, type FormState } from "@/lib/forms";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

// An admin sets up a family's account for them, for example during a phone
// call or for families already with CLG. The family gets a link to choose
// their password and agrees to the privacy policy and terms when they first
// sign in (see /agree). See docs/features/family-setup.md.

const contactSchema = z.object({
  who: z.enum(["parent", "learner"]),
  contact_name: z.string().trim().min(1, "Enter the parent's or student's full name.").max(200),
  email: z.email("Enter a valid email address.").trim().toLowerCase(),
});

// For a parent's child, an admin only needs the name. Anything else given
// must still be valid; blanks are left for the family.
const blank = z.literal("");
const partialChildSchema = z.object({
  full_name: childSchema.shape.full_name,
  date_of_birth: z.union([blank, childSchema.shape.date_of_birth]).optional(),
  state: z.union([blank, childSchema.shape.state]).optional(),
  year_level: z.union([blank, childSchema.shape.year_level]).optional(),
  school: z.string().trim().max(200).optional(),
  goals: z.string().trim().max(4000, "Please keep the end goal under 4,000 characters.").optional(),
  extra_info: childSchema.shape.extra_info,
});

type Found = { account_id: string; full_name: string; is_parent: boolean; is_student: boolean };
type Made = { userId: string; link: string | null } | { error: string };

// Makes the account and sends the invitation email. Until CLG's own email
// sender is set up, Supabase can't email families, so the admin gets the
// link to send themselves instead.
async function makeAccount(email: string, data: Record<string, string>): Promise<Made> {
  const admin = createAdminClient();
  const redirectTo = `${siteUrl()}/login`;
  const sent = await admin.auth.admin.inviteUserByEmail(email, { data, redirectTo });
  if (!sent.error && sent.data.user) return { userId: sent.data.user.id, link: null };
  if (sent.error) console.error("Family invitation email failed:", sent.error.code ?? sent.error.name, sent.error.message);

  const made = await admin.auth.admin.generateLink({ type: "invite", email, options: { data, redirectTo } });
  if (made.error || !made.data.user || !made.data.properties?.action_link) {
    console.error("Family invitation link failed:", made.error?.code, made.error?.message);
    return { error: "We couldn't make the account. Please check the details and try again." };
  }
  return { userId: made.data.user.id, link: made.data.properties.action_link };
}

function sentText(email: string, link: string | null): string {
  return link
    ? ` The email couldn't be sent, because CLG's own email sender isn't set up yet. Copy this link and send it to ${email} yourself (for example by text or email). It works once, for a short time: ${link}`
    : ` We've emailed ${email} a link to choose a password.`;
}

export async function setUpFamily(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const contact = contactSchema.safeParse(Object.fromEntries(formData));
  if (!contact.success) return { error: contact.error.issues[0].message };
  const { who, contact_name, email } = contact.data;

  // Families set up by an admin may have no subjects yet; they add them later.
  const picked = readSubjects(formData);
  const noneChosen = "error" in picked && picked.error.startsWith("Choose at least one subject");
  if ("error" in picked && !noneChosen) return picked;
  const subjects: Wanted[] = "error" in picked ? [] : picked;

  const supabase = await createClient();
  const lookup = await supabase.rpc("admin_find_account", { p_email: email });
  if (lookup.error) return { error: "We couldn't check that email. Please try again." };
  const found = ((lookup.data ?? []) as Found[])[0];

  if (who === "learner") return setUpLearner(formData, contact_name, email, subjects, found);

  const child = partialChildSchema.safeParse(Object.fromEntries(formData));
  if (!child.success) return { error: child.error.issues[0].message.replace("your child", "the child") };

  let parentId: string;
  let link: string | null = null;
  let isNew = false;
  if (found) {
    if (!found.is_parent) {
      return {
        error: `${email} already has a CLG account, but not as a parent. Ask them to add their child from their own account, or use a different email.`,
      };
    }
    parentId = found.account_id;
  } else {
    const made = await makeAccount(email, { signup_as: "parent", full_name: contact_name });
    if ("error" in made) return made;
    parentId = made.userId;
    link = made.link;
    isNew = true;
  }

  const added = await supabase.rpc("admin_add_child", {
    p_parent: parentId,
    p_full_name: child.data.full_name,
    p_date_of_birth: child.data.date_of_birth || null,
    p_state: child.data.state || null,
    p_year_level: child.data.year_level || null,
    p_school: child.data.school || null,
    p_subjects: subjects,
    p_goals: child.data.goals || null,
    p_extra_info: child.data.extra_info || null,
  });
  if (added.error) {
    console.error("Admin add child failed:", added.error.code, added.error.message);
    const start = isNew ? `The account for ${email} was made, but` : "";
    return {
      error: `${start} we couldn't add ${child.data.full_name}. ${added.error.code === "22023" ? added.error.message + "." : "Please try again."} Adding the child again won't make a second account.`.trim(),
    };
  }

  revalidatePath("/admin");
  if (!isNew) {
    return { message: `${child.data.full_name} has been added to ${found!.full_name}'s account. They'll see it next time they sign in.` };
  }
  return {
    message: `Account made for ${contact_name}, with ${child.data.full_name} added.${sentText(email, link)} To add another child, fill in the form again with the same email.`,
  };
}

const learnerSchema = z.object({
  date_of_birth: z.iso.date("Enter the student's date of birth."),
  state: childSchema.shape.state,
  year_level: childSchema.shape.year_level,
  school: z.string().trim().min(1, "Enter the student's school, university or TAFE.").max(200),
  goals: z.string().trim().max(4000, "Please keep the end goal under 4,000 characters.").optional(),
  extra_info: childSchema.shape.extra_info,
});

async function setUpLearner(
  formData: FormData,
  name: string,
  email: string,
  subjects: Wanted[],
  found: Found | undefined,
): Promise<FormState> {
  if (found) return { error: `${email} already has a CLG account. Use a different email for the student.` };
  const parsed = learnerSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const sixteen = new Date();
  sixteen.setFullYear(sixteen.getFullYear() - 16);
  if (new Date(v.date_of_birth) > sixteen) {
    return { error: "Students under 16 use CLG through a parent's account. Set up the parent instead." };
  }

  const made = await makeAccount(email, {
    signup_as: "learner",
    full_name: name,
    date_of_birth: v.date_of_birth,
    state: v.state,
    year_level: v.year_level,
    school: v.school,
  });
  if ("error" in made) return made;

  // The sign-up made the student record; add what they want help with.
  const supabase = await createClient();
  const student = await supabase
    .from("students")
    .update({ goals: v.goals || null, extra_info: v.extra_info || null })
    .eq("account_id", made.userId)
    .select("id")
    .maybeSingle();
  const saved =
    !student.error &&
    student.data &&
    (subjects.length === 0 ||
      !(
        await supabase
          .from("student_subjects")
          .insert(subjects.map((s) => ({ student_id: student.data!.id, subject: s.subject, working_level: s.level })))
      ).error);

  revalidatePath("/admin");
  const note = saved ? "" : " Their subjects or goal didn't save, so please add them from the student's details.";
  return { message: `Account made for ${name}.${sentText(email, made.link)}${note}` };
}

// Gives a student who is on a parent's account their own login. The student
// keeps their record, history and tutor, and the parent can still see it.
// The database checks the student is 16 or over and the email is new.
const ownLoginSchema = z.object({
  student_id: z.uuid("Choose a student."),
  email: z.email("Enter the student's own email address.").trim().toLowerCase(),
});

export async function giveStudentLogin(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = ownLoginSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const { student_id, email } = parsed.data;

  const supabase = await createClient();
  const offer = await supabase.rpc("admin_offer_student_login", { p_student: student_id, p_email: email });
  if (offer.error) {
    console.error("Student login offer failed:", offer.error.code, offer.error.message);
    return { error: offer.error.code === "22023" ? `${offer.error.message}.` : "We couldn't do that. Please try again." };
  }

  const student = await supabase.from("students").select("full_name").eq("id", student_id).single();
  const name = student.data?.full_name ?? "the student";
  const made = await makeAccount(email, { full_name: name });
  if ("error" in made) {
    await createAdminClient().from("student_login_offers").delete().eq("id", offer.data as string);
    return made;
  }

  revalidatePath("/admin");
  return {
    message: `${name} gets their own login once they use the link.${sentText(email, made.link)} Their parent can still see their details.`,
  };
}

// A family set up by CLG agrees to the privacy policy and terms the first
// time they sign in.
export async function agreeToPolicies(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  if (formData.get("accept") !== "on") return { error: "Please tick the box to agree before carrying on." };
  const supabase = await createClient();
  const { error } = await supabase.from("consent_records").insert([
    { account_id: viewer.id, kind: "privacy_policy", document_version: POLICY_VERSION },
    { account_id: viewer.id, kind: "terms_of_service", document_version: POLICY_VERSION },
  ]);
  if (error) return { error: "We couldn't save that. Please try again." };
  redirect("/dashboard");
}
