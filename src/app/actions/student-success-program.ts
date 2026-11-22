// Summary: the server actions for the Student Success Program (Carla, 22 Nov
// 2026). An owner or Operations admin puts a student in the program (with
// sessions planned, the book-till date, the deposit date and a note) or takes
// them out. The database checks every rule again. The book-till date is
// saved through scheduling's own booking-length function, so the program
// never writes scheduling's tables. See docs/features/student-success-program.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireAdminLevel } from "@/lib/auth"; // Makes sure the person is an admin at the right level.
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
  revalidatePath("/admin"); // The admin page (student details card).
  revalidatePath("/admin/matching"); // The Matching page (program label and order).
} // End of refresh.

// A date box's value: a real date, or empty.
const optionalDate = z.union([z.iso.date("Please choose a real date."), z.literal("")]).optional(); // "YYYY-MM-DD" or nothing.

// Puts a student in the program, or updates their program details.
export async function saveStudentSuccessProgram(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(["owner", "operations"]); // Must be the owner or an Operations admin, with two-step sign-in.
  const parsed = z.object({ // The rules:
    student_id: z.uuid("Could not read which student this is for."), // which student,
    sessions: z.union([z.coerce.number().int("Please enter a whole number of sessions.").min(1, "Please enter at least 1 session.").max(200, "Please enter 200 sessions or fewer."), z.literal("")]).optional(), // sessions planned (optional),
    book_until: optionalDate, // the book-till date (optional),
    school_holidays: z.enum(["yes", "no"]).optional(), // sessions in school holidays, yes or no,
    public_holidays: z.enum(["yes", "no"]).optional(), // sessions on public holidays, yes or no,
    deposit_paid_on: optionalDate, // when the deposit was paid (optional),
    note: z.string().trim().max(500, "Please keep the note under 500 characters.").optional(), // and a note.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("ssp_enrol", { // Asks the database to save the program details:
    p_student: d.student_id, // the student,
    p_sessions: d.sessions === "" || d.sessions === undefined ? null : d.sessions, // sessions planned (or none),
    p_book_until: d.book_until || null, // the book-till date (or none),
    p_deposit_paid_on: d.deposit_paid_on || null, // the deposit date (or none),
    p_note: d.note || null, // and the note.
  }); // End of the request.
  if (error) return { error: plainError(error, "We could not save the Student Success Program details. Please try again.") }; // Failed: plain message.
  if (d.book_until) { // A book-till date was given: save it as the student's booking length too.
    const { error: lengthError } = await supabase.rpc("set_booking_length", { // Asks scheduling to save it:
      p_student: d.student_id, // the student,
      p_until: d.book_until, // the last date,
      p_school_holidays: d.school_holidays === "yes", // school holidays or not,
      p_public_holidays: d.public_holidays === "yes", // public holidays or not.
    }); // End of the request.
    if (lengthError) { // The booking length was not saved:
      refresh(); // still refreshes, because the program details were saved,
      return { error: lengthError.code === "23514" ? "The program details were saved, but the book-till date must be from today and within a year, so the booking length was not changed." : "The program details were saved, but the booking length could not be changed. Please set it on the Schedule page." }; // and explains.
    } // End of the failure case.
  } // End of the booking length.
  refresh(); // Refreshes the pages.
  return { message: "Saved. This student is in the Student Success Program." }; // Confirms.
} // End of saveStudentSuccessProgram.

// Takes a student out of the program.
export async function leaveStudentSuccessProgram(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(["owner", "operations"]); // Must be the owner or an Operations admin, with two-step sign-in.
  const student = z.uuid().safeParse(formData.get("student_id")); // Reads and checks the student's id.
  if (!student.success) return { error: "Could not read which student this is for." }; // Bad id: plain message.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("ssp_leave", { p_student: student.data }); // Asks the database to take them out.
  if (error) return { error: plainError(error, "We could not take this student out of the program. Please try again.") }; // Failed: plain message.
  refresh(); // Refreshes the pages.
  return { message: "Done. This student is no longer in the Student Success Program." }; // Confirms.
} // End of leaveStudentSuccessProgram.
