// Summary: loading curriculums into the shared skill library: add one by
// hand, paste skills, set a student's curriculum, confirm or discard drafts,
// and load many at once from ACARA's file or CLG's own spreadsheet layout.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is a full admin.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { ACARA_VERSION, acaraSource } from "@/lib/acara"; // The ACARA version and its licence credit.
import { splitCsvLine } from "@/lib/csv"; // Splits one pasted row into its cells.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Loading curricula into the shared skill library. Admins only; the
// database checks again.

// The rules for adding a curriculum by hand:
const frameworkSchema = z.object({
  code: z.string().trim().regex(/^[A-Za-z0-9_.-]{1,30}$/, "Use a short code such as AC9 or SACE."), // a short code (letters, numbers, _ . -),
  name: z.string().trim().min(1, "Enter the curriculum's name.").max(200), // its name,
  version: z.string().trim().min(1, "Enter the version, for example 9.0.").max(40), // its version,
  starts_on: z.union([z.iso.date(), z.literal("")]).optional(), // the date it starts (optional).
}); // End of the rules.

// Adds a curriculum as a draft.
export async function createFramework(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  const parsed = frameworkSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("curriculum_frameworks").insert({ // Saves it:
    code: parsed.data.code, // code,
    name: parsed.data.name, // name,
    version: parsed.data.version, // version,
    starts_on: parsed.data.starts_on || null, // start date (or none).
  }); // End of the save.
  if (error) return { error: "Couldn't add it. That code and version may already exist." }; // Failed: the code and version may already exist.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: "Curriculum added as a draft. Load its skills, then check the summary and confirm it." }; // Tells the admin what's next.
} // End of createFramework.

// Rows: code, subject, year or level, official wording, plain wording.
export async function importSkills(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const frameworkId = z.uuid().safeParse(formData.get("framework_id")); // Reads and checks which curriculum.
  if (!frameworkId.success) return { error: "Choose a curriculum." }; // Not chosen: asks for one.

  const lines = String(formData.get("rows") ?? "") // The pasted rows:
    .split(/\r?\n/) // split into lines,
    .map((l) => l.trim()) // with spaces trimmed,
    .filter(Boolean); // dropping blank lines.
  if (lines.length === 0) return { error: "Paste at least one row." }; // Nothing pasted: asks for a row.
  if (lines.length > 3000) return { error: "Paste at most 3,000 rows at a time." }; // Too many: asks for fewer.

  const rows = []; // The rows to save.
  for (const [i, line] of lines.entries()) { // Goes through each line (i counts from 0):
    const [code, subject, levelBand, description, plain] = splitCsvLine(line); // splits it into its five cells.
    if (i === 0 && code?.toLowerCase() === "code") continue; // header row // Skips a heading row.
    if (!subject || !levelBand || !description) { // Missing a must-have cell:
      return { error: `Row ${i + 1} needs at least a subject, a year or level, and the skill wording.` }; // names the row to fix.
    } // End of that check.
    rows.push({ // Adds the row:
      framework_id: frameworkId.data, // to this curriculum,
      code: code || null, // its code (or none),
      subject: subject.slice(0, 100), // subject (up to 100 letters),
      level_band: levelBand.slice(0, 60), // level (up to 60 letters),
      description: description.slice(0, 2000), // official wording (up to 2,000 letters),
      plain_description: plain ? plain.slice(0, 500) : null, // plain wording (up to 500 letters, or none),
      sort_order: i, // and its place in the list.
    }); // End of the row.
  } // End of the loop.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("curriculum_skills").insert(rows); // Saves all the rows.
  if (error) { // Failed:
    return { // explains:
      error: // (the message)
        error.code === "23505" // if some codes are already loaded,
          ? "Some skill codes are already loaded for this curriculum. Remove those rows and try again." // that,
          : "Couldn't load the skills. Check the rows and try again.", // otherwise a general message.
    }; // End of the message.
  } // End of the failure case.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: `${rows.length} skills loaded.` }; // Confirms how many.
} // End of importSkills.

// Sets which curriculum a student follows.
export async function setStudentFramework(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = z // Checks the form has:
    .object({ student_id: z.uuid("Choose a student."), framework_id: z.uuid("Choose a curriculum.") }) // a student and a curriculum,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase // Saves the link:
    .from("student_frameworks") // in the student curriculums table,
    .upsert(parsed.data, { onConflict: "student_id,framework_id", ignoreDuplicates: true }); // skipping it if already set.
  if (error) return { error: "Couldn't set the curriculum." }; // Failed: plain message.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: "Curriculum set for this student." }; // Confirms it.
} // End of setStudentFramework.

// Confirm a draft curriculum once its summary looks right, or throw it away.
export async function confirmCurriculum(formData: FormData) {
  await requireAdmin(); // Makes sure the person is a full admin.
  const id = z.uuid().safeParse(formData.get("framework_id")); // Reads and checks which curriculum.
  if (!id.success) return; // Not a proper id: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("confirm_curriculum", { p_framework: id.data }); // Asks the database to confirm it.
  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
} // End of confirmCurriculum.

// Throws away a draft curriculum.
export async function discardCurriculum(formData: FormData) {
  await requireAdmin(); // Makes sure the person is a full admin.
  const id = z.uuid().safeParse(formData.get("framework_id")); // Reads and checks which curriculum.
  if (!id.success) return; // Not a proper id: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.rpc("discard_curriculum", { p_framework: id.data }); // Asks the database to discard it.
  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
} // End of discardCurriculum.

// Load many curricula at once from ACARA's Australian Curriculum file. The
// file is read in the admin's browser; only the chosen subjects arrive here.
// Each one is saved as a draft for an admin to check and confirm.
const acaraPayload = z // The rules for the chosen ACARA subjects:
  .array( // a list of:
    z.object({ // curriculums, each with:
      code: z.string().regex(/^[A-Za-z0-9_.-]{1,30}$/), // a short code,
      name: z.string().min(1).max(200), // a name,
      subject: z.string().min(1).max(100), // a subject,
      skills: z // skills:
        .array( // a list of:
          z.object({ // skills, each with:
            code: z.string().max(40), // a code,
            level_band: z.string().min(1).max(60), // a level,
            description: z.string().min(1).max(2000), // and wording.
          }), // (end of one skill)
        ) // (end of the list)
        .min(1) // at least 1,
        .max(1000), // and at most 1,000 per subject.
    }), // (end of one curriculum)
  ) // (end of the list)
  .min(1, "Tick at least one subject.") // At least one subject,
  .max(100); // and at most 100.

// Saves each chosen ACARA subject as a draft curriculum.
export async function importAcara(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  let raw: unknown; // Will hold the subjects as sent.
  try { // Reading could fail.
    raw = JSON.parse(String(formData.get("payload") ?? "[]")); // Reads the hidden field.
  } catch { // Couldn't read it:
    return { error: "Couldn't read the subjects. Please choose the file again." }; // asks to choose the file again.
  } // End of reading.
  const parsed = acaraPayload.safeParse(raw); // Checks the subjects against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const total = parsed.data.reduce((n, c) => n + c.skills.length, 0); // Counts all the skills.
  if (total > 5000) return { error: "That's too many skills at once. Choose fewer subjects." }; // Too many: asks for fewer subjects.

  const accessed = new Date().toLocaleDateString("en-AU", { // Today's date in words, for the licence credit:
    day: "numeric", // day number,
    month: "long", // full month name,
    year: "numeric", // year,
    timeZone: "Australia/Adelaide", // in Adelaide time.
  }); // End of the date.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const loaded: string[] = []; // Subjects loaded.
  const skipped: string[] = []; // Subjects skipped (already loaded).
  const failed: string[] = []; // Subjects that failed.

  for (const cur of parsed.data) { // Goes through each subject:
    const { data: fw, error } = await supabase // saves the curriculum:
      .from("curriculum_frameworks") // in the curriculums table,
      .insert({ code: cur.code, name: cur.name, version: ACARA_VERSION, source: acaraSource(accessed) }) // with code, name, version and licence credit,
      .select("id") // and gets back its id,
      .single(); // (one row).
    if (error || !fw) { // Failed:
      (error?.code === "23505" ? skipped : failed).push(cur.subject); // already loaded counts as skipped; anything else as failed,
      continue; // and moves on.
    } // End of that check.
    const rows = cur.skills.map((s, i) => ({ // Its skills as rows:
      framework_id: fw.id, // in this curriculum,
      subject: cur.subject, // subject,
      level_band: s.level_band, // level,
      code: s.code || null, // code (or none),
      description: s.description, // wording,
      sort_order: i, // and place in the list.
    })); // End of the rows.
    const { error: skillError } = await supabase.from("curriculum_skills").insert(rows); // Saves the skills.
    if (skillError) { // Failed:
      // Don't leave a half-loaded draft behind.
      await supabase.rpc("discard_curriculum", { p_framework: fw.id }); // throws away the half-loaded curriculum,
      failed.push(cur.subject); // notes it,
      continue; // and moves on.
    } // End of that check.
    loaded.push(cur.subject); // Notes it as loaded.
  } // End of the loop.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  const parts = []; // The parts of the message.
  if (loaded.length) parts.push(`${loaded.length} loaded as drafts. Check and confirm them above.`); // How many loaded.
  if (skipped.length) parts.push(`Already loaded, so skipped: ${skipped.join(", ")}.`); // Which were skipped.
  if (failed.length) parts.push(`Couldn't load: ${failed.join(", ")}. Please try those again.`); // Which failed.
  return loaded.length ? { message: parts.join(" ") } : { error: parts.join(" ") }; // A success message if any loaded, otherwise an error.
} // End of importAcara.

// Confirms every draft curriculum at once.
export async function confirmAllCurricula() {
  await requireAdmin(); // Makes sure the person is a full admin.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data } = await supabase.from("curriculum_frameworks").select("id").is("confirmed_at", null); // Reads every unconfirmed curriculum.
  for (const f of data ?? []) { // Goes through each:
    await supabase.rpc("confirm_curriculum", { p_framework: f.id }); // and asks the database to confirm it.
  } // End of the loop.
  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
} // End of confirmAllCurricula.

// Loads a whole curriculum from a spreadsheet in CLG's own layout (see
// src/lib/curriculum-file.ts). The file is read in the admin's browser; the
// rows arrive here and are saved as one draft for an admin to confirm.
const fileCurriculum = z.object({ // The rules for a curriculum from a spreadsheet:
  code: z.string().trim().regex(/^[A-Za-z0-9_.-]{1,30}$/, "Use a short code with no spaces, such as SACE-S1."), // a short code with no spaces,
  name: z.string().trim().min(1, "Enter the curriculum's name.").max(200), // its name,
  version: z.string().trim().min(1, "Enter the version or year, for example 2026.").max(40), // its version or year,
  source: z // where it comes from:
    .string() // text,
    .trim() // trimmed,
    .min(5, "Say where this curriculum comes from and that CLG may use it.") // at least 5 letters (and that CLG may use it),
    .max(1000), // up to 1,000.
  skills: z // the skills:
    .array( // a list of:
      z.object({ // skills, each with:
        code: z.string().max(40), // a code,
        subject: z.string().min(1).max(100), // a subject,
        level_band: z.string().min(1).max(60), // a level,
        description: z.string().min(1).max(2000), // official wording,
        plain_description: z.string().max(500), // and plain wording.
      }), // (end of one skill)
    ) // (end of the list)
    .min(1, "Choose a file with at least one skill.") // at least one,
    .max(5000, "That's too many skills at once. Split the file into smaller ones."), // and at most 5,000.
}); // End of the rules.

// Saves a whole curriculum from a spreadsheet as one draft.
export async function importCurriculumFile(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  let skills: unknown; // Will hold the skills as sent.
  try { // Reading could fail.
    skills = JSON.parse(String(formData.get("payload") ?? "[]")); // Reads the hidden field.
  } catch { // Couldn't read it:
    return { error: "Couldn't read the skills. Please choose the file again." }; // asks to choose the file again.
  } // End of reading.
  const parsed = fileCurriculum.safeParse({ // Checks everything against the rules:
    code: formData.get("code"), // code,
    name: formData.get("name"), // name,
    version: formData.get("version"), // version,
    source: formData.get("source"), // source,
    skills, // and skills.
  }); // End of the check.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const cur = parsed.data; // The checked values.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: fw, error } = await supabase // Saves the curriculum:
    .from("curriculum_frameworks") // in the curriculums table,
    .insert({ code: cur.code, name: cur.name, version: cur.version, source: cur.source }) // with code, name, version and source,
    .select("id") // and gets back its id,
    .single(); // (one row).
  if (error || !fw) { // Failed:
    return { // explains:
      error: // (the message)
        error?.code === "23505" // if that code and version exist,
          ? "A curriculum with that code and version is already loaded. Use a different code or version." // that,
          : "Couldn't add the curriculum. Please try again.", // otherwise a general message.
    }; // End of the message.
  } // End of the failure case.

  const rows = cur.skills.map((s, i) => ({ // Its skills as rows:
    framework_id: fw.id, // in this curriculum,
    code: s.code || null, // code (or none),
    subject: s.subject, // subject,
    level_band: s.level_band, // level,
    description: s.description, // official wording,
    plain_description: s.plain_description || null, // plain wording (or none),
    sort_order: i, // and place in the list.
  })); // End of the rows.
  const { error: skillError } = await supabase.from("curriculum_skills").insert(rows); // Saves the skills.
  if (skillError) { // Failed:
    // Don't leave a half-loaded draft behind.
    await supabase.rpc("discard_curriculum", { p_framework: fw.id }); // throws away the half-loaded curriculum,
    return { // and explains:
      error: // (the message)
        skillError.code === "23505" // if two rows share a code,
          ? "Two rows share the same skill code. Make each code different (or leave codes blank) and try again." // that,
          : "Couldn't load the skills. Check the file and try again.", // otherwise a general message.
    }; // End of the message.
  } // End of the failure case.

  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: `${rows.length} skills loaded as a draft. Check the summary above, then confirm it.` }; // Confirms how many, and what's next.
} // End of importCurriculumFile.
