// Summary: the server actions for the Student Success Program (Carla, 22 Nov
// 2026). A family ticks a box to ask about the program (or cancels the
// request). An owner or Operations admin approves a place (which holds one
// of the limited places and makes the program invoices: the $500 deposit,
// then the rest in full, monthly or weekly), declines a request, withdraws
// a place before the deposit is paid, records a payment agreement, changes
// a place's details, takes a student out of the program, or changes the
// number of places and the days before a missed payment forfeits the place.
// The deposit secures the place; the program switches on once everything is
// paid (the database does that when billing marks each invoice paid). The
// database checks every rule again. The book-till date is saved through
// scheduling's own booking-length function, so the program never writes
// scheduling's tables. See docs/features/student-success-program.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { FULL_ADMIN, requireAdminLevel, requireViewer } from "@/lib/auth"; // The owner and Operations admin levels, the admin level check, and the signed-in person check.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message. Messages the database wrote
// for people (codes 42501, 22023 and P0002) are shown as they are; anything
// else gets the general message given.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the database error and a general message.
  return ["42501", "22023", "P0002"].includes(error.code ?? "") ? error.message : fallback; // The database's own words, or the general message.
} // End of plainError.

// Refreshes the pages that show the program.
function refresh(): void { // No inputs.
  revalidatePath("/admin"); // The admin page (the program card and student details card).
  revalidatePath("/matching"); // The Matching page (program label and order).
  revalidatePath("/dashboard/parent"); // The family dashboard (the child's program box).
  revalidatePath("/dashboard/student"); // The student dashboard (an adult learner's program box).
  revalidatePath("/billing"); // The Billing page (the program invoices to pay).
} // End of refresh.

// The id of the student a form is about.
const studentId = z.uuid("Could not read which student this is for."); // must be a proper id.

// A date box's value: a real date, or empty.
const optionalDate = z.union([z.iso.date("Please choose a real date."), z.literal("")]).optional(); // "YYYY-MM-DD" or nothing.

// The details an admin gives for a place: sessions, book-till date, holidays and a note.
const placeDetails = z.object({ // The rules:
  student_id: studentId, // which student,
  sessions: z.union([z.coerce.number().int("Please enter a whole number of sessions.").min(1, "Please enter at least 1 session.").max(200, "Please enter 200 sessions or fewer."), z.literal("")]).optional(), // sessions planned (optional),
  book_until: optionalDate, // the book-till date (optional),
  school_holidays: z.enum(["yes", "no"]).optional(), // sessions in school holidays, yes or no,
  public_holidays: z.enum(["yes", "no"]).optional(), // sessions on public holidays, yes or no,
  note: z.string().trim().max(500, "Please keep the note under 500 characters.").optional(), // and CLG's own note.
}); // End of the rules.

// Saves the book-till date as the student's booking length (scheduling's own
// function). Gives back a plain problem message, or nothing if it worked.
async function saveBookingLength(supabase: Awaited<ReturnType<typeof createClient>>, d: z.infer<typeof placeDetails>): Promise<string | null> { // Takes the connection and the checked answers.
  if (!d.book_until) return null; // No date given: nothing to save.
  const { error } = await supabase.rpc("set_booking_length", { // Asks scheduling to save it:
    p_student: d.student_id, // the student,
    p_until: d.book_until, // the last date,
    p_school_holidays: d.school_holidays === "yes", // school holidays or not,
    p_public_holidays: d.public_holidays === "yes", // public holidays or not.
  }); // End of the request.
  if (!error) return null; // Worked: no problem.
  return error.code === "23514" // Explains what went wrong:
    ? "The book-till date must be from today and within a year, so the student's booking length was not changed." // the date is outside scheduling's rule,
    : "The student's booking length could not be changed. Please set it on the Schedule page."; // or something else.
} // End of saveBookingLength.

// ---------------------------------------------------------------------------
// The family's side
// ---------------------------------------------------------------------------

// The family ticks the box to ask about the program.
export async function askAboutStudentSuccessProgram(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Must be signed in (the database checks they are the student's family).
  const parsed = z.object({ // The rules:
    student_id: studentId, // which student,
    ask: z.literal("yes", { error: "Please tick the box to ask about the Student Success Program." }), // the tick box must be ticked,
    note: z.string().trim().max(500, "Please keep your message under 500 characters.").optional(), // and an optional message.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("ssp_request", { p_student: parsed.data.student_id, p_note: parsed.data.note || null }); // Asks the database to save the request.
  if (error) return { error: plainError(error, "We could not send your request. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Thank you. CLG will look at your request and let you know. Places are limited." }; // Confirms.
} // End of askAboutStudentSuccessProgram.

// The family cancels their request (before CLG decides).
export async function cancelStudentSuccessRequest(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Must be signed in (the database checks they are the student's family).
  const student = studentId.safeParse(formData.get("student_id")); // Reads and checks the student's id.
  if (!student.success) return { error: student.error.issues[0].message }; // Bad id: plain message.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("ssp_cancel_request", { p_student: student.data }); // Asks the database to cancel it.
  if (error) return { error: plainError(error, "We could not cancel your request. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Your request has been cancelled." }; // Confirms.
} // End of cancelStudentSuccessRequest.

// ---------------------------------------------------------------------------
// The admin's side (owner and Operations admins)
// ---------------------------------------------------------------------------

// The money part of approving a place: the program total, the payment plan
// and the date the last payment is due by.
const programMoney = z.object({ // The rules:
  total: z.coerce.number({ error: "Please enter the program total in dollars." }).positive("Please enter the program total in dollars.").max(100000, "Please enter a total of $100,000 or less."), // the total in dollars (deposit included),
  plan: z.enum(["full", "monthly", "weekly"], { error: "Please choose a payment plan: pay in full, monthly or weekly." }), // the payment plan,
  finish_on: z.iso.date("Please choose the date the last payment is due by."), // and the finish payment date.
}); // End of the rules.

// Approves a place and makes the program invoices (deposit first).
export async function approveStudentSuccessPlace(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(FULL_ADMIN); // Must be the owner or an Operations admin, with two-step sign-in.
  const form = Object.fromEntries(formData); // The form's answers.
  const parsed = placeDetails.safeParse(form); // Checks the place details.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const money = programMoney.safeParse(form); // Checks the money details.
  if (!money.success) return { error: money.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: summary, error } = await supabase.rpc("ssp_approve", { // Asks the database to approve the place:
    p_student: d.student_id, // the student,
    p_total_cents: Math.round(money.data.total * 100), // the program total in cents,
    p_plan: money.data.plan, // the payment plan,
    p_finish_on: money.data.finish_on, // the finish payment date,
    p_sessions: d.sessions === "" || d.sessions === undefined ? null : d.sessions, // sessions planned (or none),
    p_book_until: d.book_until || null, // the book-till date (or none),
    p_note: d.note || null, // and the note.
  }); // End of the request.
  if (error) return { error: plainError(error, "We could not approve the place. Please try again.") }; // Failed: plain message (nothing was changed).
  const lengthProblem = await saveBookingLength(supabase, d); // Saves the book-till date as the booking length too.
  refresh(); // Refreshes the pages.
  const done = `Place approved. Payments: ${summary ?? ""} The family has been told, and each payment is taken from their saved card or bank account on its due date. The program switches on once everything is paid.`; // What happened.
  return lengthProblem ? { error: `${done} ${lengthProblem}` } : { message: done }; // Confirms, with any booking length problem.
} // End of approveStudentSuccessPlace.

// Records (or ends) a payment agreement with the family: the place is not
// forfeited for missed payments until the date given.
export async function saveStudentSuccessAgreement(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(FULL_ADMIN); // Must be the owner or an Operations admin, with two-step sign-in.
  const parsed = z.object({ // The rules:
    student_id: studentId, // which student,
    until: optionalDate, // the date the agreement runs to (empty ends it),
    note: z.string().trim().max(500, "Please keep the note under 500 characters.").optional(), // and what was agreed.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("ssp_set_agreement", { // Asks the database to save it:
    p_student: parsed.data.student_id, // the student,
    p_until: parsed.data.until || null, // the date (or none, which ends it),
    p_note: parsed.data.note || null, // and the note.
  }); // End of the request.
  if (error) return { error: plainError(error, "We could not save the payment agreement. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: parsed.data.until ? "Payment agreement saved. The place will not be forfeited before that date." : "Payment agreement ended." }; // Confirms.
} // End of saveStudentSuccessAgreement.

// Changes the details of a place that is approved or in the program.
export async function saveStudentSuccessDetails(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(FULL_ADMIN); // Must be the owner or an Operations admin, with two-step sign-in.
  const parsed = placeDetails.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("ssp_save_details", { // Asks the database to save the details:
    p_student: d.student_id, // the student,
    p_sessions: d.sessions === "" || d.sessions === undefined ? null : d.sessions, // sessions planned (or none),
    p_book_until: d.book_until || null, // the book-till date (or none),
    p_note: d.note || null, // and the note.
  }); // End of the request.
  if (error) return { error: plainError(error, "We could not save the program details. Please try again.") }; // Failed: plain message.
  const lengthProblem = await saveBookingLength(supabase, d); // Saves the book-till date as the booking length too.
  refresh(); // Refreshes the pages.
  return lengthProblem ? { error: `The program details were saved. ${lengthProblem}` } : { message: "Program details saved." }; // Confirms, with any booking length problem.
} // End of saveStudentSuccessDetails.

// Declines a request, with an optional reason the family sees.
export async function declineStudentSuccessRequest(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(FULL_ADMIN); // Must be the owner or an Operations admin, with two-step sign-in.
  const parsed = z.object({ // The rules:
    student_id: studentId, // which student,
    reason: z.string().trim().max(500, "Please keep the reason under 500 characters.").optional(), // and an optional reason.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("ssp_decline", { p_student: parsed.data.student_id, p_reason: parsed.data.reason || null }); // Asks the database to decline it.
  if (error) return { error: plainError(error, "We could not decline the request. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Request declined. The family has been told." }; // Confirms.
} // End of declineStudentSuccessRequest.

// Withdraws a place before the deposit is paid (the program invoices are cancelled).
export async function withdrawStudentSuccessPlace(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(FULL_ADMIN); // Must be the owner or an Operations admin, with two-step sign-in.
  const parsed = z.object({ // The rules:
    student_id: studentId, // which student,
    reason: z.string().trim().min(5, "Please give a reason (the family sees it).").max(500, "Please keep the reason under 500 characters."), // and a reason.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("ssp_withdraw", { p_student: parsed.data.student_id, p_reason: parsed.data.reason }); // Asks the database to withdraw it.
  if (error) return { error: plainError(error, "We could not withdraw the place. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Place withdrawn and the program invoices cancelled. If they were already in Xero, void them there too." }; // Confirms, with a reminder about Xero.
} // End of withdrawStudentSuccessPlace.

// Takes a student out of the program.
export async function leaveStudentSuccessProgram(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(FULL_ADMIN); // Must be the owner or an Operations admin, with two-step sign-in.
  const student = studentId.safeParse(formData.get("student_id")); // Reads and checks the student's id.
  if (!student.success) return { error: student.error.issues[0].message }; // Bad id: plain message.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("ssp_leave", { p_student: student.data }); // Asks the database to take them out.
  if (error) return { error: plainError(error, "We could not take this student out of the program. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Done. This student is no longer in the Student Success Program, and any unpaid program invoices were cancelled (void them in Xero too). Any refund follows CLG's terms and is done in Billing." }; // Confirms.
} // End of leaveStudentSuccessProgram.

// Changes the number of places and the days after a missed payment before the place is forfeited.
export async function saveStudentSuccessPlaces(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(FULL_ADMIN); // Must be the owner or an Operations admin, with two-step sign-in.
  const parsed = z.object({ // The rules:
    spaces: z.coerce.number().int("Please enter a whole number of places.").min(0, "Places cannot be below 0.").max(1000, "Please enter 1000 places or fewer."), // places in total,
    forfeit_days: z.coerce.number().int("Please enter a whole number of days.").min(1, "Please allow at least 1 day.").max(60, "Please allow 60 days or fewer."), // and days before a missed payment forfeits the place.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("ssp_set_places", { p_spaces: parsed.data.spaces, p_forfeit_days: parsed.data.forfeit_days }); // Asks the database to save them.
  if (error) return { error: plainError(error, "We could not save the number of places. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Saved." }; // Confirms.
} // End of saveStudentSuccessPlaces.
