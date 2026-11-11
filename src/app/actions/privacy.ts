// Summary: privacy actions. Everyone can make a privacy request, choose
// marketing emails and give parental consent; full admins handle requests
// and keep the data breach register.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { redirect } from "next/navigation"; // Lets the code send someone to another page.
import { z } from "zod"; // The form-checking library.
import { requireAdmin, requireViewer } from "@/lib/auth"; // Makes sure someone is signed in, or is a full admin.
import { POLICY_VERSION, type FormState } from "@/lib/forms"; // The current policy version, and the form reply shape.
import { giveParentalConsent } from "@/lib/consent"; // Records a parent's consent for children.
import { PRIVACY_REQUEST_KINDS, REGIONS } from "@/lib/privacy"; // The kinds of privacy request, and the breach regions.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// ---------------------------------------------------------------------------
// For everyone: requests, marketing emails, parental consent
// ---------------------------------------------------------------------------

// The rules for a privacy request:
const requestSchema = z.object({
  kind: z.enum(PRIVACY_REQUEST_KINDS.map((k) => k.id) as [string, ...string[]], { message: "Please choose what you'd like." }), // what they'd like (one of the request kinds),
  details: z.string().trim().min(3, "Please tell us a little more.").max(2000, "Please keep it under 2000 characters."), // the details (3 to 2,000 letters),
  student_id: z.union([z.uuid(), z.literal("")]).optional(), // which child it's about (optional).
}); // End of the rules.

// Sends a privacy request to CLG.
export async function makePrivacyRequest(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = requestSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("make_privacy_request", { // Asks the database to save the request:
    p_kind: parsed.data.kind, // its kind,
    p_details: parsed.data.details, // its details,
    p_student: parsed.data.student_id || undefined, // and the child, if chosen.
  }); // End of the request.
  if (error) { // It failed:
    return { error: error.code === "54000" ? error.message : "We couldn't send that. Please try again, or email CLG." }; // shows the "too many requests" message, or a general one.
  } // End of the failure case.
  revalidatePath("/my-privacy"); // Refreshes the privacy page.
  return { message: "Sent. CLG will reply within 28 days, and you can follow it below." }; // Confirms and says when to expect a reply.
} // End of makePrivacyRequest.

// Turns CLG news and offers emails on or off.
export async function setMarketingEmail(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const on = formData.get("marketing") === "on"; // True if the box is ticked.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("set_marketing_email", { p_on: on, p_version: POLICY_VERSION }); // Saves the choice, with the policy version agreed to.
  if (error) return { error: "We couldn't save that. Please try again." }; // Failed: plain message.
  revalidatePath("/my-privacy"); // Refreshes the privacy page.
  return { message: on ? "You'll get CLG news and offers by email. You can turn this off any time." : "You won't get news or offers. You'll still get messages about your sessions and invoices." }; // Confirms what they'll get.
} // End of setMarketingEmail.

// A parent gives (or renews) consent for each child that needs it.
export async function agreeForChildren(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data } = await supabase.rpc("children_needing_consent"); // Asks which children need consent.
  const needed = ((data ?? []) as { student_id: string }[]).map((c) => c.student_id); // Their ids.
  const ticked = needed.filter((id) => formData.get(`child_${id}`) === "on"); // The ones the parent ticked.
  if (ticked.length < needed.length) return { error: "Please tick the box for each child to carry on." }; // Not all ticked: asks to tick each one.
  if (!(await giveParentalConsent(ticked))) return { error: "We couldn't save that. Please try again." }; // Saves consent; plain message if it fails.
  redirect("/dashboard"); // Done: goes to the dashboard.
} // End of agreeForChildren.

// ---------------------------------------------------------------------------
// For admins (owner or operations): requests and the breach register
// ---------------------------------------------------------------------------

// The rules for updating a privacy request:
const updateSchema = z.object({
  id: z.uuid(), // which request,
  status: z.enum(["in_progress", "done", "refused"]), // its new stage,
  outcome: z.string().trim().max(2000).optional(), // what was done (optional),
  extend_to: z.union([z.iso.date(), z.literal("")]).optional(), // a new due date if extended (optional),
  extension_reason: z.string().trim().max(500).optional(), // and why it was extended (optional).
}); // End of the rules.

// An admin updates a privacy request.
export async function updatePrivacyRequest(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  const parsed = updateSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("update_privacy_request", { // Asks the database to save:
    p_id: parsed.data.id, // which request,
    p_status: parsed.data.status, // its stage,
    p_outcome: parsed.data.outcome || undefined, // what was done,
    p_extend_to: parsed.data.extend_to || undefined, // the new due date,
    p_extension_reason: parsed.data.extension_reason || undefined, // and the reason for extending.
  }); // End of the save.
  if (error) return { error: error.message }; // Failed: shows the database's message.
  revalidatePath("/admin/privacy"); // Refreshes the admin privacy page.
  return { message: "Saved. Remember to tell the person what's happening." }; // Reminds the admin to tell the person.
} // End of updatePrivacyRequest.

// The rules for recording a data breach:
const incidentSchema = z.object({
  title: z.string().trim().min(3, "Give it a short title.").max(200), // a short title,
  what_happened: z.string().trim().min(3, "Say briefly what happened.").max(4000), // what happened,
  found_at: z.string().min(1, "When did CLG find out?"), // when CLG found out,
  data_involved: z.string().trim().max(1000).optional(), // what information was involved (optional),
  people_affected: z.union([z.coerce.number().int().min(0), z.literal("")]).optional(), // how many people were affected (optional whole number).
}); // End of the rules.

// Times typed into the form are Adelaide times.
function adelaideToIso(local: string): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(local); // Splits "YYYY-MM-DDTHH:MM" into its parts.
  if (!m) return null; // Not in that shape: can't be read.
  const asUtc = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]); // Reads the time as if it were universal time.
  // Adelaide's offset at that moment (+9:30 or +10:30).
  const parts = new Intl.DateTimeFormat("en-AU", { timeZone: "Australia/Adelaide", timeZoneName: "longOffset" }) // Asks for Adelaide's offset at that moment:
    .formatToParts(new Date(asUtc)) // by formatting the moment,
    .find((p) => p.type === "timeZoneName")?.value; // and picking out the offset text (e.g. "GMT+10:30").
  const off = /GMT([+-])(\d{2}):(\d{2})/.exec(parts ?? ""); // Splits the offset into sign, hours and minutes.
  const minutes = off ? (off[1] === "-" ? -1 : 1) * (+off[2] * 60 + +off[3]) : 570; // The offset in minutes (570 = 9.5 hr if unreadable).
  return new Date(asUtc - minutes * 60_000).toISOString(); // Moves the time back by the offset to get the true moment.
} // End of adelaideToIso.

// Records a data breach in the register.
export async function recordIncident(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  const parsed = incidentSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const foundAt = adelaideToIso(parsed.data.found_at); // Turns the typed time into a true moment.
  if (!foundAt) return { error: "Please check the date and time found." }; // Unreadable time: plain message.
  const regions = formData.getAll("regions").map(String).filter((r) => REGIONS.some((x) => x.id === r)); // The ticked regions, keeping only known ones.
  if (regions.length === 0) return { error: "Tick where the people affected live (Australia if unsure)." }; // None ticked: asks to tick at least one.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("privacy_incidents").insert({ // Saves the breach:
    title: parsed.data.title, // title,
    what_happened: parsed.data.what_happened, // what happened,
    found_at: foundAt, // when found,
    data_involved: parsed.data.data_involved || null, // information involved (or none),
    people_affected: parsed.data.people_affected === "" || parsed.data.people_affected === undefined ? null : parsed.data.people_affected, // people affected (or none if blank),
    children_affected: formData.get("children_affected") === "on", // whether children were affected (tick box),
    regions, // and the regions.
  }); // End of the save.
  if (error) return { error: "We couldn't save that. Check the date isn't in the future, then try again." }; // Failed: plain message.
  revalidatePath("/admin/privacy"); // Refreshes the admin privacy page.
  return { message: "Recorded. The 72-hr clock has started: follow the next step shown." }; // Reminds the admin the 72-hr clock has started.
} // End of recordIncident.

// The rules for a breach update:
const incidentUpdateSchema = z.object({
  id: z.uuid(), // which breach,
  step: z.enum(["contained", "assessed_serious", "assessed_not_serious", "regulators", "people", "close"]), // which step happened,
  note: z.string().trim().max(2000).optional(), // a note (optional).
}); // End of the rules.

// Records the next step on a data breach.
export async function updateIncident(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  const parsed = incidentUpdateSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: "Please choose what's happened." }; // Problem: asks what happened.
  const now = new Date().toISOString(); // The current time.
  const note = parsed.data.note || null; // The note (or none).
  const change: Record<string, unknown> = // What to save, by step:
    parsed.data.step === "contained" // contained:
      ? { contained_at: now } // the time it was contained,
      : parsed.data.step === "assessed_serious" // judged serious:
        ? { serious_harm_likely: true, decision_reason: note } // serious harm likely, with the reason,
        : parsed.data.step === "assessed_not_serious" // judged not serious:
          ? { serious_harm_likely: false, decision_reason: note } // serious harm unlikely, with the reason,
          : parsed.data.step === "regulators" // regulators told:
            ? { regulators_told_at: now, regulators_told: note } // when, and which ones,
            : parsed.data.step === "people" // people told:
              ? { people_told_at: now } // when,
              : { closed_at: now, lessons: note }; // otherwise closing: when, and lessons learned.
  if ((parsed.data.step.startsWith("assessed") || parsed.data.step === "regulators") && !note) { // Decisions and telling regulators need a note:
    return { error: parsed.data.step === "regulators" ? "Write which regulators were told." : "Write the reason for the decision." }; // asks for the right note.
  } // End of that check.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("privacy_incidents").update(change).eq("id", parsed.data.id); // Saves the change on this breach.
  if (error) { // Failed:
    return { // explains:
      error: // (the message)
        parsed.data.step === "close" // if closing,
          ? "It can't be closed yet: decide on serious harm first, and if harm is likely, record telling the regulators." // what has to happen first,
          : "We couldn't save that. Please try again.", // otherwise a general message.
    }; // End of the message.
  } // End of the failure case.
  revalidatePath("/admin/privacy"); // Refreshes the admin privacy page.
  return { message: "Saved." }; // Tells the person it worked.
} // End of updateIncident.
