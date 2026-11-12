"use server"; // Marks every function in this file as a server action (it runs only on the server).

// Scheduling changes from Carla's 2 Nov 2026 notes: study periods,
// requests (extra sessions, public holiday one-offs, cover), public
// holidays, blocking and library opening hours. The database checks every
// rule; these actions only read the form and pass on plain messages.

import { revalidatePath } from "next/cache"; // Tells Next.js to refresh a page's saved copy.
import { z } from "zod"; // Zod checks that form values are the right shape.
import { requireViewer } from "@/lib/auth"; // Gets the signed-in person (or sends them to sign in).
import type { FormState } from "@/lib/forms"; // The type for a form's result.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { parseOsmHours } from "@/lib/osm-hours"; // Turns OpenStreetMap opening hours text into rows.

// Gives a plain message: the database's own words if they are plain, otherwise the fallback.
function plainError(error: { message: string } | null, fallback: string): string { // Takes the error (if any) and a fallback message.
  if (!error) return fallback; // No error: the fallback.
  const technical = /violates|syntax|relation|column|function|permission denied|uuid/i.test(error.message); // Whether the message looks technical.
  return technical ? fallback : error.message; // Technical: the fallback; otherwise the database's words.
} // End of plainError.

// Finishes a successful save: refreshes the sessions page and says it worked.
function done(message: string): FormState { // Takes the message to show.
  revalidatePath("/schedule"); // Refreshes the sessions page.
  return { message }; // Gives back the message.
} // End of done.

const id = z.uuid(); // The shape of an id.
const optionalText = (max: number) => z.string().trim().max(max).optional(); // The shape of optional text, up to a given length.

// ---------------------------------------------------------------------------
// Study periods
// ---------------------------------------------------------------------------
export async function setStudyPeriod(_prev: FormState, formData: FormData): Promise<FormState> { // Saves which study period a student follows.
  await requireViewer(); // Must be signed in.
  const v = z // Checks the form:
    .object({ student_id: id, calendar: z.enum(["public", "private", "own"]) }) // a student and one of the three study periods,
    .safeParse(Object.fromEntries(formData)); // from the form values.
  if (!v.success) return { error: "Choose the study period." }; // Not right: asks to choose.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("set_study_period", { p_student: v.data.student_id, p_calendar: v.data.calendar }); // Saves it (the database checks who may).
  if (error) return { error: plainError(error, "Couldn't save the study period.") }; // Didn't work: says why.
  return done(v.data.calendar === "own" ? "Saved. Now add the study dates below." : "Saved."); // Saved (and for own dates, asks for them next).
} // End of setStudyPeriod.

export async function addOwnTerm(_prev: FormState, formData: FormData): Promise<FormState> { // Adds the family's own study dates.
  await requireViewer(); // Must be signed in.
  const v = z // Checks the form:
    .object({ // has:
      student_id: id, // a student,
      starts_on: z.iso.date("Enter the first day."), // the first day,
      ends_on: z.iso.date("Enter the last day."), // the last day,
      label: optionalText(100), // and an optional name,
    }) // (end of the fields)
    .safeParse(Object.fromEntries(formData)); // from the form values.
  if (!v.success) return { error: v.error.issues[0].message }; // Not right: says why.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("add_own_term", { // Saves:
    p_student: v.data.student_id, // the student,
    p_starts: v.data.starts_on, // the first day,
    p_ends: v.data.ends_on, // the last day,
    p_label: v.data.label || null, // and the name (or none).
  }); // End of the save.
  if (error) return { error: plainError(error, "Couldn't save those dates.") }; // Didn't work: says why.
  return done("Study dates saved."); // Says it's saved.
} // End of addOwnTerm.

export async function removeOwnTerm(formData: FormData) { // Removes one of the family's own study date ranges.
  await requireViewer(); // Must be signed in.
  const v = id.safeParse(formData.get("id")); // Checks the id.
  if (!v.success) return; // Not right: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("remove_own_term", { p_id: v.data }); // Removes it (the database checks who may).
  revalidatePath("/schedule"); // Refreshes the sessions page.
} // End of removeOwnTerm.

export async function setTerm4LastDay(_prev: FormState, formData: FormData): Promise<FormState> { // Saves the last day of Term 4 for a student.
  await requireViewer(); // Must be signed in.
  const v = z // Checks the form:
    .object({ student_id: id, last_day: z.iso.date("Enter the last day of Term 4.") }) // a student and a date,
    .safeParse(Object.fromEntries(formData)); // from the form values.
  if (!v.success) return { error: v.error.issues[0].message }; // Not right: says why.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("set_term4_last_day", { p_student: v.data.student_id, p_last_day: v.data.last_day }); // Saves it (the database checks who may).
  if (error) return { error: plainError(error, "Couldn't save the date.") }; // Didn't work: says why.
  return done("Last day of Term 4 saved."); // Says it's saved.
} // End of setTerm4LastDay.

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------
export async function makeSessionRequest(_prev: FormState, formData: FormData): Promise<FormState> { // Sends a family's request for a session.
  await requireViewer(); // Must be signed in.
  const v = z // Checks the form:
    .object({ // has:
      student_id: id, // a student,
      kind: z.enum(["extra", "public_holiday", "away_cover"]), // the kind of request,
      subject: z.string().trim().min(1, "Choose the subject.").max(100), // the subject,
      event_on: z.union([z.iso.date(), z.literal("")]).optional(), // a date (or blank),
      event_label: optionalText(200), // what the event is (optional),
      wants: z.enum(["time", "tutor", "either"]).optional(), // what they'd like for cover (optional),
      note: optionalText(1000), // and a note (optional),
    }) // (end of the fields)
    .safeParse(Object.fromEntries(formData)); // from the form values.
  if (!v.success) return { error: v.error.issues[0].message }; // Not right: says why.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("make_session_request", { // Saves:
    p_student: v.data.student_id, // the student,
    p_kind: v.data.kind, // the kind,
    p_subject: v.data.subject, // the subject,
    p_event_on: v.data.event_on || null, // the date (or none),
    p_event_label: v.data.event_label || null, // the event (or none),
    p_wants: v.data.kind === "away_cover" ? (v.data.wants ?? "either") : null, // what they'd like (only for cover; either if not chosen),
    p_note: v.data.note || null, // and the note (or none).
  }); // End of the save.
  if (error) return { error: plainError(error, "Couldn't send the request.") }; // Didn't work: says why.
  return done("Request sent. Your tutor or CLG will offer a time if one is available."); // Says it's sent and what happens next.
} // End of makeSessionRequest.

export async function offerOneOff(_prev: FormState, formData: FormData): Promise<FormState> { // Offers a one-off time for a request.
  await requireViewer(); // Must be signed in.
  const v = z // Checks the form:
    .object({ // has:
      request_id: id, // the request,
      tutor_id: z.union([id, z.literal("")]).optional(), // a tutor (admins choose; otherwise blank),
      date: z.iso.date("Choose the date."), // the date,
      start_time: z.iso.time("Choose the start time."), // the start time,
      minutes: z.coerce.number().int().min(60).max(240), // the length (1 to 4 hr),
      delivery: z.enum(["online", "library", "home", "school"]), // where,
      library_id: z.union([id, z.literal("")]).optional(), // a library (or blank),
      note: optionalText(500), // and a note (optional),
    }) // (end of the fields)
    .safeParse(Object.fromEntries(formData)); // from the form values.
  if (!v.success) return { error: v.error.issues[0].message }; // Not right: says why.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("offer_one_off", { // Saves:
    p_request: v.data.request_id, // the request,
    p_tutor: v.data.tutor_id || null, // the tutor (or none: the database uses the signed-in tutor),
    p_date: v.data.date, // the date,
    p_start: v.data.start_time, // the start time,
    p_minutes: v.data.minutes, // the length,
    p_delivery: v.data.delivery, // where,
    p_library: v.data.delivery === "library" ? v.data.library_id || null : null, // the library (only for a library session),
    p_note: v.data.note || null, // and the note (or none).
  }); // End of the save.
  if (error) return { error: plainError(error, "Couldn't offer that time.") }; // Didn't work: says why.
  return done("Offered. The family has been asked to approve it."); // Says it's offered and the family must approve.
} // End of offerOneOff.

export async function closeSessionRequest(_prev: FormState, formData: FormData): Promise<FormState> { // Closes a request (done, declined or withdrawn).
  await requireViewer(); // Must be signed in.
  const v = z // Checks the form:
    .object({ id, status: z.enum(["done", "declined", "withdrawn"]), note: optionalText(1000) }) // the request, the new status, and a note (optional),
    .safeParse(Object.fromEntries(formData)); // from the form values.
  if (!v.success) return { error: "Something went wrong. Please refresh the page." }; // Not right: asks to refresh.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("close_session_request", { p_id: v.data.id, p_status: v.data.status, p_note: v.data.note || null }); // Saves it (the database checks who may, and that declining has a reason).
  if (error) return { error: plainError(error, "Couldn't update the request.") }; // Didn't work: says why.
  return done("Request updated."); // Says it's updated.
} // End of closeSessionRequest.

export async function setSkipPublicHolidays(_prev: FormState, formData: FormData): Promise<FormState> { // Turns skipping public holidays on or off for a booking.
  await requireViewer(); // Must be signed in.
  const v = z.object({ booking_id: id, skip: z.enum(["yes", "no"]) }).safeParse(Object.fromEntries(formData)); // Checks the booking and the yes/no choice.
  if (!v.success) return { error: "Something went wrong. Please refresh the page." }; // Not right: asks to refresh.
  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase.rpc("set_skip_public_holidays", { p_booking: v.data.booking_id, p_skip: v.data.skip === "yes" }); // Saves it; gives back how many sessions were cancelled.
  if (error) return { error: plainError(error, "Couldn't save that.") }; // Didn't work: says why.
  const n = Number(data ?? 0); // The number cancelled.
  return done( // Says it's done:
    v.data.skip === "yes" // if skipping,
      ? `Saved. ${n} public holiday session${n === 1 ? " was" : "s were"} cancelled. You can ask for a one-off at another time that week.` // how many were cancelled and that a one-off can be asked for,
      : "Saved. Sessions on public holidays will go ahead.", // otherwise that holiday sessions go ahead.
  ); // End of the message.
} // End of setSkipPublicHolidays.

// ---------------------------------------------------------------------------
// Blocking
// ---------------------------------------------------------------------------
export async function blockMatch(_prev: FormState, formData: FormData): Promise<FormState> { // Blocks a tutor and student from being matched.
  await requireViewer(); // Must be signed in.
  const v = z // Checks the form:
    .object({ // has:
      pair: z.string().regex(/^[0-9a-f-]{36}:[0-9a-f-]{36}$/, "Choose who to block."), // the pair as "tutor id:student id",
      reason: z.string().trim().min(10, "Please give a reason (at least 10 characters).").max(2000), // and a reason of at least 10 letters,
    }) // (end of the fields)
    .safeParse(Object.fromEntries(formData)); // from the form values.
  if (!v.success) return { error: v.error.issues[0].message }; // Not right: says why.
  const [tutor, student] = v.data.pair.split(":"); // Splits the pair into tutor and student.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("block_match", { p_tutor: tutor, p_student: student, p_reason: v.data.reason }); // Saves the block (the database checks who may).
  if (error) return { error: plainError(error, "Couldn't save the block.") }; // Didn't work: says why.
  return done("Done. You won't be matched again, and CLG will be in touch to follow up. The other person isn't told."); // Says it's done and what happens next.
} // End of blockMatch.

export async function recordBlockFollowUp(_prev: FormState, formData: FormData): Promise<FormState> { // An admin records how a block was followed up.
  await requireViewer(); // Must be signed in.
  const v = z.object({ id, note: z.string().trim().min(5, "Please note what was discussed.").max(2000) }).safeParse(Object.fromEntries(formData)); // Checks the block and a note of at least 5 letters.
  if (!v.success) return { error: v.error.issues[0].message }; // Not right: says why.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("record_block_follow_up", { p_id: v.data.id, p_note: v.data.note }); // Saves it (the database checks only admins may).
  if (error) return { error: plainError(error, "Couldn't save the follow-up.") }; // Didn't work: says why.
  return done("Follow-up saved."); // Says it's saved.
} // End of recordBlockFollowUp.

export async function liftBlock(formData: FormData) { // Lifts a block.
  await requireViewer(); // Must be signed in.
  const v = id.safeParse(formData.get("id")); // Checks the id.
  if (!v.success) return; // Not right: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("lift_block", { p_id: v.data }); // Lifts it (the database checks who may).
  revalidatePath("/schedule"); // Refreshes the sessions page.
} // End of liftBlock.

// ---------------------------------------------------------------------------
// Libraries
// ---------------------------------------------------------------------------
export async function suggestLibrary(_prev: FormState, formData: FormData): Promise<FormState> { // Suggests a new library.
  await requireViewer(); // Must be signed in.
  const v = z // Checks the form:
    .object({ // has:
      name: z.string().trim().min(3, "Enter the library's name.").max(200), // the name,
      address: z.string().trim().min(5, "Enter the library's street address.").max(300), // the street address,
      suburb: optionalText(100), // and the suburb (optional),
    }) // (end of the fields)
    .safeParse(Object.fromEntries(formData)); // from the form values.
  if (!v.success) return { error: v.error.issues[0].message }; // Not right: says why.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("suggest_library", { // Saves:
    p_name: v.data.name, // the name,
    p_suburb: v.data.suburb || null, // the suburb (or none),
    p_address: v.data.address, // and the address.
  }); // End of the save.
  if (error) return { error: plainError(error, "Couldn't add the library.") }; // Didn't work: says why.
  return done("Added. CLG will confirm the library and its opening hours before sessions can be booked there."); // Says it's added and CLG will confirm it.
} // End of suggestLibrary.

// Admins load every South Australian library from OpenStreetMap (free map
// data; credit shown on the Libraries page). University, TAFE and school
// libraries are left out. Libraries already listed keep their details.
const OVERPASS = "https://overpass-api.de/api/interpreter"; // The OpenStreetMap search service's address.
const SA_LIBRARIES_QUERY = // The search: every library inside South Australia,
  '[out:json][timeout:60];area["ISO3166-2"="AU-SA"]->.sa;nwr[amenity=library](area.sa);out center tags;'; // with its map point and details.
const NOT_PUBLIC = /universit|tafe|college|school|campus|institute|hospital|archive|toy library/i; // Words that show a library isn't a public one.

type OsmElement = { // One map result from OpenStreetMap:
  type: string; // its kind (node, way or relation),
  id: number; // its number,
  lat?: number; // its latitude (for a point),
  lon?: number; // its longitude (for a point),
  center?: { lat: number; lon: number }; // its centre (for a building or area),
  tags?: Record<string, string>; // and its details (name, address, and so on).
}; // End of OsmElement.

export async function loadSaLibraries(_prev: FormState): Promise<FormState> { // Loads every SA library from OpenStreetMap (admins only).
  const viewer = await requireViewer(); // The signed-in person.
  if (!viewer.roles.includes("admin")) return { error: "Only CLG admins can load libraries." }; // Not an admin: says so.
  let elements: OsmElement[]; // The map results.
  try { // Tries the search:
    const res = await fetch(OVERPASS, { // asks OpenStreetMap:
      method: "POST", // sending the search,
      headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "clg-app library list" }, // as a form, naming the app,
      body: new URLSearchParams({ data: SA_LIBRARIES_QUERY }), // the search itself,
      cache: "no-store", // without keeping an old copy,
      signal: AbortSignal.timeout(90_000), // giving up after 90 seconds.
    }); // End of the request.
    if (!res.ok) throw new Error(String(res.status)); // An error reply: counts as failed.
    elements = ((await res.json()) as { elements?: OsmElement[] }).elements ?? []; // Reads the results (or none).
  } catch { // If it failed:
    return { error: "Couldn't reach OpenStreetMap just now. Please try again in a few minutes." }; // says so.
  } // End of the fallback.
  const rows = elements // Turns results into library rows:
    .filter((e) => e.tags?.name && !NOT_PUBLIC.test(`${e.tags.name} ${e.tags.operator ?? ""}`)) // keeps named ones that aren't university, school and so on,
    .map((e) => { // each as:
      const t = e.tags ?? {}; // its details,
      const street = [t["addr:housenumber"], t["addr:street"]].filter(Boolean).join(" "); // its street (number and street name),
      return { // gives back:
        name: t.name, // the name,
        address: street, // the street address,
        suburb: t["addr:suburb"] || t["addr:city"] || "", // the suburb (or city),
        latitude: String(e.lat ?? e.center?.lat ?? ""), // the latitude,
        longitude: String(e.lon ?? e.center?.lon ?? ""), // the longitude,
        osm_ref: `${e.type}/${e.id}`, // and its OpenStreetMap reference.
      }; // End of the row.
    }); // End of the list.
  if (rows.length === 0) return { error: "OpenStreetMap didn't return any libraries. Please try again later." }; // Nothing found: says so.
  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase.rpc("import_libraries", { p_rows: rows, p_state: "SA" }); // Adds the new ones (the database skips libraries already listed).
  if (error) return { error: plainError(error, "Couldn't save the libraries.") }; // Didn't work: says why.
  return done( // Says it's done:
    `Done: ${data ?? 0} new libraries added (${rows.length} found). Hide any that aren't public libraries. Opening hours are asked for once a tutor or family chooses a library.`, // how many were added and found, and what to do next.
  ); // End of the message.
} // End of loadSaLibraries.

export async function addLibraryHours(_prev: FormState, formData: FormData): Promise<FormState> { // Adds opening hours for a library.
  await requireViewer(); // Must be signed in.
  const days = formData.getAll("weekday").map(Number).filter((d) => Number.isInteger(d) && d >= 1 && d <= 7); // The ticked days, kept only if 1 to 7.
  const v = z // Checks the form:
    .object({ library_id: id, opens: z.iso.time("Enter the opening time."), closes: z.iso.time("Enter the closing time.") }) // the library, opening time and closing time,
    .safeParse({ library_id: formData.get("library_id"), opens: formData.get("opens"), closes: formData.get("closes") }); // from those form values.
  if (!v.success) return { error: v.error.issues[0].message }; // Not right: says why.
  if (days.length === 0) return { error: "Tick at least one day." }; // No day ticked: says so.
  if (v.data.closes <= v.data.opens) return { error: "Closing time must be after opening time." }; // Closing must be after opening.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase // Saves:
    .from("library_hours") // into library_hours,
    .insert(days.map((d) => ({ library_id: v.data.library_id, weekday: d, opens: v.data.opens, closes: v.data.closes }))); // one row per ticked day.
  if (error) return { error: "Couldn't save the hours. Only CLG admins can change them." }; // Didn't work (only admins may): says so.
  return done("Opening hours saved."); // Says it's saved.
} // End of addLibraryHours.

export async function removeLibraryHours(formData: FormData) { // Clears all of a library's opening hours.
  await requireViewer(); // Must be signed in.
  const v = id.safeParse(formData.get("library_id")); // Checks the library id.
  if (!v.success) return; // Not right: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.from("library_hours").delete().eq("library_id", v.data); // Removes its hours (the database lets only admins).
  revalidatePath("/schedule"); // Refreshes the sessions page.
} // End of removeLibraryHours.

// Fill a library's opening hours from OpenStreetMap, for an admin to check.
export async function fillHoursFromOsm(_prev: FormState, formData: FormData): Promise<FormState> { // Fills a library's hours from OpenStreetMap.
  const viewer = await requireViewer(); // The signed-in person.
  if (!viewer.roles.includes("admin")) return { error: "Only CLG admins can change opening hours." }; // Not an admin: says so.
  const v = id.safeParse(formData.get("library_id")); // Checks the library id.
  if (!v.success) return { error: "Something went wrong. Please refresh the page." }; // Not right: asks to refresh.
  const supabase = await createClient(); // Connects to the database.
  const [{ data: lib }, { count }] = await Promise.all([ // Reads two things at once:
    supabase.from("libraries").select("osm_ref").eq("id", v.data).maybeSingle(), // the library's OpenStreetMap reference,
    supabase.from("library_hours").select("id", { count: "exact", head: true }).eq("library_id", v.data), // and how many hours it already has.
  ]); // End of the reads.
  if ((count ?? 0) > 0) return { error: "This library already has hours. Clear them first to fill them again." }; // Already has hours: says to clear them first.
  const ref = (lib?.osm_ref as string | null | undefined) ?? ""; // The reference (or blank).
  const m = ref.match(/^(node|way|relation)\/(\d+)$/); // Splits it into kind and number.
  if (!m) return { error: "This library wasn't loaded from OpenStreetMap. Please add its hours by hand." }; // Not from OpenStreetMap: says to add by hand.
  let hoursText: string | undefined; // The hours text from OpenStreetMap.
  try { // Tries to read it:
    const res = await fetch(`https://api.openstreetmap.org/api/0.6/${m[1]}/${m[2]}.json`, { // asks OpenStreetMap for this one library:
      headers: { "User-Agent": "clg-app library hours" }, // naming the app,
      cache: "no-store", // without keeping an old copy,
      signal: AbortSignal.timeout(20_000), // giving up after 20 seconds.
    }); // End of the request.
    if (!res.ok) throw new Error(String(res.status)); // An error reply: counts as failed.
    const body = (await res.json()) as { elements?: { tags?: Record<string, string> }[] }; // Reads the reply.
    hoursText = body.elements?.[0]?.tags?.opening_hours; // Picks out its opening hours text.
  } catch { // If it failed:
    return { error: "Couldn't reach OpenStreetMap just now. Please try again, or add the hours by hand." }; // says so.
  } // End of the fallback.
  const rows = parseOsmHours(hoursText); // Turns the text into rows (or nothing if too complicated).
  if (!rows) { // If it couldn't:
    return { // gives back:
      error: hoursText // a message:
        ? `OpenStreetMap lists the hours as "${hoursText}", which is too complicated to fill in. Please add them by hand.` // showing the hours text that was too complicated,
        : "OpenStreetMap doesn't list hours for this library. Please add them by hand.", // or that there are no hours listed.
    }; // (end of the message)
  } // End of this part.
  const { error } = await supabase.from("library_hours").insert(rows.map((r) => ({ library_id: v.data, ...r }))); // Saves the rows for this library.
  if (error) return { error: "Couldn't save the hours." }; // Didn't work: says so.
  return done("Hours filled in from OpenStreetMap. Please check them against the library's website."); // Says it's filled in, to be checked.
} // End of fillHoursFromOsm.

// An admin says a library's hours are still right.
export async function markHoursChecked(formData: FormData) { // Marks a library's hours as checked.
  await requireViewer(); // Must be signed in.
  const v = id.safeParse(formData.get("library_id")); // Checks the library id.
  if (!v.success) return; // Not right: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("mark_library_hours_checked", { p_library: v.data }); // Saves it (the database checks who may).
  revalidatePath("/schedule"); // Refreshes the sessions page.
} // End of markHoursChecked.

export async function confirmLibrary(_prev: FormState, formData: FormData): Promise<FormState> { // An admin confirms a library so sessions can be booked there.
  await requireViewer(); // Must be signed in.
  const v = id.safeParse(formData.get("library_id")); // Checks the library id.
  if (!v.success) return { error: "Something went wrong. Please refresh the page." }; // Not right: asks to refresh.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("confirm_library", { p_library: v.data }); // Confirms it (the database checks who may).
  if (error) return { error: plainError(error, "Couldn't confirm the library.") }; // Didn't work: says why.
  return done("Library confirmed. Sessions can now be booked there, inside its opening hours."); // Says it's confirmed.
} // End of confirmLibrary.

// Owner and operations admins set the time kept free after each tutor
// session for writing the summary (Carla, 12 Nov 2026: 15 min now, likely
// 5 min later). The database checks who may change it.
export async function setSummaryMinutes(_prev: FormState, formData: FormData): Promise<FormState> { // Saves the summary time.
  await requireViewer(); // Must be signed in.
  const v = z.coerce.number().int().min(0).max(30).safeParse(formData.get("minutes")); // Checks it's a whole number from 0 to 30.
  if (!v.success) return { error: "Please enter a number of minutes from 0 to 30." }; // Not right: says what's needed.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("set_summary_minutes", { p_minutes: v.data }); // Saves it (the database checks who may).
  if (error) return { error: plainError(error, "Couldn't save the summary time.") }; // Didn't work: says why.
  revalidatePath("/schedule"); // Refreshes the sessions page.
  return done(`Saved. New times will leave ${v.data} min after each tutor session.`); // Says it's saved.
} // End of setSummaryMinutes.

// Owner and operations admins set CLG's quiet hours (Carla, 12 Nov 2026:
// 9pm to 5am). Nothing reaches anyone between these times, in their own
// local time; held notices arrive when quiet hours end. The database checks
// who may change it and that the times make sense.
const halfHour = z.string().regex(/^([01]\d|2[0-3]):(00|30)$/, "Choose a time on the hour or half hour."); // A time like "21:00" or "05:30".
export async function setQuietHours(_prev: FormState, formData: FormData): Promise<FormState> { // Saves the quiet hours.
  await requireViewer(); // Must be signed in.
  const starts = halfHour.safeParse(formData.get("starts")); // Checks the start time.
  const ends = halfHour.safeParse(formData.get("ends")); // Checks the end time.
  if (!starts.success || !ends.success) return { error: "Please choose a start and end time on the hour or half hour." }; // Not right: says what's needed.
  if (starts.data === ends.data) return { error: "Quiet hours must start and end at different times." }; // The same time: says why.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("set_quiet_hours", { p_starts: starts.data, p_ends: ends.data }); // Saves it (the database checks who may).
  if (error) return { error: plainError(error, "Couldn't save the quiet hours.") }; // Didn't work: says why.
  return done("Saved. New notices will wait until quiet hours end."); // Refreshes the page and says it's saved.
} // End of setQuietHours.
