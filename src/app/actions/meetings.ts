// Summary: the server actions for booking a meeting with Carla (Carla, 22 Nov
// 2026). Staff send a request with what it is About, the Context, their Goal,
// how urgent it is and 2 or 3 times they can do; they can accept a different
// time Carla offers, or cancel. Carla confirms a time, offers another,
// answers without a meeting, or marks a meeting as held. The database checks
// every rule again. See docs/features/meetings-with-carla.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in (the database checks the rest).
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message. Messages the database wrote
// for people (codes 42501, 22023 and P0002) are shown as they are; anything
// else gets the general message.
function plainError(error: { code?: string; message: string }): string { // Takes the database error.
  return ["42501", "22023", "P0002"].includes(error.code ?? "") ? error.message : "We could not save this. Please try again."; // The database's own words, or the general message.
} // End of plainError.

// Runs one database request and gives back the form reply.
async function run(name: string, args: Record<string, unknown>, done: string): Promise<FormState> { // Takes the function, its inputs, and the thank you message.
  await requireViewer(); // Makes sure someone is signed in.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc(name, args); // Asks the database.
  if (error) return { error: plainError(error) }; // Failed: plain message.
  revalidatePath("/meetings"); // Refreshes the page.
  return { message: done }; // Confirms.
} // End of run.

// A time typed in the form ("YYYY-MM-DDTHH:MM", Adelaide time), or blank.
const timeText = z.union([z.literal(""), z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/, "Please check the date and time.")]).default(""); // Blank or a date and time.

// The rules for a new request.
const requestSchema = z.object({ // The form's fields:
  about: z.string().trim().min(3, "Please say what the meeting is about.").max(200, "Please keep it under 200 characters."), // About,
  context: z.string().trim().min(2, "Please give some context.").max(3000, "Please keep the context under 3000 characters."), // Context,
  goal: z.string().trim().min(2, "Please write your goal for the meeting.").max(1000, "Please keep the goal under 1000 characters."), // Goal,
  urgency: z.enum(["urgent", "this_week", "no_rush"], { message: "Please choose how urgent it is." }), // how urgent,
  length: z.coerce.number().refine((n) => [15, 30, 45, 60].includes(n), "Please choose how long it needs."), // how long,
  how: z.enum(["online", "phone", "in_person"], { message: "Please choose how to meet." }), // how to meet,
  time1: timeText, // first time,
  time2: timeText, // second time,
  time3: timeText, // third time (optional).
}); // End of the rules.

// Sends a meeting request to Carla.
export async function sendMeetingRequest(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = requestSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!p.success) return { error: p.error.issues[0].message }; // Shows the first rule that failed.
  const times = [p.data.time1, p.data.time2, p.data.time3].filter(Boolean); // The times filled in.
  if (times.length < 2) return { error: "Please suggest at least 2 times you can do." }; // Too few: plain message.
  return run("meeting_request_send", { p_about: p.data.about, p_context: p.data.context, p_goal: p.data.goal, p_urgency: p.data.urgency, p_length: p.data.length, p_how: p.data.how, p_times: times }, "Sent. Carla replies within 1 business day, and straight away when it is urgent."); // Sends it.
} // End of sendMeetingRequest.

// Reads a request id from the form.
function readId(formData: FormData): string | null { // Takes the form.
  const id = z.uuid().safeParse(formData.get("id")); // Reads and checks the id.
  return id.success ? id.data : null; // The id, or nothing.
} // End of readId.

// Cancels a request (the person who asked, or Carla).
export async function cancelMeetingRequest(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const id = readId(formData); // Which request.
  if (!id) return { error: "Could not read which request this is." }; // Bad id: plain message.
  const note = String(formData.get("note") ?? "").trim().slice(0, 1000); // Any note (kept short).
  return run("meeting_request_cancel", { p_id: id, p_note: note || null }, "Cancelled. The other person has been told."); // Cancels it.
} // End of cancelMeetingRequest.

// Accepts the different time Carla offered.
export async function acceptMeetingTime(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const id = readId(formData); // Which request.
  if (!id) return { error: "Could not read which request this is." }; // Bad id: plain message.
  return run("meeting_request_accept_time", { p_id: id }, "Accepted. Carla has been told."); // Accepts it.
} // End of acceptMeetingTime.

// Carla confirms a time: "pick" is one of the suggested times, or "other" uses the typed time.
export async function confirmMeeting(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const id = readId(formData); // Which request.
  if (!id) return { error: "Could not read which request this is." }; // Bad id: plain message.
  const pick = String(formData.get("pick") ?? ""); // The chosen suggested time, or "other".
  const at = pick === "other" ? String(formData.get("other") ?? "") : pick; // The time to use.
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(at)) return { error: "Please choose one of their times, or type a different time." }; // No time: plain message.
  const note = String(formData.get("note") ?? "").trim().slice(0, 2000); // Any note (kept short).
  return run("meeting_request_confirm", { p_id: id, p_at: at, p_note: note || null }, pick === "other" ? "Different time offered. They have been asked to accept it." : "Confirmed. They have been told."); // Confirms or offers it.
} // End of confirmMeeting.

// Carla answers without a meeting.
export async function answerMeetingRequest(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const id = readId(formData); // Which request.
  if (!id) return { error: "Could not read which request this is." }; // Bad id: plain message.
  const note = String(formData.get("note") ?? "").trim().slice(0, 2000); // The answer (kept short).
  if (note.length < 2) return { error: "Please write your answer." }; // No answer: plain message.
  return run("meeting_request_answer", { p_id: id, p_note: note }, "Answered. They have been told."); // Answers it.
} // End of answerMeetingRequest.

// Carla marks a confirmed meeting as held.
export async function markMeetingHeld(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const id = readId(formData); // Which request.
  if (!id) return { error: "Could not read which request this is." }; // Bad id: plain message.
  return run("meeting_request_held", { p_id: id }, "Marked as held."); // Marks it.
} // End of markMeetingHeld.
