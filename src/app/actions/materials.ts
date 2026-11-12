// Summary: adding, tagging and publishing materials in the library. Admins
// only; the database checks again.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { redirect } from "next/navigation"; // Lets the code send someone to another page.
import { z } from "zod"; // The form-checking library.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is a full admin.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { MATERIAL_KINDS, MAX_VIEW_BYTES, VIEW_TYPES, titleFromFileName, viewFileType } from "@/lib/materials"; // Material kinds, size limit, file types, tidy titles and file type check.
import { checkPdf } from "@/lib/materials-stamp"; // Checks a PDF can be stamped and counts its pages.
import { YEAR_LEVELS, mathsProblem } from "@/lib/students"; // Year levels, and the maths naming check.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Adding, tagging and publishing materials. Admins only; the database
// checks again.

// The rules for a material's details:
const detailsSchema = z
  .object({ // (the fields:)
    kind: z.enum(MATERIAL_KINDS, "Choose what kind of material it is."), // kind (one of the list),
    subject: z.string().trim().min(2, "Enter the subject.").max(100), // subject (2 to 100 letters),
    from_level: z.enum(YEAR_LEVELS, "Choose the lowest year level it suits."), // lowest year level it suits,
    to_level: z.enum(YEAR_LEVELS, "Choose the highest year level it suits."), // highest year level it suits,
    description: z.string().trim().max(1000, "Keep the note under 1000 characters.").optional(), // a note (optional, up to 1,000 letters).
  }) // (end of the fields)
  .superRefine((v, ctx) => { // Extra check:
    const problem = mathsProblem(v.subject, v.to_level); // maths must be named correctly for the highest level,
    if (problem) ctx.addIssue({ code: "custom", message: problem }); // adds the problem if not.
  }) // End of the extra check.
  .refine((v) => YEAR_LEVELS.indexOf(v.from_level) <= YEAR_LEVELS.indexOf(v.to_level), { // And the lowest level can't be above the highest:
    message: "The first year level needs to be the same as or below the second.", // (the message if it is)
  }); // End of the rules.

// The rules for the list of uploaded files:
const uploadedSchema = z.array(
  z.object({ // each file has:
    viewPath: z.string().regex(/^view\/[0-9a-f-]{36}\.(pdf|jpg|png)$/), // its viewing copy's place in the store (view/<id>.pdf, .jpg or .png),
    fileName: z.string().max(300), // its original file name,
    title: z.string().trim().max(200).optional(), // an optional title,
    sourcePath: z // optionally, the editable original's place:
      .string() // (text)
      .regex(/^source\/[0-9a-f-]{36}\.[a-z]{3,4}$/) // in the form source/<id>.<ending>,
      .optional(), // (optional).
    sourceName: z.string().max(200).optional(), // the editable original's name (optional).
  }), // End of one file's rules.
).min(1, "Choose at least one file.").max(20, "Add up to 20 files at a time."); // At least 1 and at most 20 files.

// The files are already in the file store (the browser sent them there).
// Check each one, then save it as a draft ready for tagging.
export async function addMaterials(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const details = detailsSchema.safeParse(Object.fromEntries(formData)); // Checks the details.
  if (!details.success) return { error: details.error.issues[0].message }; // Shows the first rule that failed.
  let files: z.infer<typeof uploadedSchema>; // Will hold the checked file list.
  try { // Reading the list could fail.
    const parsed = uploadedSchema.safeParse(JSON.parse(String(formData.get("files_json") ?? "[]"))); // Reads and checks the hidden file list.
    if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
    files = parsed.data; // Keeps the checked list.
  } catch { // The list couldn't be read:
    return { error: "Choose at least one file." }; // asks to choose files.
  } // End of reading the list.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const store = supabase.storage.from("materials"); // The materials file store.
  const saved: string[] = []; // Ids of materials saved.
  const problems: string[] = []; // Plain messages about files that failed.

  for (const f of files) { // Goes through each file:
    const cleanUp = () => store.remove([f.viewPath, ...(f.sourcePath ? [f.sourcePath] : [])]); // helper to delete this file's uploads if it fails.
    const { data: blob, error: readError } = await store.download(f.viewPath); // Downloads the viewing copy to check it.
    if (readError || !blob) { // Didn't arrive:
      problems.push(`${f.fileName}: the upload didn't arrive. Please try again.`); // notes it,
      continue; // and moves on.
    } // End of that check.
    if (blob.size > MAX_VIEW_BYTES) { // Too big:
      await cleanUp(); // deletes the uploads,
      problems.push(`${f.fileName}: over 4 MB. Save it as a smaller PDF (for example "reduce file size" or lower picture quality) and try again.`); // explains how to make it smaller,
      continue; // and moves on.
    } // End of that check.
    const bytes = new Uint8Array(await blob.arrayBuffer()); // The file's contents.
    const ext = viewFileType(bytes); // Its real type from its first bytes.
    if (!ext || !f.viewPath.endsWith(`.${ext}`)) { // Not an allowed type, or doesn't match its name:
      await cleanUp(); // deletes the uploads,
      problems.push(`${f.fileName}: not a PDF, JPG or PNG.`); // notes it,
      continue; // and moves on.
    } // End of that check.
    let pages: number | null = 1; // Page count (pictures count as 1).
    if (ext === "pdf") { // For PDFs:
      const checked = await checkPdf(bytes); // checks it can be stamped,
      if ("error" in checked) { // it can't:
        await cleanUp(); // deletes the uploads,
        problems.push(`${f.fileName}: ${checked.error}`); // notes why,
        continue; // and moves on.
      } // End of that check.
      pages = checked.pages; // Keeps the page count.
    } // End of the PDF case.

    const { data: row, error } = await supabase // Saves the material as a draft:
      .from("materials") // in the materials table,
      .insert({ // with:
        title: f.title || titleFromFileName(f.fileName), // the title given, or one made from the file name,
        kind: details.data.kind, // kind,
        subject: details.data.subject, // subject,
        from_level: details.data.from_level, // lowest level,
        to_level: details.data.to_level, // highest level,
        description: details.data.description || null, // note (or none),
        file_path: f.viewPath, // viewing copy's place,
        file_type: VIEW_TYPES[ext], // its file type,
        file_bytes: bytes.byteLength, // its size,
        page_count: pages, // page count,
        source_path: f.sourcePath ?? null, // original's place (or none),
        source_name: f.sourceName?.slice(0, 200) ?? null, // original's name (or none).
      }) // End of the details.
      .select("id") // and gets back the new id,
      .single(); // (one row).
    if (error || !row) { // Save failed:
      await cleanUp(); // deletes the uploads,
      problems.push(`${f.fileName}: couldn't be saved. Please try again.`); // notes it,
      continue; // and moves on.
    } // End of that check.
    saved.push(row.id); // Remembers the saved id.
  } // End of the files loop.

  revalidatePath("/admin/materials"); // Refreshes the materials page.
  if (saved.length === 1 && problems.length === 0) { // Exactly one saved with no problems:
    redirect(`/admin/materials/${saved[0]}`); // goes straight to it for tagging.
  } // End of that case.
  const done = saved.length // What was done:
    ? `${saved.length} saved as drafts. Next, tag each one with its curriculum skills under "Library", then publish it.` // how many were saved, and what's next,
    : ""; // or nothing.
  return problems.length // Shows:
    ? { error: [done, ...problems].filter(Boolean).join(" ") } // what was done plus the problems,
    : { message: done }; // or just what was done.
} // End of addMaterials.

const idSchema = z.uuid(); // The rule for a proper id.

// Saves changes to a material's title and details.
export async function updateMaterialDetails(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const id = idSchema.safeParse(formData.get("id")); // Reads and checks the id.
  const details = detailsSchema.safeParse(Object.fromEntries(formData)); // Checks the details.
  const title = z.string().trim().min(2, "Enter a title.").max(200).safeParse(formData.get("title")); // Checks the title (2 to 200 letters).
  if (!id.success) return { error: "Something went wrong. Please reload the page." }; // Bad id: asks to reload.
  if (!title.success) return { error: title.error.issues[0].message }; // Bad title: shows why.
  if (!details.success) return { error: details.error.issues[0].message }; // Bad details: shows why.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase // Saves:
    .from("materials") // in the materials table,
    .update({ ...details.data, description: details.data.description || null, title: title.data }) // the details, note (or none) and title,
    .eq("id", id.data); // for this material.
  if (error) return { error: "Couldn't save the changes. Please try again." }; // Failed: plain message.
  revalidatePath(`/admin/materials/${id.data}`); // Refreshes this material's page.
  revalidatePath("/admin/materials"); // Refreshes the materials page.
  return { message: "Saved." }; // Tells the person it worked.
} // End of updateMaterialDetails.

// Tag with the ticked skills.
export async function addMaterialSkills(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const id = idSchema.safeParse(formData.get("id")); // Reads and checks the id.
  const skills = z.array(z.uuid()).max(300).safeParse(formData.getAll("skill")); // Reads and checks the ticked skills (up to 300).
  if (!id.success || !skills.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  if (skills.data.length === 0) return { error: "Tick at least one skill." }; // None ticked: asks for one.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase // Saves:
    .from("material_skills") // in the material skills table,
    .upsert( // adding:
      skills.data.map((skill_id) => ({ material_id: id.data, skill_id })), // one row per ticked skill,
      { onConflict: "material_id,skill_id", ignoreDuplicates: true }, // skipping any already there.
    ); // End of the rows.
  if (error) return { error: "Couldn't add those skills. Only skills from a confirmed curriculum can be used." }; // Failed: only confirmed curriculum skills can be used.
  revalidatePath(`/admin/materials/${id.data}`); // Refreshes this material's page.
  revalidatePath("/admin/materials"); // Refreshes the materials page.
  return { message: `Tagged with ${skills.data.length} skill${skills.data.length === 1 ? "" : "s"}.` }; // Confirms how many.
} // End of addMaterialSkills.

// Removes one skill from a material.
export async function removeMaterialSkill(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const id = idSchema.safeParse(formData.get("id")); // Reads and checks the material id.
  const skill = idSchema.safeParse(formData.get("skill")); // Reads and checks the skill id.
  if (!id.success || !skill.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.from("material_skills").delete().eq("material_id", id.data).eq("skill_id", skill.data); // Deletes that skill tag.
  if (error) { // Failed:
    return { // explains:
      error: // (the message)
        error.code === "23514" // if it was the last skill on a published material,
          ? "A published material needs at least one skill. Add another first, or retire the material." // that one is needed,
          : "Couldn't remove it. Please try again.", // otherwise a general message.
    }; // End of the message.
  } // End of the failure case.
  revalidatePath(`/admin/materials/${id.data}`); // Refreshes this material's page.
  revalidatePath("/admin/materials"); // Refreshes the materials page.
  return { message: "Removed." }; // Confirms it.
} // End of removeMaterialSkill.

// The rules for publishing or retiring:
const statusSchema = z.object({
  id: z.uuid(), // which material,
  status: z.enum(["published", "retired"]), // published or retired,
  no_skills_reason: z.string().trim().max(300).optional(), // why no skills fit (optional).
}); // End of the rules.

// Publishes or retires a material.
export async function setMaterialStatus(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const parsed = statusSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const change: Record<string, string | null> = { status: parsed.data.status }; // The change: the new stage.
  if (parsed.data.no_skills_reason !== undefined) change.no_skills_reason = parsed.data.no_skills_reason || null; // Adds the no-skills reason, if the box was on the form.
  const { error } = await supabase.from("materials").update(change).eq("id", parsed.data.id); // Saves the change.
  if (error) { // Failed:
    return { // explains:
      error: // (the message)
        error.code === "23514" // if no skills are tagged,
          ? "Tag at least one curriculum skill first, or if no curriculum fits, say why in the box." // what to do,
          : "Couldn't change it. Please try again.", // otherwise a general message.
    }; // End of the message.
  } // End of the failure case.
  revalidatePath(`/admin/materials/${parsed.data.id}`); // Refreshes this material's page.
  revalidatePath("/admin/materials"); // Refreshes the materials page.
  revalidatePath("/materials"); // Refreshes the tutors' materials page.
  return { // Tells the admin:
    message: // (the message)
      parsed.data.status === "published" // if published,
        ? "Published. Tutors who teach this subject at these year levels can now open it." // who can now open it,
        : "Retired. Tutors can no longer see it. You can publish it again at any time.", // otherwise that tutors can't see it.
  }; // End of the message.
} // End of setMaterialStatus.

// Only drafts can be deleted (with their files).
export async function deleteDraftMaterial(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin.
  const id = idSchema.safeParse(formData.get("id")); // Reads and checks the id.
  if (!id.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: m } = await supabase // Reads the material:
    .from("materials") // from the materials table,
    .select("file_path, source_path, status") // its file places and stage,
    .eq("id", id.data) // this one,
    .maybeSingle(); // (one at most).
  if (!m) return { error: "That material is already gone." }; // Not found: already gone.
  if (m.status !== "draft") return { error: "Only drafts can be deleted. Retire a published material instead." }; // Not a draft: explains to retire instead.
  const { error } = await supabase.from("materials").delete().eq("id", id.data); // Deletes the row.
  if (error) return { error: "Couldn't delete it. Please try again." }; // Failed: plain message.
  await supabase.storage.from("materials").remove([m.file_path, ...(m.source_path ? [m.source_path] : [])]); // Deletes its files from the store.
  revalidatePath("/admin/materials"); // Refreshes the materials page.
  redirect("/admin/materials?section=library"); // Goes back to the library.
} // End of deleteDraftMaterial.
