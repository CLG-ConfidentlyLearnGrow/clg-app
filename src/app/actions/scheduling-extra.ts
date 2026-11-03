"use server";

// Scheduling changes from Carla's 2 Nov 2026 notes: study periods,
// requests (extra sessions, public holiday one-offs, cover), public
// holidays, blocking and library opening hours. The database checks every
// rule; these actions only read the form and pass on plain messages.

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

function plainError(error: { message: string } | null, fallback: string): string {
  if (!error) return fallback;
  const technical = /violates|syntax|relation|column|function|permission denied|uuid/i.test(error.message);
  return technical ? fallback : error.message;
}

function done(message: string): FormState {
  revalidatePath("/schedule");
  return { message };
}

const id = z.uuid();
const optionalText = (max: number) => z.string().trim().max(max).optional();

// ---------------------------------------------------------------------------
// Study periods
// ---------------------------------------------------------------------------
export async function setStudyPeriod(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = z
    .object({ student_id: id, calendar: z.enum(["public", "private", "own"]) })
    .safeParse(Object.fromEntries(formData));
  if (!v.success) return { error: "Choose the study period." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_study_period", { p_student: v.data.student_id, p_calendar: v.data.calendar });
  if (error) return { error: plainError(error, "Couldn't save the study period.") };
  return done(v.data.calendar === "own" ? "Saved. Now add the study dates below." : "Saved.");
}

export async function addOwnTerm(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = z
    .object({
      student_id: id,
      starts_on: z.iso.date("Enter the first day."),
      ends_on: z.iso.date("Enter the last day."),
      label: optionalText(100),
    })
    .safeParse(Object.fromEntries(formData));
  if (!v.success) return { error: v.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("add_own_term", {
    p_student: v.data.student_id,
    p_starts: v.data.starts_on,
    p_ends: v.data.ends_on,
    p_label: v.data.label || null,
  });
  if (error) return { error: plainError(error, "Couldn't save those dates.") };
  return done("Study dates saved.");
}

export async function removeOwnTerm(formData: FormData) {
  await requireViewer();
  const v = id.safeParse(formData.get("id"));
  if (!v.success) return;
  const supabase = await createClient();
  await supabase.rpc("remove_own_term", { p_id: v.data });
  revalidatePath("/schedule");
}

export async function setTerm4LastDay(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = z
    .object({ student_id: id, last_day: z.iso.date("Enter the last day of Term 4.") })
    .safeParse(Object.fromEntries(formData));
  if (!v.success) return { error: v.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_term4_last_day", { p_student: v.data.student_id, p_last_day: v.data.last_day });
  if (error) return { error: plainError(error, "Couldn't save the date.") };
  return done("Last day of Term 4 saved.");
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------
export async function makeSessionRequest(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = z
    .object({
      student_id: id,
      kind: z.enum(["extra", "public_holiday", "away_cover"]),
      subject: z.string().trim().min(1, "Choose the subject.").max(100),
      event_on: z.union([z.iso.date(), z.literal("")]).optional(),
      event_label: optionalText(200),
      wants: z.enum(["time", "tutor", "either"]).optional(),
      note: optionalText(1000),
    })
    .safeParse(Object.fromEntries(formData));
  if (!v.success) return { error: v.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("make_session_request", {
    p_student: v.data.student_id,
    p_kind: v.data.kind,
    p_subject: v.data.subject,
    p_event_on: v.data.event_on || null,
    p_event_label: v.data.event_label || null,
    p_wants: v.data.kind === "away_cover" ? (v.data.wants ?? "either") : null,
    p_note: v.data.note || null,
  });
  if (error) return { error: plainError(error, "Couldn't send the request.") };
  return done("Request sent. Your tutor or CLG will offer a time if one is available.");
}

export async function offerOneOff(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = z
    .object({
      request_id: id,
      tutor_id: z.union([id, z.literal("")]).optional(),
      date: z.iso.date("Choose the date."),
      start_time: z.iso.time("Choose the start time."),
      minutes: z.coerce.number().int().min(60).max(240),
      delivery: z.enum(["online", "library", "home", "school"]),
      library_id: z.union([id, z.literal("")]).optional(),
      note: optionalText(500),
    })
    .safeParse(Object.fromEntries(formData));
  if (!v.success) return { error: v.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("offer_one_off", {
    p_request: v.data.request_id,
    p_tutor: v.data.tutor_id || null,
    p_date: v.data.date,
    p_start: v.data.start_time,
    p_minutes: v.data.minutes,
    p_delivery: v.data.delivery,
    p_library: v.data.delivery === "library" ? v.data.library_id || null : null,
    p_note: v.data.note || null,
  });
  if (error) return { error: plainError(error, "Couldn't offer that time.") };
  return done("Offered. The family has been asked to approve it.");
}

export async function closeSessionRequest(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = z
    .object({ id, status: z.enum(["done", "declined", "withdrawn"]), note: optionalText(1000) })
    .safeParse(Object.fromEntries(formData));
  if (!v.success) return { error: "Something went wrong. Please refresh the page." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("close_session_request", { p_id: v.data.id, p_status: v.data.status, p_note: v.data.note || null });
  if (error) return { error: plainError(error, "Couldn't update the request.") };
  return done("Request updated.");
}

export async function setSkipPublicHolidays(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = z.object({ booking_id: id, skip: z.enum(["yes", "no"]) }).safeParse(Object.fromEntries(formData));
  if (!v.success) return { error: "Something went wrong. Please refresh the page." };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_skip_public_holidays", { p_booking: v.data.booking_id, p_skip: v.data.skip === "yes" });
  if (error) return { error: plainError(error, "Couldn't save that.") };
  const n = Number(data ?? 0);
  return done(
    v.data.skip === "yes"
      ? `Saved. ${n} public holiday session${n === 1 ? " was" : "s were"} cancelled. You can ask for a one-off at another time that week.`
      : "Saved. Sessions on public holidays will go ahead.",
  );
}

// ---------------------------------------------------------------------------
// Blocking
// ---------------------------------------------------------------------------
export async function blockMatch(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = z
    .object({
      pair: z.string().regex(/^[0-9a-f-]{36}:[0-9a-f-]{36}$/, "Choose who to block."),
      reason: z.string().trim().min(10, "Please give a reason (at least 10 characters).").max(2000),
    })
    .safeParse(Object.fromEntries(formData));
  if (!v.success) return { error: v.error.issues[0].message };
  const [tutor, student] = v.data.pair.split(":");
  const supabase = await createClient();
  const { error } = await supabase.rpc("block_match", { p_tutor: tutor, p_student: student, p_reason: v.data.reason });
  if (error) return { error: plainError(error, "Couldn't save the block.") };
  return done("Done. You won't be matched again, and CLG will be in touch to follow up. The other person isn't told.");
}

export async function recordBlockFollowUp(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = z.object({ id, note: z.string().trim().min(5, "Please note what was discussed.").max(2000) }).safeParse(Object.fromEntries(formData));
  if (!v.success) return { error: v.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("record_block_follow_up", { p_id: v.data.id, p_note: v.data.note });
  if (error) return { error: plainError(error, "Couldn't save the follow-up.") };
  return done("Follow-up saved.");
}

export async function liftBlock(formData: FormData) {
  await requireViewer();
  const v = id.safeParse(formData.get("id"));
  if (!v.success) return;
  const supabase = await createClient();
  await supabase.rpc("lift_block", { p_id: v.data });
  revalidatePath("/schedule");
}

// ---------------------------------------------------------------------------
// Libraries
// ---------------------------------------------------------------------------
export async function suggestLibrary(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = z
    .object({ name: z.string().trim().min(3, "Enter the library's name.").max(200), suburb: optionalText(100) })
    .safeParse(Object.fromEntries(formData));
  if (!v.success) return { error: v.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("suggest_library", { p_name: v.data.name, p_suburb: v.data.suburb || null });
  if (error) return { error: plainError(error, "Couldn't add the library.") };
  return done("Added. CLG will confirm the library and its opening hours before sessions can be booked there.");
}

export async function addLibraryHours(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const days = formData.getAll("weekday").map(Number).filter((d) => Number.isInteger(d) && d >= 1 && d <= 7);
  const v = z
    .object({ library_id: id, opens: z.iso.time("Enter the opening time."), closes: z.iso.time("Enter the closing time.") })
    .safeParse({ library_id: formData.get("library_id"), opens: formData.get("opens"), closes: formData.get("closes") });
  if (!v.success) return { error: v.error.issues[0].message };
  if (days.length === 0) return { error: "Tick at least one day." };
  if (v.data.closes <= v.data.opens) return { error: "Closing time must be after opening time." };
  const supabase = await createClient();
  const { error } = await supabase
    .from("library_hours")
    .insert(days.map((d) => ({ library_id: v.data.library_id, weekday: d, opens: v.data.opens, closes: v.data.closes })));
  if (error) return { error: "Couldn't save the hours. Only CLG admins can change them." };
  return done("Opening hours saved.");
}

export async function removeLibraryHours(formData: FormData) {
  await requireViewer();
  const v = id.safeParse(formData.get("library_id"));
  if (!v.success) return;
  const supabase = await createClient();
  await supabase.from("library_hours").delete().eq("library_id", v.data);
  revalidatePath("/schedule");
}

export async function confirmLibrary(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const v = id.safeParse(formData.get("library_id"));
  if (!v.success) return { error: "Something went wrong. Please refresh the page." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("confirm_library", { p_library: v.data });
  if (error) return { error: plainError(error, "Couldn't confirm the library.") };
  return done("Library confirmed. Sessions can now be booked there, inside its opening hours.");
}
