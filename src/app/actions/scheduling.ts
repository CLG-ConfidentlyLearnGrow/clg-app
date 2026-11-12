// Summary: scheduling actions: asking for and offering weekly bookings,
// tutors and families answering, cancelling, recording how a session went,
// and the other booking steps below.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { after } from "next/server"; // Runs a task after the reply is sent, so the person isn't kept waiting.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in, and says who they are.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { runTeamsSyncQuietly } from "@/lib/teams/sync"; // Updates Teams meeting links, without stopping on errors.

// The database explains most refusals in plain words (see the scheduling
// migration). Pass those on; hide anything technical.
function plainError(error: { message: string; code?: string } | null, fallback: string): string {
  if (!error) return fallback; // No error: uses the fallback message.
  const technical = /violates|syntax|relation|column|function|permission denied|uuid/i.test(error.message); // True if the message looks technical (database wording).
  return technical ? fallback : error.message; // Technical: uses the fallback; otherwise passes the plain message on.
} // End of plainError.

// Finishes a scheduling action: refreshes the page and updates Teams links.
function done(message: string): FormState {
  revalidatePath("/schedule"); // Refreshes the schedule page.
  // Sessions may have been added or cancelled: update Teams links after replying.
  after(runTeamsSyncQuietly); // Updates Teams links once the reply is sent.
  return { message }; // Gives back the success message.
} // End of done.

// ---------------------------------------------------------------------------
// Families (and admins during the pilot) ask for a weekly booking
// ---------------------------------------------------------------------------
// The rules for a booking:
const bookingSchema = z
  .object({ // (the fields:)
    student_id: z.uuid(), // which student,
    subject: z.string().trim().min(1).max(100), // the subject,
    tutor_id: z.uuid(), // which tutor,
    weekday: z.coerce.number().int().min(1).max(7), // the weekday (1 Monday to 7 Sunday),
    start_time: z.iso.time(), // the start time,
    minutes: z.coerce.number().int().min(60).max(240), // how long, 60 to 240 minutes,
    delivery: z.enum(["online", "library"]), // online or at a library,
    library_id: z.union([z.uuid(), z.literal("")]).optional(), // which library (optional),
    first_date: z.iso.date("Choose the first date."), // the first date,
    last_date: z.iso.date("Choose the last date."), // the last date,
    note: z.string().trim().max(1000).optional(), // a note (optional).
  }) // (end of the fields)
  .refine((v) => v.last_date >= v.first_date, { message: "The last date must be after the first date." }); // and the last date can't be before the first.

// The app's suggested time, sent along when an admin makes an offer:
const suggestionSchema = z.object({
  suggested_tutor: z.uuid(), // the suggested tutor,
  suggested_weekday: z.coerce.number().int().min(1).max(7), // the suggested weekday,
  suggested_start: z.iso.time(), // the suggested start time,
  suggested_delivery: z.enum(["online", "library", "home"]), // the suggested place,
  suggested_library: z.union([z.uuid(), z.literal("")]).optional(), // the suggested library (optional),
  change_reason: z.enum(["tutor_fit", "family_request", "tutor_request", "time", "place", "other"]).optional(), // why the admin changed it (optional),
  change_note: z.string().trim().max(500).optional(), // a note on the change (optional).
}); // End of the rules.

// A family asks for a weekly booking, or an admin offers one.
export async function requestBooking(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const parsed = bookingSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.

  // An admin who picked something other than the app's suggestion says why.
  const isAdmin = viewer.roles.includes("admin"); // True if the person is an admin.
  const suggestion = isAdmin && formData.get("suggested_tutor") ? suggestionSchema.safeParse(Object.fromEntries(formData)) : null; // For admins with a suggestion, checks the suggestion's fields.
  const changed = // True when the admin picked something different:
    suggestion?.success && // the suggestion is valid, and
    (suggestion.data.suggested_tutor !== v.tutor_id || // the tutor differs,
      suggestion.data.suggested_weekday !== v.weekday || // or the weekday,
      suggestion.data.suggested_start.slice(0, 5) !== v.start_time.slice(0, 5) || // or the start time (hours and minutes),
      suggestion.data.suggested_delivery !== v.delivery || // or the place,
      (suggestion.data.suggested_library || "") !== (v.library_id || "")); // or the library.
  if (changed && !suggestion.data.change_reason) return { error: "Please say why you didn't use the suggested time." }; // Changed without a reason: asks for one.

  // "Another time or place" (CLG admins only): outside the tutor's availability.
  const other = isAdmin && formData.get("other") === "1"; // True if an admin chose "another time or place".
  if (other && suggestion?.success && !suggestion.data.change_reason) return { error: "Please say why you didn't use the suggested time." }; // That also needs a reason when there's a suggestion.

  const supabase = await createClient(); // Connects to the database.
  const { data: bookingId, error } = await supabase.rpc(other ? "offer_other_time" : "request_booking", { // Asks the database to make the booking (an "other time" offer, or a normal one), and gets its id:
    p_student: v.student_id, // the student,
    p_subject: v.subject, // the subject,
    p_tutor: v.tutor_id, // the tutor,
    p_weekday: v.weekday, // the weekday,
    p_start: v.start_time, // the start time,
    p_minutes: v.minutes, // the length,
    p_delivery: v.delivery, // online or library,
    p_library: v.delivery === "library" ? v.library_id || null : null, // the library, only for library sessions,
    p_first_date: v.first_date, // the first date,
    p_last_date: v.last_date, // the last date,
    p_note: v.note || null, // the note (or none).
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't send the request. Please try again.") }; // Failed: plain message.

  if (changed && suggestion?.success) { // If the admin changed the suggestion:
    await supabase.rpc("record_offer_change", { // records the change for later review:
      p_booking: bookingId as string, // the booking,
      p_suggested_tutor: suggestion.data.suggested_tutor, // the suggested tutor,
      p_suggested_weekday: suggestion.data.suggested_weekday, // the suggested weekday,
      p_suggested_start: suggestion.data.suggested_start, // the suggested start,
      p_suggested_delivery: suggestion.data.suggested_delivery, // the suggested place,
      p_suggested_library: suggestion.data.suggested_library || null, // the suggested library (or none),
      p_reason: suggestion.data.change_reason!, // the reason,
      p_note: suggestion.data.change_note || null, // the note (or none).
    }); // End of the record.
  } // End of that step.
  return done( // Refreshes, updates Teams, and tells them:
    isAdmin // for admins,
      ? "Offer sent. The tutor and family each have 3 days to approve, with a reminder after 2 days. It's confirmed once both say yes." // how the offer is approved,
      : "Request sent. The tutor has 48 hours to confirm. You'll see it under Bookings.", // for families, how the request is confirmed.
  ); // (end of the message)
} // End of requestBooking.

// ---------------------------------------------------------------------------
// Tutors answer requests
// ---------------------------------------------------------------------------
// The rules for answering a booking:
const answerSchema = z.object({
  booking_id: z.uuid(), // which booking,
  answer: z.enum(["accept", "decline"]), // accept or decline,
  note: z.string().trim().max(1000).optional(), // a note (optional).
}); // End of the rules.

// A tutor accepts or declines a booking request.
export async function answerBooking(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = answerSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: "Choose accept or decline." }; // Problem: asks them to choose.
  if (parsed.data.answer === "decline" && !parsed.data.note?.trim()) return { error: "Please give a reason for declining." }; // Declining needs a reason.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("respond_to_booking", { // Asks the database to record the answer:
    p_booking: parsed.data.booking_id, // which booking,
    p_accept: parsed.data.answer === "accept", // accepted or not,
    p_note: parsed.data.note || null, // the note (or none).
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't save your answer.") }; // Failed: plain message.
  return done( // Refreshes, updates Teams, and tells them:
    parsed.data.answer === "accept" // if accepted,
      ? "Accepted. If the family still needs to approve, it's confirmed once they do." // that it's confirmed once the family approves,
      : "Declined. CLG will offer the family other times.", // if declined, that CLG will offer other times.
  ); // (end of the message)
} // End of answerBooking.

// ---------------------------------------------------------------------------
// Families approve a time CLG offered
// ---------------------------------------------------------------------------
// A family approves or declines an offered time.
export async function approveBooking(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = answerSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: "Choose approve or decline." }; // Problem: asks them to choose.
  if (parsed.data.answer === "decline" && !parsed.data.note?.trim()) return { error: "Please give a reason for declining." }; // Declining needs a reason.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("approve_booking", { // Asks the database to record the answer:
    p_booking: parsed.data.booking_id, // which booking,
    p_ok: parsed.data.answer === "accept", // approved or not,
    p_note: parsed.data.note || null, // the note (or none).
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't save your answer.") }; // Failed: plain message.
  return done( // Refreshes, updates Teams, and tells them:
    parsed.data.answer === "accept" // if approved,
      ? "Approved. It's confirmed once the tutor has said yes too." // that it's confirmed once the tutor agrees,
      : "Thanks for letting us know. CLG will offer another time.", // if declined, that CLG will offer another time.
  ); // (end of the message)
} // End of approveBooking.

// ---------------------------------------------------------------------------
// Cancelling
// ---------------------------------------------------------------------------
// The rules for cancelling:
const cancelSchema = z.object({
  id: z.uuid(), // the session or booking,
  reason: z.string().trim().max(500).optional(), // the reason (optional),
  on_behalf: z.enum(["", "family", "tutor", "admin"]).optional(), // who it's cancelled for (optional, admins only).
}); // End of the rules.

// Cancels one session.
export async function cancelSession(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = cancelSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: "Couldn't read that request." }; // Problem: plain message.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("cancel_session", { // Asks the database to cancel it:
    p_session: parsed.data.id, // which session,
    p_reason: parsed.data.reason || null, // the reason (or none),
    p_for: parsed.data.on_behalf || null, // who it's for (or none).
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't cancel the session.") }; // Failed: plain message.
  return done("Session cancelled."); // Refreshes, updates Teams, and confirms it.
} // End of cancelSession.

// Stops a weekly booking, cancelling its future sessions.
export async function stopBooking(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = cancelSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: "Couldn't read that request." }; // Problem: plain message.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("cancel_booking", { // Asks the database to stop it:
    p_booking: parsed.data.id, // which booking,
    p_reason: parsed.data.reason || null, // the reason (or none),
    p_for: parsed.data.on_behalf || null, // who it's for (or none).
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't stop the booking.") }; // Failed: plain message.
  return done("Booking stopped. Its future sessions are cancelled."); // Refreshes, updates Teams, and confirms it.
} // End of stopBooking.

// ---------------------------------------------------------------------------
// After a session: completed or no-show
// ---------------------------------------------------------------------------
const outcomeSchema = z.object({ id: z.uuid(), outcome: z.enum(["completed", "no_show"]) }); // The rules: the session, and done or no-show.

// Records whether a session happened or was a no-show.
export async function recordOutcome(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = outcomeSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: "Choose done or no-show." }; // Problem: asks them to choose.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("record_session_outcome", { // Asks the database to record it:
    p_session: parsed.data.id, // which session,
    p_status: parsed.data.outcome, // and the outcome.
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't save that.") }; // Failed: plain message.
  return done("Saved."); // Refreshes, updates Teams, and confirms it.
} // End of recordOutcome.

// ---------------------------------------------------------------------------
// Tutors: how and where they work
// ---------------------------------------------------------------------------
// A tutor saves how they work (online, in person) and which libraries they use.
export async function saveTutorPlaces(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor")) return { error: "Only tutors can set this." }; // Only tutors can do this.

  const online = formData.get("online") === "on"; // True if "online" is ticked.
  const inPerson = formData.get("in_person") === "on"; // True if "in person" is ticked.
  const learningSupport = formData.get("learning_support") === "on"; // True if "learning support" is ticked.
  if (!online && !inPerson) return { error: "Choose online, in person, or both." }; // At least one way of working is needed.
  const libraries = z.array(z.uuid()).safeParse(formData.getAll("library")); // Checks the ticked libraries' ids.
  if (!libraries.success) return { error: "Couldn't read the libraries you chose." }; // Odd ids: plain message.
  if (inPerson && libraries.data.length === 0) return { error: "Tick at least one library for in-person sessions." }; // In person needs at least one library.

  const supabase = await createClient(); // Connects to the database.
  const settings = await supabase.from("tutor_session_settings").upsert({ // Saves the settings (adds or updates the row):
    tutor_id: viewer.id, // for this tutor,
    online, // online or not,
    in_person: inPerson, // in person or not,
    learning_support: learningSupport, // learning support or not.
  }); // End of the save.
  if (settings.error) return { error: "Couldn't save your settings." }; // Failed: plain message.

  const current = await supabase.from("tutor_places").select("library_id").eq("tutor_id", viewer.id); // Reads the tutor's current libraries.
  const had = new Set((current.data ?? []).map((r) => r.library_id as string)); // The libraries they had.
  const want = new Set(libraries.data); // The libraries they want now.
  const remove = [...had].filter((id) => !want.has(id)); // Ones to remove: had but no longer wanted.
  const add = [...want].filter((id) => !had.has(id)).map((library_id) => ({ tutor_id: viewer.id, library_id })); // Ones to add: wanted but not had.
  if (remove.length) { // If any to remove:
    const r = await supabase.from("tutor_places").delete().eq("tutor_id", viewer.id).in("library_id", remove); // deletes them,
    if (r.error) return { error: "Couldn't update your libraries." }; // failed: plain message.
  } // End of removing.
  if (add.length) { // If any to add:
    const r = await supabase.from("tutor_places").insert(add); // adds them,
    if (r.error) return { error: "Couldn't update your libraries." }; // failed: plain message.
  } // End of adding.
  return done("Saved."); // Refreshes, updates Teams, and confirms it.
} // End of saveTutorPlaces.

// ---------------------------------------------------------------------------
// Admins: the list of libraries
// ---------------------------------------------------------------------------
// The rules for a library:
const librarySchema = z.object({
  name: z.string().trim().min(1, "Enter the library's name.").max(200), // its name,
  suburb: z.string().trim().max(100).optional(), // the suburb (optional),
  address: z.string().trim().max(300).optional(), // the address (optional),
  latitude: z.union([z.coerce.number().min(-90).max(90), z.literal("")]).optional(), // its latitude (optional),
  longitude: z.union([z.coerce.number().min(-180).max(180), z.literal("")]).optional(), // its longitude (optional).
}); // End of the rules.

// An admin adds a library to the list.
export async function addLibrary(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("admin")) return { error: "Only admins can add libraries." }; // Only admins can do this.
  const parsed = librarySchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("libraries").insert({ // Saves the library:
    name: parsed.data.name, // its name,
    suburb: parsed.data.suburb || null, // the suburb (or none),
    address: parsed.data.address || null, // the address (or none),
    latitude: parsed.data.latitude === "" ? null : (parsed.data.latitude ?? null), // the latitude (or none),
    longitude: parsed.data.longitude === "" ? null : (parsed.data.longitude ?? null), // the longitude (or none).
  }); // End of the save.
  if (error) return { error: error.code === "23505" ? "That library is already listed." : "Couldn't add the library." }; // Failed: says if it's already listed, or a general message.
  return done("Library added."); // Refreshes, updates Teams, and confirms it.
} // End of addLibrary.

// An admin turns a library on or off in the list.
export async function setLibraryActive(formData: FormData) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("admin")) return; // Only admins can do this.
  const id = z.uuid().safeParse(formData.get("id")); // Reads and checks the library's id.
  if (!id.success) return; // Bad id: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase // Saves:
    .from("libraries") // in the libraries table,
    .update({ active: formData.get("active") === "true" }) // on or off, from the form,
    .eq("id", id.data); // for this library.
  revalidatePath("/schedule"); // Refreshes the schedule page.
} // End of setLibraryActive.

// ---------------------------------------------------------------------------
// Away dates
// ---------------------------------------------------------------------------
// The rules for away dates:
const awaySchema = z
  .object({ // (the fields:)
    who: z.string().min(1, "Choose who will be away."), // who will be away,
    from_date: z.iso.date("Choose the first day away."), // the first day,
    to_date: z.iso.date("Choose the last day away."), // the last day,
    reason: z.string().trim().max(300).optional(), // the reason (optional),
    tutor_offer: z.string().trim().max(1000).optional(), // what the tutor offers instead (optional).
  }) // (end of the fields)
  .refine((v) => v.to_date >= v.from_date, { message: "The last day must be on or after the first day." }); // and the last day can't be before the first.

// "who" is "me" for a tutor's own dates, or "student:<id>" for a child.
export async function addAwayDates(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const parsed = awaySchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const studentId = v.who.startsWith("student:") ? v.who.slice(8) : null; // The student's id, if it's for a student.
  if (studentId && !z.uuid().safeParse(studentId).success) return { error: "Choose who will be away." }; // Odd id: asks them to choose again.

  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase.rpc("add_away_dates", { // Asks the database to save the dates, and gets how many sessions were cancelled:
    p_tutor: studentId ? null : viewer.id, // the tutor (when it's their own dates),
    p_student: studentId, // the student (when it's a child's dates),
    p_from: v.from_date, // the first day,
    p_to: v.to_date, // the last day,
    p_reason: v.reason || null, // the reason (or none),
    p_tutor_offer: studentId ? null : v.tutor_offer || null, // the tutor's offer (tutors only, or none).
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't save the away dates.") }; // Failed: plain message.
  // A tutor's away dates wait 2 hours before sessions are cancelled, so a
  // mistake can be fixed by removing them.
  if (!studentId) // For a tutor's own dates:
    return done( // refreshes, updates Teams, and tells them:
      "Saved. Booked sessions on these dates will be cancelled in 2 hours, and families and CLG will be told. Remove the dates before then if you made a mistake.", // sessions will be cancelled in 2 hours unless they remove the dates.
    ); // (end of the message)
  const n = Number(data ?? 0); // How many sessions were cancelled.
  return done(n ? `Saved. ${n} booked session${n === 1 ? " was" : "s were"} cancelled.` : "Saved. No booked sessions were affected."); // Refreshes, updates Teams, and says how many (or none).
} // End of addAwayDates.

// Removes away dates.
export async function removeAwayDates(formData: FormData) {
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("id")); // Reads and checks the id.
  if (!id.success) return; // Bad id: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("remove_away_dates", { p_id: id.data }); // Asks the database to remove them.
  revalidatePath("/schedule"); // Refreshes the schedule page.
} // End of removeAwayDates.

// ---------------------------------------------------------------------------
// Waitlist
// ---------------------------------------------------------------------------
// The rules for joining the waitlist:
const waitSchema = z.object({
  student_id: z.uuid(), // which student,
  subject: z.string().trim().min(1).max(100), // the subject,
  minutes: z.coerce.number().int().min(60).max(240), // how long, 60 to 240 minutes,
  online: z.enum(["0", "1"]), // online or not ("1" or "0"),
  libraries: z.string().optional(), // libraries, as a comma list (optional),
  weekdays: z.string().optional(), // weekdays, as a comma list (optional),
  earliest: z.union([z.iso.time(), z.literal("")]).optional(), // earliest start time (optional),
  latest: z.union([z.iso.time(), z.literal("")]).optional(), // latest start time (optional),
  note: z.string().trim().max(1000).optional(), // a note (optional).
}); // End of the rules.

// Adds a student to the waitlist.
export async function joinWaitlist(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = waitSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: "Couldn't read that request." }; // Problem: plain message.
  const v = parsed.data; // The checked values.
  const libraries = (v.libraries ?? "").split(",").filter(Boolean); // The libraries as a list.
  if (!z.array(z.uuid()).safeParse(libraries).success) return { error: "Couldn't read the libraries." }; // Odd ids: plain message.
  const weekdays = (v.weekdays ?? "").split(",").filter(Boolean).map(Number); // The weekdays as a list of numbers.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("join_waitlist", { // Asks the database to add them:
    p_student: v.student_id, // the student,
    p_subject: v.subject, // the subject,
    p_minutes: v.minutes, // the length,
    p_online: v.online === "1", // online or not,
    p_libraries: libraries, // the libraries,
    p_weekdays: weekdays.length ? weekdays : null, // the weekdays (or none),
    p_earliest: v.earliest || null, // earliest start (or none),
    p_latest: v.latest || null, // latest start (or none),
    p_tutor: null, // no particular tutor,
    p_note: v.note || null, // the note (or none).
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't add to the waitlist.") }; // Failed: plain message.
  return done("Added to the waitlist. CLG will be in touch when a suitable tutor is available."); // Refreshes, updates Teams, and confirms it.
} // End of joinWaitlist.

// Takes a student off the waitlist.
export async function leaveWaitlist(formData: FormData) {
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("id")); // Reads and checks the id.
  if (!id.success) return; // Bad id: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("leave_waitlist", { p_id: id.data, p_reason: "withdrawn" }); // Asks the database to remove them, noting they withdrew.
  revalidatePath("/schedule"); // Refreshes the schedule page.
} // End of leaveWaitlist.

// ---------------------------------------------------------------------------
// Tutor sign on and off
// ---------------------------------------------------------------------------
// The rules for signing on:
const signOnSchema = z.object({
  id: z.uuid(), // which session,
  latitude: z.coerce.number().min(-90).max(90).optional(), // latitude (optional),
  longitude: z.coerce.number().min(-180).max(180).optional(), // longitude (optional).
}); // End of the rules.

// The position (library sessions only) is checked against the library and
// not stored.
export async function signOn(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const raw = Object.fromEntries([...formData.entries()].filter(([, v]) => v !== "")); // The form's fields, leaving out blank ones.
  const parsed = signOnSchema.safeParse(raw); // Checks them against the rules.
  if (!parsed.success) return { error: "Couldn't read that request." }; // Problem: plain message.

  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase.rpc("sign_on", { // Asks the database to sign on, and gets how it went:
    p_session: parsed.data.id, // which session,
    p_latitude: parsed.data.latitude ?? null, // latitude (or none),
    p_longitude: parsed.data.longitude ?? null, // longitude (or none).
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't sign you on.") }; // Failed: plain message.
  const messages: Record<string, string> = { // The message for each result:
    online: "Signed on.", // online,
    at_library: "Signed on at the library.", // at the library,
    not_at_library: "Signed on. The check didn't place you at the library, so CLG will take a look.", // not placed at the library,
    no_location: "Signed on without a location check. CLG will take a look.", // no location given.
  }; // End of the messages.
  return done(messages[String(data)] ?? "Signed on."); // Refreshes, updates Teams, and shows the right message.
} // End of signOn.

// The rules for a different finish time:
const endTimeSchema = z.object({
  id: z.uuid(), // which session,
  date: z.iso.date(), // the date,
  end_time: z.iso.time("Enter the time you finished."), // the time they finished,
  note: z.string().trim().min(1, "Please say why the time was different.").max(500), // why it was different.
}); // End of the rules.

// A tutor records a different finish time, for an admin to confirm.
export async function recordEndTime(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = endTimeSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("record_end_time", { // Asks the database to record it:
    p_session: v.id, // which session,
    // Postgres reads the date and time in Adelaide time.
    p_end: `${v.date} ${v.end_time} Australia/Adelaide`, // the finish date and time,
    p_note: v.note, // and why.
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't save the time.") }; // Failed: plain message.
  return done("Saved. CLG will confirm the time."); // Refreshes, updates Teams, and confirms it.
} // End of recordEndTime.

// The rules for confirming times:
const confirmSchema = z.object({
  id: z.uuid(), // which session,
  date: z.iso.date(), // the date,
  from_time: z.iso.time("Enter the start time."), // the start time,
  to_time: z.iso.time("Enter the end time."), // the end time.
}); // End of the rules.

// An admin confirms a session's actual start and end times.
export async function confirmTimes(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("admin")) return { error: "Only admins can confirm times." }; // Only admins can do this.
  const parsed = confirmSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("confirm_session_times", { // Asks the database to confirm them:
    p_session: v.id, // which session,
    p_from: `${v.date} ${v.from_time} Australia/Adelaide`, // the start, in Adelaide time,
    p_to: `${v.date} ${v.to_time} Australia/Adelaide`, // the end, in Adelaide time.
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't confirm the times.") }; // Failed: plain message.
  return done("Times confirmed."); // Refreshes, updates Teams, and confirms it.
} // End of confirmTimes.

// ---------------------------------------------------------------------------
// Notices
// ---------------------------------------------------------------------------
// Marks all of this person's notices as read.
export async function markNoticesRead() {
  await requireViewer(); // Makes sure someone is signed in.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("mark_notices_read"); // Asks the database to mark them read.
  revalidatePath("/schedule"); // Refreshes the schedule page.
} // End of markNoticesRead.

// The rules for reminder settings:
const noticeSettingsSchema = z.object({
  first_reminder_hours: z.coerce.number().int().min(2).max(168), // hours before a session for the first reminder (2 to 168).
}); // End of the rules.

// Saves when this person's first reminder comes.
export async function saveNoticeSettings(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const parsed = noticeSettingsSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: "Choose when the first reminder comes." }; // Problem: asks them to choose.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("notice_settings").upsert({ // Saves the setting (adds or updates the row):
    account_id: viewer.id, // for this person,
    first_reminder_hours: parsed.data.first_reminder_hours, // the hours.
  }); // End of the save.
  if (error) return { error: "Couldn't save your settings." }; // Failed: plain message.
  return done("Saved. New reminders will use these settings."); // Refreshes, updates Teams, and confirms it.
} // End of saveNoticeSettings.

// ---------------------------------------------------------------------------
// Next term: the family's answer, and school term dates (admins)
// ---------------------------------------------------------------------------
// The rules for the family's next-term answer:
const renewalSchema = z.object({
  id: z.uuid(), // which renewal,
  same_again: z.enum(["yes", "no"], "Please say whether you'd like the same again."), // the same again, yes or no,
  holidays: z.enum(["yes", "no"], "Please say whether you'd like holiday sessions."), // holiday sessions, yes or no,
  change_what: z.enum(["time", "tutor", "both"]).optional(), // what to change (optional),
  change_reason: z.string().trim().max(1000).optional(), // why (optional),
  feedback: z.string().trim().max(2000).optional(), // feedback (optional).
}); // End of the rules.

// A family answers whether they'd like the same again next term.
export async function answerRenewal(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = renewalSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  if (v.same_again === "no" && !v.change_what) return { error: "Please say what you'd like to change." }; // "No" needs what to change.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("answer_renewal", { // Asks the database to save the answer:
    p_renewal: v.id, // which renewal,
    p_same_again: v.same_again === "yes", // same again or not,
    p_holidays: v.holidays === "yes", // holiday sessions or not,
    p_change_what: v.same_again === "no" ? (v.change_what ?? null) : null, // what to change (only when "no"),
    p_change_reason: v.change_reason || null, // why (or none),
    p_feedback: v.feedback || null, // feedback (or none),
    p_testimonial_ok: formData.get("testimonial_ok") === "on", // and whether their feedback may be quoted.
  }); // End of the request.
  if (error) return { error: plainError(error, "Couldn't save your answer.") }; // Failed: plain message.
  return done( // Refreshes, updates Teams, and tells them:
    v.same_again === "yes" // if the same again,
      ? "Thank you. Your tutor has been asked to confirm next term." // that the tutor will confirm,
      : "Thank you. CLG will be in touch to arrange the change.", // otherwise that CLG will be in touch.
  ); // (end of the message)
} // End of answerRenewal.

// The rules for school term dates:
const termSchema = z
  .object({ // (the fields:)
    state: z.enum(["SA", "NSW", "VIC", "QLD", "WA", "TAS", "ACT", "NT"]), // the state,
    calendar: z.enum(["public", "private"]).default("public"), // public or private school calendar (public by default),
    term: z.coerce.number().int().min(1).max(4), // term 1 to 4,
    starts_on: z.iso.date("Enter the first day of term."), // the first day,
    ends_on: z.iso.date("Enter the last day of term."), // the last day.
  }) // (end of the fields)
  .refine((v) => v.ends_on > v.starts_on, { message: "The last day must be after the first day." }); // and the last day must be after the first.

// An admin adds or changes a school term's dates.
export async function addTerm(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in (the database checks for an admin).
  const parsed = termSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("school_terms").upsert( // Saves the term (adds, or updates if it's already there):
    { // (the values:)
      state: v.state, // the state,
      calendar: v.calendar, // the calendar,
      year: Number(v.starts_on.slice(0, 4)), // the year, from the first day,
      term: v.term, // the term number,
      starts_on: v.starts_on, // the first day,
      ends_on: v.ends_on, // the last day.
    }, // (end of the values)
    { onConflict: "state,calendar,year,term" }, // The same state, calendar, year and term means the same row.
  ); // End of the save.
  if (error) return { error: "Couldn't save the term. Only CLG admins can change term dates." }; // Failed: plain message.
  return done("Term saved."); // Refreshes, updates Teams, and confirms it.
} // End of addTerm.

// ---------------------------------------------------------------------------
// Tutors confirm their availability each term
// ---------------------------------------------------------------------------
// A tutor confirms (or changes) their availability for next term.
export async function confirmAvailability(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("id")); // Reads and checks the id.
  if (!id.success) return { error: "Couldn't read that check." }; // Bad id: plain message.
  const changed = formData.get("answer") === "changed"; // True if they said it has changed.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("confirm_availability", { p_check: id.data, p_changed: changed }); // Asks the database to save the answer.
  if (error) return { error: plainError(error, "Couldn't save your answer.") }; // Failed: plain message.
  return done("Thanks. Your availability is confirmed for next term."); // Refreshes, updates Teams, and thanks them.
} // End of confirmAvailability.

// ---------------------------------------------------------------------------
// Where a child can have sessions (families and admins)
// ---------------------------------------------------------------------------
// How long the family wants to book for (families and CLG admins).
const bookingLengthSchema = z.object({
  student_id: z.uuid("Couldn't read which child this is for."), // which child,
  book_until: z.iso.date("Please choose the last date."), // the last date to book until,
  school_holidays: z.enum(["yes", "no"], "Please say whether sessions go ahead in school holidays."), // sessions in school holidays, yes or no,
  public_holidays: z.enum(["yes", "no"], "Please say whether sessions go ahead on public holidays."), // sessions on public holidays, yes or no.
}); // End of the rules.

// Saves how long a family wants to book for.
export async function saveBookingLength(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const v = bookingLengthSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!v.success) return { error: v.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("set_booking_length", { // Asks the database to save it:
    p_student: v.data.student_id, // the child,
    p_until: v.data.book_until, // the last date,
    p_school_holidays: v.data.school_holidays === "yes", // school holidays or not,
    p_public_holidays: v.data.public_holidays === "yes", // public holidays or not.
  }); // End of the request.
  if (error) { // It failed:
    return { error: error.code === "23514" ? "The last date must be from today and within a year." : plainError(error, "Couldn't save this.") }; // explains the date rule, or a plain message.
  } // End of the failure case.
  return done("Saved. You can change this at any time."); // Refreshes, updates Teams, and confirms it.
} // End of saveBookingLength.

// Saves where and when a child can have sessions.
export async function saveStudentPlaces(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const student = z.uuid().safeParse(formData.get("student_id")); // Reads and checks the child's id.
  if (!student.success) return { error: "Couldn't read which child this is for." }; // Bad id: plain message.
  const libraries = z.array(z.uuid()).safeParse(formData.getAll("library")); // Checks the ticked libraries' ids.
  if (!libraries.success) return { error: "Couldn't read the libraries you chose." }; // Odd ids: plain message.
  let online = formData.get("online") === "on"; // True if "online" is ticked.
  let libraryIds = libraries.data; // The chosen libraries.
  const supabase = await createClient(); // Connects to the database.
  // Families only give preferred times: keep the places CLG has set.
  if (formData.get("keep_places") === "1") { // If the family is only giving times:
    const { data: current } = await supabase // reads the current places:
      .from("student_places") // from the student places table,
      .select("online, library_ids") // online and libraries,
      .eq("student_id", student.data) // for this child,
      .maybeSingle(); // (one at most).
    online = current?.online ?? true; // keeps online as it was (yes if not set),
    libraryIds = (current?.library_ids as string[] | undefined) ?? []; // and keeps the libraries as they were.
  } else if (!online && libraryIds.length === 0) { // Otherwise, if nothing was chosen:
    return { error: "Choose online, at least one library, or both." }; // asks for online, a library, or both.
  } // End of that check.
  const days = formData.getAll("preferred_day").map(Number).filter((d) => Number.isInteger(d) && d >= 1 && d <= 7); // The preferred weekdays, only 1 to 7.
  const PARTS = ["morning", "midday", "afternoon", "evening"]; // The parts of the day allowed.
  const parts = formData.getAll("preferred_part").map(String).filter((p) => PARTS.includes(p)); // The preferred parts of the day, only allowed ones.

  const { error } = await supabase.from("student_places").upsert({ // Saves (adds or updates the row):
    student_id: student.data, // the child,
    online, // online or not,
    library_ids: libraryIds, // the libraries,
    preferred_days: days.length ? days : null, // preferred days (or none),
    preferred_parts: parts.length ? parts : null, // preferred parts of the day (or none),
    // Exact times were replaced by parts of the day (2 Nov 2026).
    preferred_from: null, // clears the old exact start time,
    preferred_to: null, // and the old exact end time,
    preferred_school_hours: formData.get("preferred_school_hours") === "on", // whether school hours suit,
    tutor_preferences: String(formData.get("tutor_preferences") ?? "").trim().slice(0, 1000) || null, // any tutor preferences (up to 1,000 characters, or none).
  }); // End of the save.
  if (error) return { error: "Couldn't save the places." }; // Failed: plain message.
  return done("Saved. Offers will start from these places and preferences."); // Refreshes, updates Teams, and confirms it.
} // End of saveStudentPlaces.
