// Summary: the server actions for tutor applications. Anyone can send an
// application from the public "Apply to tutor" page (with spam checks and
// an optional CV). The owner and Operations admins save each application's
// screening record, decline it with a reason, or approve it, which sends the
// usual tutor invite link. See docs/features/tutor-applications.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { randomUUID } from "node:crypto"; // Makes random file names, so no one can guess a CV's address.
import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { headers } from "next/headers"; // Reads the request's headers (for the sender's internet address).
import { z } from "zod"; // The form-checking library.
import { checkFormStamp, scrambleAddress } from "@/lib/apply-token"; // The spam checks: the signed form stamp and the scrambled address.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is a full admin (owner or Operations).
import { STATES } from "@/lib/checks"; // The Australian states.
import { documentType } from "@/lib/documents"; // Works out a file's real type from its contents.
import { emailIsSetUp, sendEmails } from "@/lib/email/send"; // Checks email is set up, and sends emails.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { sendStaffInvite } from "@/lib/staff-invite"; // Sends the usual tutor invite link.
import { createAdminClient } from "@/lib/supabase/admin"; // Connects with the server's own key (only for saving public applications).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import {
  APPLICATION_NOTICE_VERSION, // The collection notice version shown on the form.
  DECLINE_REASONS, // The reasons for declining.
  FIRST_AID_STATUSES, // The first aid answers.
  MAX_CV_BYTES, // The largest CV accepted.
  RRHAN_STATUSES, // The RRHAN-EC answers.
  TEACH_MODES, // How someone can teach.
  WWCC_STATUSES, // The Working with Children Check answers.
} from "@/lib/tutor-applications"; // (shared words and limits for applications)

const BUCKET = "tutor-applications"; // The private file store for CVs.

// The plain database messages we're happy to show as they are (they start
// with these words); anything else gets a general message.
const PLAIN = /^(Please|You already|Too many|We're|We are|Your CV|Only |Choose|Record|This |That )/; // The starts of the database's own plain messages (old and written-out wording).

// A short text answer that must be filled in, with plain messages.
const needed = (label: string, max: number, min = 1) => // Takes the question's name, the longest and shortest lengths:
  z.string().trim().min(min, min > 1 ? `Please write a little more for "${label}".` : `Please fill in "${label}".`).max(max, `Please keep "${label}" under ${max.toLocaleString()} characters.`); // and gives back the rule.

// An optional short text answer.
const optional = (label: string, max: number) => // Takes the question's name and the longest length:
  z.string().trim().max(max, `Please keep "${label}" under ${max.toLocaleString()} characters.`).optional().default(""); // and gives back the rule (blank if not given).

// The rules for one referee (n is 1 or 2).
const referee = (n: number) => // Takes the referee's number:
  z.object({ // and gives back the rules:
    name: needed(`Referee ${n} name`, 200, 2), // their name,
    relationship: needed(`Referee ${n}: how they know you`, 300, 2), // how they know the applicant,
    email: z.union([z.literal(""), z.email(`Please check referee ${n}'s email address.`)]).default(""), // their email (or blank),
    phone: optional(`Referee ${n} phone`, 30), // their phone (or blank).
  }).refine((r) => r.email !== "" || r.phone.length >= 6, `Please give an email or phone number for referee ${n}.`); // At least one way to contact them.

// The rules for the whole application form.
const applySchema = z.object({
  first_name: needed("First name", 100), // first name,
  last_name: needed("Last name", 100), // last name,
  email: z.email("Please enter a valid email address.").trim().toLowerCase().max(254), // email (tidied to lower case),
  phone: needed("Phone", 30, 6), // phone,
  state: z.enum(STATES, "Please choose the state you live in."), // state,
  suburb: needed("Suburb or town", 100), // suburb or town,
  teach_mode: z.enum(TEACH_MODES, "Please choose how you would like to teach."), // in person, online or both,
  right_to_work: z.enum(["yes", "no"], "Please say whether you have the right to work in Australia."), // right to work (yes or no),
  subjects: needed("Subjects and year levels", 2000, 3), // subjects and year levels,
  availability: needed("When you are free", 1000, 3), // availability,
  weekly_hours: z.union([z.literal(""), z.coerce.number().int("Please give hours a week as a whole number.").min(1, "Hours a week should be between 1 and 40.").max(40, "Hours a week should be between 1 and 40.")]).default(""), // hours a week (optional),
  qualifications: needed("Qualifications", 3000, 3), // qualifications,
  teacher_registration: optional("Teacher registration", 100), // teacher registration (optional),
  experience: needed("Teaching or tutoring experience", 3000, 3), // experience,
  wwcc_status: z.enum(WWCC_STATUSES, "Please answer the Working with Children Check question."), // Working with Children Check status,
  wwcc_number: optional("Check number", 50), // its number (optional),
  wwcc_state: z.union([z.literal(""), z.enum(STATES)]).default(""), // its state (optional),
  wwcc_expiry: z.union([z.literal(""), z.iso.date("Please check the expiry date.")]).default(""), // its expiry (optional),
  rrhan_ec_status: z.enum(RRHAN_STATUSES, "Please answer the RRHAN-EC question."), // RRHAN-EC,
  first_aid_status: z.enum(FIRST_AID_STATUSES, "Please answer the first aid question."), // first aid,
  statement: needed("Why you would like to tutor with CLG", 3000, 30), // why CLG,
  helped_example: needed("A time you helped a young person", 3000, 30), // a time they helped,
  heard_from: optional("How you heard about CLG", 200), // how they heard (optional),
}); // End of the rules.

// Reads the sender's internet address from the request (Vercel puts it in
// these headers). Only used, scrambled, for the daily limit.
async function senderAddress(): Promise<string | null> {
  const h = await headers(); // The request's headers.
  return h.get("x-real-ip") ?? h.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null; // Vercel's own header first, then the first forwarded address, or nothing.
} // End of senderAddress.

// Sends a tutor application from the public page. Spam checks first (the
// hidden box must be empty and the signed stamp must show a person took
// their time), then the answers are checked, the CV stored privately, and
// the application saved with the server's own key. If saving fails, the
// CV is removed again.
export async function submitTutorApplication(_prev: FormState, formData: FormData): Promise<FormState> {
  // Spam check 1: a hidden box people never see. Bots fill in every box.
  if (String(formData.get("website") ?? "").trim() !== "") { // Something was typed in the hidden box:
    return { message: "Thanks, your application has been sent." }; // pretends it worked (so the bot learns nothing) but saves nothing.
  } // End of the hidden box check.
  // Spam check 2: the signed "form opened at" stamp.
  const stampProblem = checkFormStamp(formData.get("started") as string | null); // Checks the stamp.
  if (stampProblem) return { error: stampProblem }; // Problem: says what to do.

  const text = (name: string) => String(formData.get(name) ?? ""); // Reads one answer as text (blank if missing).
  const parsed = applySchema.safeParse(Object.fromEntries(Object.keys(applySchema.shape).map((k) => [k, text(k)]))); // Checks every answer against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const refs = [1, 2].map((n) => // Checks each referee:
    referee(n).safeParse({ name: text(`ref${n}_name`), relationship: text(`ref${n}_relationship`), email: text(`ref${n}_email`).trim().toLowerCase(), phone: text(`ref${n}_phone`) }), // from their four boxes.
  ); // End of the referee checks.
  const badRef = refs.find((r) => !r.success); // The first referee with a problem, if any.
  if (badRef && !badRef.success) return { error: badRef.error.issues[0].message }; // Shows that problem.
  if (formData.get("referee_consent") !== "on") return { error: "Please confirm your referees are happy for CLG to contact them." }; // Referee permission not ticked: asks for it.
  if (formData.get("declared_true") !== "on" || formData.get("declared_suitable") !== "on") { // A declaration not ticked:
    return { error: "Please tick both declarations to send your application." }; // asks for them.
  } // End of the declarations check.
  const v = parsed.data; // The checked answers.

  // The CV (optional): a real PDF, not too big.
  const cv = formData.get("cv"); // The chosen file, if any.
  let cvBytes: Uint8Array | null = null; // The CV's bytes (none yet).
  if (cv instanceof File && cv.size > 0) { // A file was chosen:
    if (cv.size > MAX_CV_BYTES) return { error: "Your CV is too big. Please save it as a smaller PDF (under 3.5MB)." }; // Too big: says the limit.
    cvBytes = new Uint8Array(await cv.arrayBuffer()); // Reads its bytes.
    if (documentType(cvBytes)?.type !== "application/pdf") return { error: "Your CV needs to be a PDF. In Word, choose File, then Save as, then PDF." }; // Not a PDF: says how to make one.
  } // End of the CV check.

  const supabase = createAdminClient(); // Connects with the server's own key (the save function only allows the server).
  let cvPath = ""; // Where the CV is stored (none yet).
  if (cvBytes) { // There's a CV:
    cvPath = `${randomUUID()}.pdf`; // a random name, so nobody can guess its address,
    const stored = await supabase.storage.from(BUCKET).upload(cvPath, cvBytes, { contentType: "application/pdf", upsert: false }); // stores it privately, never replacing another file.
    if (stored.error) { // Couldn't store it:
      console.error("Tutor application CV upload:", stored.error.message); // notes why in the server log,
      return { error: "Your CV did not upload. Please try again, or send your application without it and email it to us." }; // and offers a way round it.
    } // End of the failure case.
  } // End of storing the CV.

  const { error } = await supabase.rpc("tutor_application_submit", { // Saves the application:
    p: { // the answers:
      ...v, // everything checked above,
      right_to_work: v.right_to_work === "yes", // right to work as yes or no,
      weekly_hours: v.weekly_hours === "" ? "" : String(v.weekly_hours), // hours a week as text (blank if not given),
      referees: refs.map((r) => (r.success ? r.data : null)), // the two referees,
      cv_path: cvPath, // the CV's path (blank if none),
      declared_true: true, // the first declaration (checked above),
      declared_suitable: true, // the second declaration (checked above),
      privacy_version: APPLICATION_NOTICE_VERSION, // the notice version they saw,
    }, // (end of the answers)
    p_ip_hash: scrambleAddress(await senderAddress()), // and their scrambled internet address, for the daily limit.
  }); // End of the save.
  if (error) { // Saving failed:
    if (cvPath) await supabase.storage.from(BUCKET).remove([cvPath]); // removes the CV so nothing is left behind,
    if (!PLAIN.test(error.message)) console.error("Tutor application save:", error.code, error.message); // notes unexpected problems in the server log,
    return { error: PLAIN.test(error.message) ? error.message : "Could not send your application. Please try again." }; // and shows the database's plain message, or a general one.
  } // End of the failure case.

  // A short "we've got it" email. If it can't be sent, the application is still saved.
  if (emailIsSetUp()) { // Email is set up:
    const problem = await sendEmails([{ // sends one email:
      id: `tutor-application-${randomUUID()}`, // a fresh id for it,
      email: v.email, // to the applicant,
      first_name: v.first_name, // greeting them by first name,
      subject: "Thanks for applying to tutor with CLG", // the subject line,
      body: "We have received your application to tutor with CLG Tutoring. We read every application and will be in touch, usually within two weeks. If you are shortlisted, we will invite you to an interview and contact your two referees. If you need to change anything, just reply to this email.", // what happens next,
      link: "/privacy", // the button opens the privacy policy,
      button: "How we look after your information", // the button's words,
      footer: "You get this email because you applied to tutor with CLG Tutoring.", // and why they got it.
    }]); // End of the email.
    if (problem) console.error("Tutor application thank-you email:", problem); // Couldn't send: notes why in the server log.
  } // End of the email.

  revalidatePath("/admin/applications"); // Refreshes the admin queue.
  return { message: "Thanks, your application has been sent. We will email you to confirm, and be in touch soon." }; // Thanks them.
} // End of submitTutorApplication.

// The rules for the screening record.
const saveSchema = z.object({
  id: z.uuid(), // which application,
  status: z.enum(["new", "shortlisted", "withdrawn"], "Choose New, Shortlisted or Withdrawn."), // where it's up to,
  interview_on: z.union([z.literal(""), z.iso.date("Check the interview date.")]).default(""), // interview date (or blank),
  interview_notes: z.string().trim().max(4000, "Please keep the interview notes under 4,000 characters.").default(""), // interview notes,
  referee_1_checked_on: z.union([z.literal(""), z.iso.date("Check the referee 1 date.")]).default(""), // referee 1 checked (or blank),
  referee_2_checked_on: z.union([z.literal(""), z.iso.date("Check the referee 2 date.")]).default(""), // referee 2 checked (or blank),
  referee_notes: z.string().trim().max(4000, "Please keep the referee notes under 4,000 characters.").default(""), // referee notes,
  wwcc_verified_on: z.union([z.literal(""), z.iso.date("Check the Working with Children Check date.")]).default(""), // check verified (or blank),
  admin_notes: z.string().trim().max(4000, "Please keep the notes under 4,000 characters.").default(""), // other notes.
}); // End of the rules.

// Saves an application's screening record and status.
export async function saveTutorApplication(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (the database checks again).
  const parsed = saveSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const { id, ...record } = parsed.data; // The application and its record.
  const supabase = await createClient(); // Connects as the signed-in admin.
  const { error } = await supabase.rpc("tutor_application_save", { p_id: id, p: record }); // Saves it.
  if (error) return { error: PLAIN.test(error.message) ? error.message : "Could not save. Please try again." }; // Failed: the plain message, or a general one.
  revalidatePath("/admin/applications"); // Refreshes the queue.
  return { message: "Saved." }; // Confirms it.
} // End of saveTutorApplication.

// The rules for declining.
const declineSchema = z.object({
  id: z.uuid(), // which application,
  reason: z.enum(DECLINE_REASONS, "Choose a reason for declining."), // why,
  note: z.string().trim().max(1000, "Please keep the note under 1,000 characters.").default(""), // any note.
}); // End of the rules.

// Declines an application, and (if ticked) sends a polite "not this time"
// email. The reason stays private to admins and isn't in the email.
export async function declineTutorApplication(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (the database checks again).
  const parsed = declineSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects as the signed-in admin.
  const { data: email, error } = await supabase.rpc("tutor_application_decline", { p_id: parsed.data.id, p_reason: parsed.data.reason, p_note: parsed.data.note }); // Records the decline and gets their email.
  if (error) return { error: PLAIN.test(error.message) ? error.message : "Could not decline it. Please try again." }; // Failed: the plain message, or a general one.
  revalidatePath("/admin/applications"); // Refreshes the queue.
  if (formData.get("send_email") !== "on") return { message: "Declined. No email was sent." }; // No email asked for: confirms.
  const { data: who } = await supabase.from("tutor_applications").select("first_name").eq("id", parsed.data.id).maybeSingle(); // Reads their first name for the greeting.
  const problem = emailIsSetUp() // Sends the email if email is set up:
    ? await sendEmails([{ // one email:
        id: `tutor-application-decline-${parsed.data.id}`, // an id for it (once per application),
        email: String(email), // to the applicant,
        first_name: (who?.first_name as string | undefined) ?? null, // greeting them by first name,
        subject: "Your application to tutor with CLG", // the subject line,
        body: "Thank you for applying to tutor with CLG Tutoring and for the time you put into your application. We are not able to offer you a tutoring role at the moment. We will keep your application for 12 months and then delete it. You are welcome to apply again in future if things change.", // a polite, plain "not this time",
        link: "/", // the button opens the CLG app's front page,
        button: "Visit CLG", // the button's words,
        footer: "You get this email because you applied to tutor with CLG Tutoring.", // and why they got it.
      }]) // End of the email.
    : "Email is not set up yet."; // Email not set up: notes that.
  if (problem) { // The email didn't go:
    console.error("Tutor application decline email:", problem); // notes why in the server log,
    return { message: `Declined, but the email could not be sent. Please let them know yourself at ${String(email)}.` }; // and asks the admin to tell them.
  } // End of that case.
  return { message: "Declined, and a polite email has been sent." }; // Confirms both.
} // End of declineTutorApplication.

// Approves an application (the database checks the interview and both
// referee checks are recorded) and sends the usual tutor invite link. Also
// used to send the invite again if it didn't go the first time.
export async function approveTutorApplication(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (the database checks again).
  const id = z.uuid().safeParse(formData.get("id")); // Checks the application id looks right.
  if (!id.success) return { error: "That application was not found." }; // Odd id: plain message.
  const supabase = await createClient(); // Connects as the signed-in admin.
  const { data: email, error } = await supabase.rpc("tutor_application_approve", { p_id: id.data }); // Approves it (or refuses, saying what's missing) and gets their email.
  if (error || typeof email !== "string") return { error: error && PLAIN.test(error.message) ? error.message : "Could not approve it. Please try again." }; // Failed: the plain message, or a general one.
  revalidatePath("/admin/applications"); // Refreshes the queue.
  const invite = await sendStaffInvite(email, "tutor", null); // Sends the tutor invite link (or adds the tutor role if they already have an account).
  if (invite.error) return { error: `Approved, but the invite could not be made: ${invite.error} Press Send invite again to retry.` }; // The invite failed: says so (the approval stays).
  await supabase.rpc("tutor_application_invited", { p_id: id.data }); // Notes that the invite went (or was handed to the admin).
  revalidatePath("/admin/applications"); // Refreshes the queue again to show it.
  return { message: `Approved. ${invite.message ?? ""}`.trim() }; // Confirms, with what happened to the invite.
} // End of approveTutorApplication.
