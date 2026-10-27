"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// The database explains most refusals in plain words (see the scheduling
// migration). Pass those on; hide anything technical.
function plainError(error: { message: string; code?: string } | null, fallback: string): string {
  if (!error) return fallback;
  const technical = /violates|syntax|relation|column|function|permission denied|uuid/i.test(error.message);
  return technical ? fallback : error.message;
}

function done(message: string): FormState {
  revalidatePath("/schedule");
  return { message };
}

// ---------------------------------------------------------------------------
// Families (and admins during the pilot) ask for a weekly booking
// ---------------------------------------------------------------------------
const bookingSchema = z
  .object({
    student_id: z.uuid(),
    subject: z.string().trim().min(1).max(100),
    tutor_id: z.uuid(),
    weekday: z.coerce.number().int().min(1).max(7),
    start_time: z.iso.time(),
    minutes: z.coerce.number().int().min(60).max(240),
    delivery: z.enum(["online", "library"]),
    library_id: z.union([z.uuid(), z.literal("")]).optional(),
    first_date: z.iso.date("Choose the first date."),
    last_date: z.iso.date("Choose the last date."),
    note: z.string().trim().max(1000).optional(),
  })
  .refine((v) => v.last_date >= v.first_date, { message: "The last date must be after the first date." });

export async function requestBooking(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = bookingSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;

  const supabase = await createClient();
  const { error } = await supabase.rpc("request_booking", {
    p_student: v.student_id,
    p_subject: v.subject,
    p_tutor: v.tutor_id,
    p_weekday: v.weekday,
    p_start: v.start_time,
    p_minutes: v.minutes,
    p_delivery: v.delivery,
    p_library: v.delivery === "library" ? v.library_id || null : null,
    p_first_date: v.first_date,
    p_last_date: v.last_date,
    p_note: v.note || null,
  });
  if (error) return { error: plainError(error, "Couldn't send the request. Please try again.") };
  return done("Request sent. The tutor has 48 hours to confirm. You'll see it under Bookings.");
}

// ---------------------------------------------------------------------------
// Tutors answer requests
// ---------------------------------------------------------------------------
const answerSchema = z.object({
  booking_id: z.uuid(),
  answer: z.enum(["accept", "decline"]),
  note: z.string().trim().max(1000).optional(),
});

export async function answerBooking(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = answerSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Choose accept or decline." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("respond_to_booking", {
    p_booking: parsed.data.booking_id,
    p_accept: parsed.data.answer === "accept",
    p_note: parsed.data.note || null,
  });
  if (error) return { error: plainError(error, "Couldn't save your answer.") };
  return done(parsed.data.answer === "accept" ? "Accepted. The sessions are booked." : "Declined. CLG will offer the family other times.");
}

// ---------------------------------------------------------------------------
// Cancelling
// ---------------------------------------------------------------------------
const cancelSchema = z.object({
  id: z.uuid(),
  reason: z.string().trim().max(500).optional(),
  on_behalf: z.enum(["", "family", "tutor", "admin"]).optional(),
});

export async function cancelSession(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = cancelSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Couldn't read that request." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_session", {
    p_session: parsed.data.id,
    p_reason: parsed.data.reason || null,
    p_for: parsed.data.on_behalf || null,
  });
  if (error) return { error: plainError(error, "Couldn't cancel the session.") };
  return done("Session cancelled.");
}

export async function stopBooking(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = cancelSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Couldn't read that request." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_booking", {
    p_booking: parsed.data.id,
    p_reason: parsed.data.reason || null,
    p_for: parsed.data.on_behalf || null,
  });
  if (error) return { error: plainError(error, "Couldn't stop the booking.") };
  return done("Booking stopped. Its future sessions are cancelled.");
}

// ---------------------------------------------------------------------------
// After a session: completed or no-show
// ---------------------------------------------------------------------------
const outcomeSchema = z.object({ id: z.uuid(), outcome: z.enum(["completed", "no_show"]) });

export async function recordOutcome(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = outcomeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Choose done or no-show." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("record_session_outcome", {
    p_session: parsed.data.id,
    p_status: parsed.data.outcome,
  });
  if (error) return { error: plainError(error, "Couldn't save that.") };
  return done("Saved.");
}

// ---------------------------------------------------------------------------
// Tutors: how and where they work
// ---------------------------------------------------------------------------
export async function saveTutorPlaces(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("tutor")) return { error: "Only tutors can set this." };

  const online = formData.get("online") === "on";
  const inPerson = formData.get("in_person") === "on";
  const learningSupport = formData.get("learning_support") === "on";
  if (!online && !inPerson) return { error: "Choose online, in person, or both." };
  const libraries = z.array(z.uuid()).safeParse(formData.getAll("library"));
  if (!libraries.success) return { error: "Couldn't read the libraries you chose." };
  if (inPerson && libraries.data.length === 0) return { error: "Tick at least one library for in-person sessions." };

  const supabase = await createClient();
  const settings = await supabase.from("tutor_session_settings").upsert({
    tutor_id: viewer.id,
    online,
    in_person: inPerson,
    learning_support: learningSupport,
  });
  if (settings.error) return { error: "Couldn't save your settings." };

  const current = await supabase.from("tutor_places").select("library_id").eq("tutor_id", viewer.id);
  const had = new Set((current.data ?? []).map((r) => r.library_id as string));
  const want = new Set(libraries.data);
  const remove = [...had].filter((id) => !want.has(id));
  const add = [...want].filter((id) => !had.has(id)).map((library_id) => ({ tutor_id: viewer.id, library_id }));
  if (remove.length) {
    const r = await supabase.from("tutor_places").delete().eq("tutor_id", viewer.id).in("library_id", remove);
    if (r.error) return { error: "Couldn't update your libraries." };
  }
  if (add.length) {
    const r = await supabase.from("tutor_places").insert(add);
    if (r.error) return { error: "Couldn't update your libraries." };
  }
  return done("Saved.");
}

// ---------------------------------------------------------------------------
// Admins: the list of libraries
// ---------------------------------------------------------------------------
const librarySchema = z.object({
  name: z.string().trim().min(1, "Enter the library's name.").max(200),
  suburb: z.string().trim().max(100).optional(),
  address: z.string().trim().max(300).optional(),
  latitude: z.union([z.coerce.number().min(-90).max(90), z.literal("")]).optional(),
  longitude: z.union([z.coerce.number().min(-180).max(180), z.literal("")]).optional(),
});

export async function addLibrary(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("admin")) return { error: "Only admins can add libraries." };
  const parsed = librarySchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.from("libraries").insert({
    name: parsed.data.name,
    suburb: parsed.data.suburb || null,
    address: parsed.data.address || null,
    latitude: parsed.data.latitude === "" ? null : (parsed.data.latitude ?? null),
    longitude: parsed.data.longitude === "" ? null : (parsed.data.longitude ?? null),
  });
  if (error) return { error: error.code === "23505" ? "That library is already listed." : "Couldn't add the library." };
  return done("Library added.");
}

export async function setLibraryActive(formData: FormData) {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("admin")) return;
  const id = z.uuid().safeParse(formData.get("id"));
  if (!id.success) return;
  const supabase = await createClient();
  await supabase
    .from("libraries")
    .update({ active: formData.get("active") === "true" })
    .eq("id", id.data);
  revalidatePath("/schedule");
}

// ---------------------------------------------------------------------------
// Away dates
// ---------------------------------------------------------------------------
const awaySchema = z
  .object({
    who: z.string().min(1, "Choose who will be away."),
    from_date: z.iso.date("Choose the first day away."),
    to_date: z.iso.date("Choose the last day away."),
    reason: z.string().trim().max(300).optional(),
  })
  .refine((v) => v.to_date >= v.from_date, { message: "The last day must be on or after the first day." });

// "who" is "me" for a tutor's own dates, or "student:<id>" for a child.
export async function addAwayDates(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  const parsed = awaySchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const studentId = v.who.startsWith("student:") ? v.who.slice(8) : null;
  if (studentId && !z.uuid().safeParse(studentId).success) return { error: "Choose who will be away." };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("add_away_dates", {
    p_tutor: studentId ? null : viewer.id,
    p_student: studentId,
    p_from: v.from_date,
    p_to: v.to_date,
    p_reason: v.reason || null,
  });
  if (error) return { error: plainError(error, "Couldn't save the away dates.") };
  const n = Number(data ?? 0);
  return done(n ? `Saved. ${n} booked session${n === 1 ? " was" : "s were"} cancelled.` : "Saved. No booked sessions were affected.");
}

export async function removeAwayDates(formData: FormData) {
  await requireViewer();
  const id = z.uuid().safeParse(formData.get("id"));
  if (!id.success) return;
  const supabase = await createClient();
  await supabase.rpc("remove_away_dates", { p_id: id.data });
  revalidatePath("/schedule");
}

// ---------------------------------------------------------------------------
// Waitlist
// ---------------------------------------------------------------------------
const waitSchema = z.object({
  student_id: z.uuid(),
  subject: z.string().trim().min(1).max(100),
  minutes: z.coerce.number().int().min(60).max(240),
  online: z.enum(["0", "1"]),
  libraries: z.string().optional(),
  weekdays: z.string().optional(),
  earliest: z.union([z.iso.time(), z.literal("")]).optional(),
  latest: z.union([z.iso.time(), z.literal("")]).optional(),
  note: z.string().trim().max(1000).optional(),
});

export async function joinWaitlist(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = waitSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Couldn't read that request." };
  const v = parsed.data;
  const libraries = (v.libraries ?? "").split(",").filter(Boolean);
  if (!z.array(z.uuid()).safeParse(libraries).success) return { error: "Couldn't read the libraries." };
  const weekdays = (v.weekdays ?? "").split(",").filter(Boolean).map(Number);

  const supabase = await createClient();
  const { error } = await supabase.rpc("join_waitlist", {
    p_student: v.student_id,
    p_subject: v.subject,
    p_minutes: v.minutes,
    p_online: v.online === "1",
    p_libraries: libraries,
    p_weekdays: weekdays.length ? weekdays : null,
    p_earliest: v.earliest || null,
    p_latest: v.latest || null,
    p_tutor: null,
    p_note: v.note || null,
  });
  if (error) return { error: plainError(error, "Couldn't add to the waitlist.") };
  return done("Added to the waitlist. CLG will be in touch when a suitable tutor is free.");
}

export async function leaveWaitlist(formData: FormData) {
  await requireViewer();
  const id = z.uuid().safeParse(formData.get("id"));
  if (!id.success) return;
  const supabase = await createClient();
  await supabase.rpc("leave_waitlist", { p_id: id.data, p_reason: "withdrawn" });
  revalidatePath("/schedule");
}

// ---------------------------------------------------------------------------
// Tutor sign on and off
// ---------------------------------------------------------------------------
const signOnSchema = z.object({
  id: z.uuid(),
  latitude: z.coerce.number().min(-90).max(90).optional(),
  longitude: z.coerce.number().min(-180).max(180).optional(),
});

// The position (library sessions only) is checked against the library and
// not stored.
export async function signOn(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const raw = Object.fromEntries([...formData.entries()].filter(([, v]) => v !== ""));
  const parsed = signOnSchema.safeParse(raw);
  if (!parsed.success) return { error: "Couldn't read that request." };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("sign_on", {
    p_session: parsed.data.id,
    p_latitude: parsed.data.latitude ?? null,
    p_longitude: parsed.data.longitude ?? null,
  });
  if (error) return { error: plainError(error, "Couldn't sign you on.") };
  const messages: Record<string, string> = {
    online: "Signed on.",
    at_library: "Signed on at the library.",
    not_at_library: "Signed on. The check didn't place you at the library, so CLG will take a look.",
    no_location: "Signed on without a location check. CLG will take a look.",
  };
  return done(messages[String(data)] ?? "Signed on.");
}

const endTimeSchema = z.object({
  id: z.uuid(),
  date: z.iso.date(),
  end_time: z.iso.time("Enter the time you finished."),
  note: z.string().trim().min(1, "Please say why the time was different.").max(500),
});

export async function recordEndTime(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = endTimeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;

  const supabase = await createClient();
  const { error } = await supabase.rpc("record_end_time", {
    p_session: v.id,
    // Postgres reads the date and time in Adelaide time.
    p_end: `${v.date} ${v.end_time} Australia/Adelaide`,
    p_note: v.note,
  });
  if (error) return { error: plainError(error, "Couldn't save the time.") };
  return done("Saved. CLG will confirm the time.");
}

const confirmSchema = z.object({
  id: z.uuid(),
  date: z.iso.date(),
  from_time: z.iso.time("Enter the start time."),
  to_time: z.iso.time("Enter the end time."),
});

export async function confirmTimes(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("admin")) return { error: "Only admins can confirm times." };
  const parsed = confirmSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;

  const supabase = await createClient();
  const { error } = await supabase.rpc("confirm_session_times", {
    p_session: v.id,
    p_from: `${v.date} ${v.from_time} Australia/Adelaide`,
    p_to: `${v.date} ${v.to_time} Australia/Adelaide`,
  });
  if (error) return { error: plainError(error, "Couldn't confirm the times.") };
  return done("Times confirmed.");
}

// ---------------------------------------------------------------------------
// Notices
// ---------------------------------------------------------------------------
export async function markNoticesRead() {
  await requireViewer();
  const supabase = await createClient();
  await supabase.rpc("mark_notices_read");
  revalidatePath("/schedule");
}

const noticeSettingsSchema = z.object({
  first_reminder_hours: z.coerce.number().int().min(2).max(168),
});

export async function saveNoticeSettings(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  const parsed = noticeSettingsSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Choose when the first reminder comes." };

  const supabase = await createClient();
  const { error } = await supabase.from("notice_settings").upsert({
    account_id: viewer.id,
    first_reminder_hours: parsed.data.first_reminder_hours,
    by_email: formData.get("by_email") === "on",
    by_text: formData.get("by_text") === "on",
  });
  if (error) return { error: "Couldn't save your settings." };
  return done("Saved. New reminders will use these settings.");
}
