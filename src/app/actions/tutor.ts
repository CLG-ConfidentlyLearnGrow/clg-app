// Summary: what a tutor can save from their dashboard: most hours per week,
// available times, their checks (with a copy of the certificate), and subjects.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { randomUUID } from "node:crypto"; // Makes random ids (for file names).
import { revalidatePath } from "next/cache"; // Tells Next.js to refresh a page's saved copy.
import { z } from "zod"; // Zod checks that form values are the right shape.
import { requireViewer } from "@/lib/auth"; // Gets the signed-in person (or sends them to sign in).
import { checkDates } from "@/lib/check-dates"; // Works out a check's expiry date.
import { CHECK_KINDS } from "@/lib/checks"; // The list of check types.
import { MAX_DOCUMENT_BYTES, documentType } from "@/lib/documents"; // The biggest file allowed, and a reader for the file's real type.
import { ADDRESS_NOT_FOUND, findMapPoint } from "@/lib/geocode"; // Finds an address's map point, and the message when it cannot.
import { YEAR_LEVELS, mathsProblem } from "@/lib/students"; // Year levels, and the maths subject-name rule.
import type { FormState } from "@/lib/forms"; // The type for a form's result.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

async function requireTutor() { // Makes sure the person is a tutor.
  const viewer = await requireViewer(); // The signed-in person.
  if (!viewer.roles.includes("tutor")) throw new Error("Not a tutor"); // Not a tutor: stops here.
  return viewer; // Gives back the person.
} // End of requireTutor.

const hoursSchema = z.object({ // The shape of the hours form:
  max_weekly_hours: z.coerce.number("Enter a number of hours.").min(0).max(60, "60 hours is the most allowed."), // a number from 0 to 60.
}); // End of the shape.

// The most hours a tutor can work each week. Separate from availability.
export async function saveMaxHours(_prev: FormState, formData: FormData): Promise<FormState> { // Saves the most hours a tutor can work.
  const viewer = await requireTutor(); // Makes sure they're a tutor.
  const parsed = hoursSchema.safeParse(Object.fromEntries(formData)); // Checks the form values.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Not right: says why.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase // Saves:
    .from("tutor_work_settings") // into tutor_work_settings,
    .update({ max_weekly_hours: parsed.data.max_weekly_hours }) // the new hours,
    .eq("tutor_id", viewer.id); // for this tutor.
  if (error) return { error: "Could not save your hours." }; // Didn't work: says so.

  revalidatePath("/dashboard", "layout"); // Refreshes the dashboards.
  return { message: "Saved." }; // Says it's saved.
} // End of saveMaxHours.

const slotSchema = z // The shape of a time slot:
  .object({ // has:
    weekday: z.coerce.number().int().min(1).max(7), // a weekday (1 = Monday to 7 = Sunday),
    starts_at: z.iso.time("Enter a start time."), // a start time,
    ends_at: z.iso.time("Enter an end time."), // and an end time,
  }) // (end of the fields)
  .refine((v) => v.ends_at > v.starts_at, { message: "The end time must be after the start time." }); // and the end must be after the start.

export async function addAvailability(_prev: FormState, formData: FormData): Promise<FormState> { // Adds a time the tutor is available.
  const viewer = await requireTutor(); // Makes sure they're a tutor.
  const parsed = slotSchema.safeParse(Object.fromEntries(formData)); // Checks the form values.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Not right: says why.
  // Where the tutor can teach in this time: online, and in person within a
  // distance of one of their starting addresses (libraries, learners' homes, or both).
  const online = formData.get("online") === "on"; // Whether they ticked online.
  const atLibraries = formData.get("libraries") === "on"; // Whether they ticked libraries.
  const home_visits = formData.get("home_visits") === "on"; // Whether they ticked learners' homes.
  const travel = z // Checks the travel part:
    .object({ // has:
      travel_place_id: z.union([z.uuid(), z.literal("")]), // a starting address (or blank),
      travel_km: z.union([z.coerce.number().int("Enter whole kilometres.").min(1, "Enter at least 1 km.").max(100, "100 km is the most allowed."), z.literal("")]), // and a distance from 1 to 100 km (or blank).
    }) // (end of the fields)
    .safeParse({ travel_place_id: String(formData.get("travel_place_id") ?? ""), travel_km: String(formData.get("travel_km") ?? "") }); // from the form.
  if (!travel.success) return { error: travel.error.issues[0].message }; // Not right: says why.
  const inPerson = atLibraries || home_visits; // In person if libraries or homes are ticked.
  if (!inPerson && !online) return { error: "Choose online, libraries, learners' homes, or a mix." }; // Needs at least one place.
  const travel_place_id = inPerson ? travel.data.travel_place_id || null : null; // The starting address (only for in person).
  const travel_km = inPerson && travel.data.travel_km !== "" ? travel.data.travel_km : null; // The distance (only for in person).
  if (inPerson && (!travel_place_id || travel_km === null)) { // In person without an address or distance:
    return { error: "For in-person sessions, choose where you travel from and how many km you will travel." }; // asks for both.
  } // End of that check.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase // Saves:
    .from("tutor_availability") // into tutor_availability,
    .insert({ tutor_id: viewer.id, ...parsed.data, online, in_person: atLibraries, home_visits, travel_place_id, travel_km, library_id: null }); // the time, places and distance, for this tutor.
  if (error) { // If it didn't work:
    // Say what went wrong in plain words, so it can be fixed quickly.
    if (error.code === "PGRST204" || error.code === "42703") { // A database update hasn't been run:
      return { // gives back:
        error: // the message:
          "The app's database is missing an update, so times cannot be saved yet. The owner needs to run the migration 20261119700100_travel_distance.sql (and any earlier scheduling updates) in Supabase.", // naming the update to run.
      }; // (end of the message)
    } // End of this case.
    if (error.message.includes("at least 2 hours")) { // A casual tutor's time is shorter than 2 hours (Carla, 18 Nov 2026):
      return { error: "Casual tutors give available times in blocks of at least 2 hours, because casual work is paid in blocks of at least 2 hours. Please make this time at least 2 hours long." }; // explains the rule.
    } // End of this case.
    if (error.code === "22023") { // The starting address is not theirs:
      return { error: "Choose one of your own starting addresses." }; // says so.
    } // End of this case.
    if (error.code === "23503") { // No tutor profile yet:
      return { error: "Your tutor profile is not set up yet. Ask a CLG admin to finish setting up your tutor account." }; // says so.
    } // End of this case.
    return { error: "Could not add that time. Please try again, or tell a CLG admin if it keeps happening." }; // Anything else: a general message.
  } // End of the error part.

  revalidatePath("/dashboard", "layout"); // Refreshes the dashboards.
  return { message: "Added." }; // Says it's added.
} // End of addAvailability.

export async function removeAvailability(formData: FormData) { // Removes one of the tutor's available times.
  const viewer = await requireTutor(); // Makes sure they're a tutor.
  const id = z.uuid().safeParse(formData.get("id")); // Checks the time's id.
  if (!id.success) return; // Not right: does nothing.

  const supabase = await createClient(); // Connects to the database.
  await supabase.from("tutor_availability").delete().eq("id", id.data).eq("tutor_id", viewer.id); // Removes the time, only if it's this tutor's.
  revalidatePath("/dashboard", "layout"); // Refreshes the dashboards.
} // End of removeAvailability.

// The addresses a tutor travels from (for example Home or Uni). Each one is
// looked up once to find its map point, so distances can be worked out.
const travelPlaceSchema = z.object({ // The shape of the address form:
  label: z.string().trim().min(1, "Give the address a short name, such as Home.").max(60, "Keep the name to 60 characters."), // a short name,
  address: z.string().trim().min(5, "Enter the full street address.").max(300, "Keep the address to 300 characters."), // and the street address.
}); // End of the shape.

export async function addTravelPlace(_prev: FormState, formData: FormData): Promise<FormState> { // Adds a starting address for a tutor.
  const viewer = await requireTutor(); // Makes sure they are a tutor.
  const parsed = travelPlaceSchema.safeParse({ label: formData.get("label"), address: formData.get("address") }); // Checks the form values.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Not right: says why.
  const point = await findMapPoint(parsed.data.address); // Looks up the address's map point.
  if (!point) return { error: ADDRESS_NOT_FOUND }; // Not found: asks them to check it.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("tutor_travel_places").insert({ // Saves:
    tutor_id: viewer.id, // for this tutor,
    label: parsed.data.label, // the name,
    address: parsed.data.address, // the address as typed,
    latitude: point.latitude, // and its map point.
    longitude: point.longitude, // (west to east)
  }); // End of the save.
  if (error) return { error: "Could not save the address. Please try again, or tell a CLG admin if it keeps happening." }; // Did not work: says so.
  revalidatePath("/dashboard", "layout"); // Refreshes the dashboards.
  return { message: `Saved. Found: ${point.label}` }; // Says it is saved and shows the address found, so they can check it.
} // End of addTravelPlace.

export async function removeTravelPlace(formData: FormData) { // Removes one of the tutor's starting addresses.
  const viewer = await requireTutor(); // Makes sure they are a tutor.
  const id = z.uuid().safeParse(formData.get("id")); // Checks the address's id.
  if (!id.success) return; // Not right: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.from("tutor_travel_places").delete().eq("id", id.data).eq("tutor_id", viewer.id); // Removes it, only if it is theirs (the database keeps addresses a time still uses).
  revalidatePath("/dashboard", "layout"); // Refreshes the dashboards.
} // End of removeTravelPlace.

const myCheckSchema = z.object({ // The shape of the check form:
  kind: z.enum(CHECK_KINDS, "Choose the check."), // which check,
  reference: z.string().trim().max(100).optional(), // its number (optional, up to 100 letters),
  completed_on: z.union([z.iso.date(), z.literal("")]).optional(), // the date done (or blank),
  expires_on: z.union([z.iso.date(), z.literal("")]).optional(), // the expiry date (or blank).
}); // End of the shape.

// A tutor adds or renews one of their own checks, with a copy of the
// certificate. It is logged and waits for CLG to confirm it against the
// official record before it counts.
export async function submitMyCheck(_prev: FormState, formData: FormData): Promise<FormState> { // Saves a tutor's check.
  const viewer = await requireTutor(); // Makes sure they're a tutor.
  const { document, ...fields } = Object.fromEntries(formData); // Separates the file from the other values.
  const parsed = myCheckSchema.safeParse(fields); // Checks the other values.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Not right: says why.
  const v = parsed.data; // The checked values.
  const dates = checkDates(v.kind, v.reference, v.completed_on || undefined, v.expires_on || undefined); // Works out the expiry date.
  if ("error" in dates) return dates; // Couldn't: says why.

  if (!(document instanceof File) || document.size === 0) { // No file attached:
    return { error: "Attach a copy of your certificate or card (a PDF or a photo)." }; // asks for one.
  } // End of this case.
  if (document.size > MAX_DOCUMENT_BYTES) { // File too big:
    return { error: "That file is too big. Please use a file under 3.5 MB, or take a photo instead." }; // says so.
  } // End of this case.
  const bytes = new Uint8Array(await document.arrayBuffer()); // Reads the file's bytes.
  const kind = documentType(bytes); // Works out its real type from the bytes.
  if (!kind) return { error: "Please attach a PDF or a photo (JPG, PNG or WebP)." }; // Not a PDF or photo: says so.

  const supabase = await createClient(); // Connects to the database.
  const path = `${viewer.id}/${randomUUID()}.${kind.ext}`; // The file's storage name: the tutor's folder and a random name.
  const upload = await supabase.storage // Uploads:
    .from("check-documents") // into the check-documents store,
    .upload(path, bytes, { contentType: kind.type, upsert: false }); // the file, without replacing any other.
  if (upload.error) return { error: "Could not upload your file. Please try again." }; // Didn't work: says so.

  const { error } = await supabase.from("tutor_checks").insert({ // Saves the check into tutor_checks:
    tutor_id: viewer.id, // the tutor,
    kind: v.kind, // the check type,
    reference: v.reference || null, // its number (or none),
    completed_on: v.completed_on || null, // the date done (or none),
    expires_on: dates.expiresOn, // the expiry date,
    document_path: path, // and where the copy is stored.
  }); // End of the save.
  if (error) { // If it didn't work:
    // Don't leave an unattached copy behind.
    await supabase.storage.from("check-documents").remove([path]); // removes the uploaded copy,
    return { error: error.code === "23514" ? `${error.message}.` : "Could not save your check. Please try again." }; // and says why (the database's own words for a date rule).
  } // End of the error part.

  revalidatePath("/dashboard", "layout"); // Refreshes the dashboards,
  revalidatePath("/admin"); // and the admin page.
  return { message: "Saved. CLG will check your copy against the official record." }; // Says it's saved and will be checked.
} // End of submitMyCheck.

const teachingSchema = z // The shape of the subject form:
  .object({ // has:
    subject: z.string().trim().min(2, "Enter the subject.").max(100), // the subject (2 to 100 letters),
    from_level: z.enum(YEAR_LEVELS, "Choose the lowest year level."), // the lowest year level,
    to_level: z.enum(YEAR_LEVELS, "Choose the highest year level."), // and the highest year level,
  }) // (end of the fields)
  .superRefine((v, ctx) => { // then checks the maths naming rule:
    const problem = mathsProblem(v.subject, v.to_level); // any problem with the subject name for that year level,
    if (problem) ctx.addIssue({ code: "custom", message: problem }); // added as a message.
  }) // (end of the maths check)
  .refine((v) => YEAR_LEVELS.indexOf(v.from_level) <= YEAR_LEVELS.indexOf(v.to_level), { // and the lowest level must not be above the highest:
    message: "The first year level needs to be the same as or below the second.", // the message if it is.
  }); // End of the shape.

// A subject the tutor teaches, and the year levels they teach it for.
export async function addTeaching(_prev: FormState, formData: FormData): Promise<FormState> { // Adds a subject the tutor teaches.
  const viewer = await requireTutor(); // Makes sure they're a tutor.
  const parsed = teachingSchema.safeParse(Object.fromEntries(formData)); // Checks the form values.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Not right: says why.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("tutor_teaching").insert({ tutor_id: viewer.id, ...parsed.data }); // Saves the subject for this tutor.
  if (error) { // If it didn't work:
    return { // gives back:
      error: // a message:
        error.code === "23505" // if it's already added,
          ? "You have already added that subject. Remove it first to change its year levels." // says so,
          : "Could not save. Please try again.", // otherwise a general message.
    }; // (end of the message)
  } // End of the error part.
  revalidatePath("/dashboard", "layout"); // Refreshes the dashboards.
  return { message: `${parsed.data.subject} added.` }; // Says it's added.
} // End of addTeaching.

export async function removeTeaching(formData: FormData) { // Removes a subject the tutor teaches.
  await requireTutor(); // Makes sure they're a tutor.
  const id = z.uuid().safeParse(formData.get("id")); // Checks the subject's id.
  if (!id.success) return; // Not right: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.from("tutor_teaching").delete().eq("id", id.data); // Removes it (database rules only let a tutor remove their own).
  revalidatePath("/dashboard", "layout"); // Refreshes the dashboards.
} // End of removeTeaching.
