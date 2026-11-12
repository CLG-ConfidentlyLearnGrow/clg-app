// Summary: an admin sets up a family's account for them (parent with child,
// or a student 16+), gives a student their own login, or sends a fresh
// password link; families agree to the policies the first time they sign in.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { redirect } from "next/navigation"; // Lets the code send someone to another page.
import { z } from "zod"; // The form-checking library.
import { FRONT_DESK, requireAdminLevel, requireViewer } from "@/lib/auth"; // The front-desk group, and the sign-in and admin-level checks.
import { childSchema, readSubjects, type Wanted } from "@/lib/child-form"; // The child form rules, reading the chosen subjects, and a subject's shape.
import { saveStudyDetails } from "@/lib/study-details"; // Saves a university or TAFE student's degree and unit details.
import { siteUrl } from "@/lib/env"; // The app's web address, for links in emails.
import { POLICY_VERSION, type FormState } from "@/lib/forms"; // The policy version, and the form reply shape.
import { makeAccount, sentText } from "@/lib/family-invite"; // Makes a family account and words the "sent" message.
import { createAdminClient } from "@/lib/supabase/admin"; // The all-powerful database helper (secret key).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// An admin sets up a family's account for them, for example during a phone
// call or for families already with CLG. The family gets a link to choose
// their password and agrees to the privacy policy and terms when they first
// sign in (see /agree). See docs/features/family-setup.md.

// The rules for the contact part of the form:
const contactSchema = z.object({
  who: z.enum(["parent", "learner"]), // setting up a parent or a learner,
  contact_name: z.string().trim().min(1, "Enter the parent's or student's full name.").max(200), // their full name,
  email: z.email("Enter a valid email address.").trim().toLowerCase(), // their email (tidied to lower case).
}); // End of the rules.

// For a parent's child, an admin only needs the name. Anything else given
// must still be valid; blanks are left for the family.
const blank = z.literal(""); // A field left blank.
const partialChildSchema = z.object({ // The rules for a child set up by an admin:
  full_name: childSchema.shape.full_name, // name (required),
  date_of_birth: z.union([blank, childSchema.shape.date_of_birth]).optional(), // date of birth (blank or a real date),
  state: z.union([blank, childSchema.shape.state]).optional(), // state (blank or from the list),
  year_level: z.union([blank, childSchema.shape.year_level]).optional(), // year level (blank or from the list),
  school: z.string().trim().max(200).optional(), // school (optional),
  goals: z.string().trim().max(4000, "Please keep the end goal under 4,000 characters.").optional(), // end goal (optional),
  extra_info: childSchema.shape.extra_info, // other information,
  learning_needs: childSchema.shape.learning_needs, // learning needs,
  program: childSchema.shape.program, // degree or course.
}); // End of the rules.

type Found = { account_id: string; full_name: string; is_parent: boolean; is_student: boolean }; // One account found by email: id, name, and whether they're a parent or student.
export async function setUpFamily(_prev: FormState, formData: FormData): Promise<FormState> { // Sets up a family (or a student) from the admin form.
  await requireAdminLevel(FRONT_DESK); // Front desk admins and above.
  const contact = contactSchema.safeParse(Object.fromEntries(formData)); // Checks the contact details.
  if (!contact.success) return { error: contact.error.issues[0].message }; // Shows the first rule that failed.
  const { who, contact_name, email } = contact.data; // The checked values.

  // Families set up by an admin may have no subjects yet; they add them later.
  const picked = readSubjects(formData); // Reads the chosen subjects.
  const noneChosen = "error" in picked && picked.error.startsWith("Choose at least one subject"); // True if the only problem is "no subjects chosen".
  if ("error" in picked && !noneChosen) return picked; // Any other subject problem: shows it.
  const subjects: Wanted[] = "error" in picked ? [] : picked; // The subjects (none if none were chosen).

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const lookup = await supabase.rpc("admin_find_account", { p_email: email }); // Looks up the email.
  if (lookup.error) return { error: "We couldn't check that email. Please try again." }; // Lookup failed: plain message.
  const found = ((lookup.data ?? []) as Found[])[0]; // The first match (if any).

  if (who === "learner") return setUpLearner(formData, contact_name, email, subjects, found); // Students 16+ are set up separately.

  const child = partialChildSchema.safeParse(Object.fromEntries(formData)); // Checks the child's details.
  if (!child.success) return { error: child.error.issues[0].message.replace("your child", "the child") }; // Shows the first problem, worded for an admin.

  let parentId: string; // The parent's account id.
  let link: string | null = null; // The invite link to send by hand, if the email failed.
  let isNew = false; // Whether a new account was made.
  if (found) { // The email already has an account:
    if (!found.is_parent) { // but not as a parent:
      return { // explains:
        error: `${email} already has a CLG account, but not as a parent. Ask them to add their child from their own account, or use a different email.`, // (the message)
      }; // End of the message.
    } // End of that case.
    parentId = found.account_id; // Uses the existing parent account.
  } else { // No account yet:
    const made = await makeAccount(email, { signup_as: "parent", full_name: contact_name }); // makes one and sends the invitation.
    if ("error" in made) return made; // Failed: passes on the message.
    parentId = made.userId; // The new account's id.
    link = made.link; // Any link to send by hand.
    isNew = true; // Marks it as new.
  } // End of the account step.

  const added = await supabase.rpc("admin_add_child", { // Asks the database to add the child:
    p_parent: parentId, // to this parent,
    p_full_name: child.data.full_name, // name,
    p_date_of_birth: child.data.date_of_birth || null, // date of birth (or none),
    p_state: child.data.state || null, // state (or none),
    p_year_level: child.data.year_level || null, // year level (or none),
    p_school: child.data.school || null, // school (or none),
    p_subjects: subjects, // subjects,
    p_goals: child.data.goals || null, // end goal (or none),
    p_extra_info: child.data.extra_info || null, // other information (or none).
  }); // End of the request.
  if (added.error) { // It failed:
    console.error("Admin add child failed:", added.error.code, added.error.message); // notes why in the server log,
    const start = isNew ? `The account for ${email} was made, but` : ""; // mentions the account was made, if it was,
    return { // and explains:
      error: `${start} we couldn't add ${child.data.full_name}. ${added.error.code === "22023" ? added.error.message + "." : "Please try again."} Adding the child again won't make a second account.`.trim(), // (the message)
    }; // End of the message.
  } // End of the failure case.

  if (typeof added.data === "string") { // The child was added:
    if (child.data.learning_needs) { // learning needs were given:
      await supabase.from("students").update({ learning_needs: child.data.learning_needs }).eq("id", added.data); // saves them.
    } // End of learning needs.
    await saveStudyDetails(supabase, added.data, child.data.program, subjects); // Saves degree and unit details.
  } // End of the extras.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  if (!isNew) { // Existing parent:
    return { message: `${child.data.full_name} has been added to ${found!.full_name}'s account. They'll see it next time they sign in.` }; // says the child was added to their account.
  } // End of that case.
  return { // New parent:
    message: `Account made for ${contact_name}, with ${child.data.full_name} added.${sentText(email, link)} To add another child, fill in the form again with the same email.`, // says the account was made, how the invite was sent, and how to add another child.
  }; // End of the message.
} // End of setUpFamily.

// The rules for a student 16+ set up by an admin:
const learnerSchema = z.object({
  date_of_birth: z.iso.date("Enter the student's date of birth."), // date of birth (a real date),
  state: childSchema.shape.state, // state,
  year_level: childSchema.shape.year_level, // year level,
  school: z.string().trim().min(1, "Enter the student's school, university or TAFE.").max(200), // school, university or TAFE (required),
  goals: z.string().trim().max(4000, "Please keep the end goal under 4,000 characters.").optional(), // end goal (optional),
  extra_info: childSchema.shape.extra_info, // other information,
  learning_needs: childSchema.shape.learning_needs, // learning needs,
  program: childSchema.shape.program, // degree or course.
}); // End of the rules.

// Sets up a student aged 16 or over with their own account.
async function setUpLearner(
  formData: FormData, // The form's data.
  name: string, // Their name.
  email: string, // Their email.
  subjects: Wanted[], // Their chosen subjects.
  found: Found | undefined, // Any account already using the email.
): Promise<FormState> { // (the result shape)
  if (found) return { error: `${email} already has a CLG account. Use a different email for the student.` }; // Email already used: asks for a different one.
  const parsed = learnerSchema.safeParse(Object.fromEntries(formData)); // Checks the student's details.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const sixteen = new Date(); // Today,
  sixteen.setFullYear(sixteen.getFullYear() - 16); // moved back 16 years.
  if (new Date(v.date_of_birth) > sixteen) { // Born after that (under 16):
    return { error: "Students under 16 use CLG through a parent's account. Set up the parent instead." }; // explains they use a parent's account.
  } // End of the age check.

  const made = await makeAccount(email, { // Makes their account and sends the invitation:
    signup_as: "learner", // as a learner,
    full_name: name, // name,
    date_of_birth: v.date_of_birth, // date of birth,
    state: v.state, // state,
    year_level: v.year_level, // year level,
    school: v.school, // school.
  }); // End of the details.
  if ("error" in made) return made; // Failed: passes on the message.

  // The sign-up made the student record; add what they want help with.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const student = await supabase // Saves the student's extra details:
    .from("students") // in the students table,
    .update({ // the changes:
      goals: v.goals || null, // end goal (or none),
      extra_info: v.extra_info || null, // other information (or none),
      learning_needs: v.learning_needs || null, // learning needs (or none),
      program: v.program || null, // degree or course (or none).
    }) // End of the changes.
    .eq("account_id", made.userId) // for the student linked to the new account,
    .select("id") // and gets back its id,
    .maybeSingle(); // (one at most).
  const saved = // True if everything saved:
    !student.error && // the update worked,
    student.data && // a student was found,
    (subjects.length === 0 || // and either no subjects,
      !( // or the subjects saved without error:
        await supabase // (saving them:)
          .from("student_subjects") // in the student subjects table,
          .insert( // adding:
            subjects.map((s) => ({ // one row per subject:
              student_id: student.data!.id, // for this student,
              subject: s.subject, // name,
              working_level: s.level, // level,
              course_code: s.course_code || null, // unit code (or none),
              course_url: s.course_url || null, // unit link (or none).
            })), // (end of the rows)
          ) // (end of the insert)
      ).error); // (no error means saved)

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  const note = saved ? "" : " Their subjects or goal didn't save, so please add them from the student's details."; // A note if anything didn't save.
  return { message: `Account made for ${name}.${sentText(email, made.link)}${note}` }; // Says the account was made, how the invite was sent, and any note.
} // End of setUpLearner.

// Gives a student who is on a parent's account their own login. The student
// keeps their record, history and tutor, and the parent can still see it.
// The database checks the student is 16 or over and the email is new.
// The rules for giving a student their own login:
const ownLoginSchema = z.object({
  student_id: z.uuid("Choose a student."), // which student,
  email: z.email("Enter the student's own email address.").trim().toLowerCase(), // their own email (tidied to lower case).
}); // End of the rules.

// An admin gives a student on a parent's account their own login.
export async function giveStudentLogin(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FRONT_DESK); // Front desk admins and above.
  return offerOwnLogin(formData, "admin_offer_student_login"); // Uses the shared steps with the admin's database check.
} // End of giveStudentLogin.

// A parent gives their own child, aged 16 or over, a login. The database
// checks they manage this child and the child is 16 or over.
export async function giveMyChildLogin(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("parent")) return { error: "Only a parent can do this." }; // Only parents.
  return offerOwnLogin(formData, "parent_offer_student_login"); // Uses the shared steps with the parent's database check.
} // End of giveMyChildLogin.

// The shared steps for giving a student their own login.
async function offerOwnLogin(
  formData: FormData, // The form's data.
  rpc: "admin_offer_student_login" | "parent_offer_student_login", // Which database check to use (admin or parent).
): Promise<FormState> { // (the result shape)
  const parsed = ownLoginSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const { student_id, email } = parsed.data; // The checked values.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const offer = await supabase.rpc(rpc, { p_student: student_id, p_email: email }); // Asks the database to record the offer (it checks age, email and rights).
  if (offer.error) { // It failed:
    console.error("Student login offer failed:", offer.error.code, offer.error.message); // notes why in the server log,
    return { error: offer.error.code === "22023" ? `${offer.error.message}.` : "We couldn't do that. Please try again." }; // shows the database's plain message, or a general one.
  } // End of the failure case.

  const student = await supabase.from("students").select("full_name").eq("id", student_id).single(); // Reads the student's name.
  const name = student.data?.full_name ?? "the student"; // Their name (or "the student").
  const made = await makeAccount(email, { full_name: name }); // Makes their login and sends the invitation.
  if ("error" in made) { // Failed:
    await createAdminClient().from("student_login_offers").delete().eq("id", offer.data as string); // removes the offer so it can be tried again,
    return made; // and passes on the message.
  } // End of the failure case.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  revalidatePath("/dashboard", "layout"); // Refreshes the dashboard and everything under it.
  return { // Tells them:
    message: `${name} gets their own login once they use the link.${sentText(email, made.link)} ${rpc === "parent_offer_student_login" ? "You" : "Their parent"} can still see their details.`, // what happens next, how the invite was sent, and that the parent still sees the details.
  }; // End of the message.
} // End of offerOwnLogin.

// Sends a family or student a new link to choose their password, for when
// the first one ran out before they used it. Only for family accounts that
// have never signed in: staff use "Add staff", and anyone who has signed in
// can use "Forgot password" themselves.
export async function sendNewLink(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FRONT_DESK); // Front desk admins and above.
  const parsed = z.email("Enter a valid email address.").trim().toLowerCase().safeParse(formData.get("email")); // Reads and checks the email.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const email = parsed.data; // The checked email.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const lookup = await supabase.rpc("admin_find_account", { p_email: email }); // Looks up the email.
  if (lookup.error) return { error: "We couldn't check that email. Please try again." }; // Lookup failed: plain message.
  const found = ((lookup.data ?? []) as Found[])[0]; // The first match (if any).
  if (!found) return { error: `No CLG account uses ${email}. To make one, use "Set up a family".` }; // No account: suggests "Set up a family".

  const admin = createAdminClient(); // Connects with full access.
  const roles = await admin.from("account_roles").select("role").eq("account_id", found.account_id); // Reads the account's roles.
  const roleNames = (roles.data ?? []).map((r) => r.role as string); // Their role names.
  if (roles.error) return { error: "We couldn't check that account. Please try again." }; // Couldn't read them: plain message.
  if (roleNames.includes("admin") || roleNames.includes("tutor")) { // A staff account:
    return { error: "That's a staff account. To send staff a new link, invite them again under Staff." }; // explains staff are invited again under Staff.
  } // End of that case.
  if (roleNames.length === 0) { // No roles (a student's own login in waiting):
    return { error: `That account was made for a student's own login. Use "Give a student their own login" again with the same email.` }; // explains to offer the login again.
  } // End of that case.
  const user = await admin.auth.admin.getUserById(found.account_id); // Reads their sign-in account.
  if (user.error || !user.data.user) return { error: "We couldn't check that account. Please try again." }; // Couldn't read it: plain message.
  if (user.data.user.last_sign_in_at) { // Already signed in:
    return { // explains:
      error: `${found.full_name} has already signed in. If they've forgotten their password, they can use "Forgot password" on the sign-in page.`, // they can use "Forgot password".
    }; // End of the message.
  } // End of that case.

  const redirectTo = `${siteUrl()}/login`; // After choosing a password, they land on the login page.
  const confirmed = Boolean(user.data.user.email_confirmed_at); // True once they've confirmed their email.
  const sent = confirmed // Sends the right email:
    ? await admin.auth.resetPasswordForEmail(email, { redirectTo }) // a password reset if confirmed,
    : await admin.auth.admin.inviteUserByEmail(email, { redirectTo }); // otherwise a fresh invitation.
  if (!sent.error) return { message: `We've emailed ${email} a new link to choose a password.` }; // It sent: confirms it.
  console.error("New login link email failed:", sent.error.code ?? sent.error.name, sent.error.message); // Notes the email failure in the server log.

  const made = await admin.auth.admin.generateLink( // Makes the link without emailing it:
    confirmed ? { type: "recovery", email, options: { redirectTo } } : { type: "invite", email, options: { redirectTo } }, // a reset link if confirmed, otherwise an invitation link.
  ); // End of making the link.
  if (made.error || !made.data.properties?.action_link) { // That failed too:
    console.error("New login link failed:", made.error?.code, made.error?.message); // notes it in the server log,
    return { error: "We couldn't make a new link. Please try again." }; // and tells the admin plainly.
  } // End of the failure case.
  return { message: `New link made for ${found.full_name}.${sentText(email, made.data.properties.action_link)}` }; // Gives the admin the link to send themselves.
} // End of sendNewLink.

// A family set up by CLG agrees to the privacy policy and terms the first
// time they sign in.
export async function agreeToPolicies(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (formData.get("accept") !== "on") return { error: "Please tick the box to agree before carrying on." }; // Box not ticked: asks them to tick it.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("consent_records").insert([ // Saves their agreement:
    { account_id: viewer.id, kind: "privacy_policy", document_version: POLICY_VERSION }, // to the privacy policy,
    { account_id: viewer.id, kind: "terms_of_service", document_version: POLICY_VERSION }, // and the terms, at the current version.
  ]); // End of the save.
  if (error) return { error: "We couldn't save that. Please try again." }; // Failed: plain message.
  // News and offers only when they ticked the separate, optional box.
  if (formData.get("marketing") === "on") { // The optional news box was ticked:
    const news = await supabase.rpc("set_marketing_email", { p_on: true, p_version: POLICY_VERSION }); // saves that choice,
    if (news.error) console.error("Marketing choice not saved:", news.error.code, news.error.message); // notes any failure in the server log.
  } // End of the news choice.
  redirect("/dashboard"); // Goes to the dashboard.
} // End of agreeToPolicies.
