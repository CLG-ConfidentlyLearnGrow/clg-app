"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { MATERIAL_KINDS, MAX_VIEW_BYTES, VIEW_TYPES, titleFromFileName, viewFileType } from "@/lib/materials";
import { checkPdf } from "@/lib/materials-stamp";
import { PLAIN_MATHS, YEAR_LEVELS } from "@/lib/students";
import { createClient } from "@/lib/supabase/server";

// Adding, tagging and publishing materials. Admins only; the database
// checks again.

const detailsSchema = z
  .object({
    kind: z.enum(MATERIAL_KINDS, "Choose what kind of material it is."),
    subject: z.string().trim().min(2, "Enter the subject.").max(100),
    from_level: z.enum(YEAR_LEVELS, "Choose the lowest year level it suits."),
    to_level: z.enum(YEAR_LEVELS, "Choose the highest year level it suits."),
    description: z.string().trim().max(1000, "Keep the note under 1000 characters.").optional(),
  })
  .refine((v) => !PLAIN_MATHS.has(v.subject.toLowerCase()), {
    message: "Choose General Maths, Essential Maths or Advanced Maths, so it reaches the right tutors.",
  })
  .refine((v) => YEAR_LEVELS.indexOf(v.from_level) <= YEAR_LEVELS.indexOf(v.to_level), {
    message: "The first year level needs to be the same as or below the second.",
  });

const uploadedSchema = z.array(
  z.object({
    viewPath: z.string().regex(/^view\/[0-9a-f-]{36}\.(pdf|jpg|png)$/),
    fileName: z.string().max(300),
    title: z.string().trim().max(200).optional(),
    sourcePath: z
      .string()
      .regex(/^source\/[0-9a-f-]{36}\.[a-z]{3,4}$/)
      .optional(),
    sourceName: z.string().max(200).optional(),
  }),
).min(1, "Choose at least one file.").max(20, "Add up to 20 files at a time.");

// The files are already in the file store (the browser sent them there).
// Check each one, then save it as a draft ready for tagging.
export async function addMaterials(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const details = detailsSchema.safeParse(Object.fromEntries(formData));
  if (!details.success) return { error: details.error.issues[0].message };
  let files: z.infer<typeof uploadedSchema>;
  try {
    const parsed = uploadedSchema.safeParse(JSON.parse(String(formData.get("files_json") ?? "[]")));
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    files = parsed.data;
  } catch {
    return { error: "Choose at least one file." };
  }

  const supabase = await createClient();
  const store = supabase.storage.from("materials");
  const saved: string[] = [];
  const problems: string[] = [];

  for (const f of files) {
    const cleanUp = () => store.remove([f.viewPath, ...(f.sourcePath ? [f.sourcePath] : [])]);
    const { data: blob, error: readError } = await store.download(f.viewPath);
    if (readError || !blob) {
      problems.push(`${f.fileName}: the upload didn't arrive. Please try again.`);
      continue;
    }
    if (blob.size > MAX_VIEW_BYTES) {
      await cleanUp();
      problems.push(`${f.fileName}: over 4 MB. Save it as a smaller PDF (for example "reduce file size" or lower picture quality) and try again.`);
      continue;
    }
    const bytes = new Uint8Array(await blob.arrayBuffer());
    const ext = viewFileType(bytes);
    if (!ext || !f.viewPath.endsWith(`.${ext}`)) {
      await cleanUp();
      problems.push(`${f.fileName}: not a PDF, JPG or PNG.`);
      continue;
    }
    let pages: number | null = 1;
    if (ext === "pdf") {
      const checked = await checkPdf(bytes);
      if ("error" in checked) {
        await cleanUp();
        problems.push(`${f.fileName}: ${checked.error}`);
        continue;
      }
      pages = checked.pages;
    }

    const { data: row, error } = await supabase
      .from("materials")
      .insert({
        title: f.title || titleFromFileName(f.fileName),
        kind: details.data.kind,
        subject: details.data.subject,
        from_level: details.data.from_level,
        to_level: details.data.to_level,
        description: details.data.description || null,
        file_path: f.viewPath,
        file_type: VIEW_TYPES[ext],
        file_bytes: bytes.byteLength,
        page_count: pages,
        source_path: f.sourcePath ?? null,
        source_name: f.sourceName?.slice(0, 200) ?? null,
      })
      .select("id")
      .single();
    if (error || !row) {
      await cleanUp();
      problems.push(`${f.fileName}: couldn't be saved. Please try again.`);
      continue;
    }
    saved.push(row.id);
  }

  revalidatePath("/admin/materials");
  if (saved.length === 1 && problems.length === 0) {
    redirect(`/admin/materials/${saved[0]}`);
  }
  const done = saved.length
    ? `${saved.length} saved as drafts. Next, tag each one with its curriculum skills under "Library", then publish it.`
    : "";
  return problems.length
    ? { error: [done, ...problems].filter(Boolean).join(" ") }
    : { message: done };
}

const idSchema = z.uuid();

export async function updateMaterialDetails(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const id = idSchema.safeParse(formData.get("id"));
  const details = detailsSchema.safeParse(Object.fromEntries(formData));
  const title = z.string().trim().min(2, "Enter a title.").max(200).safeParse(formData.get("title"));
  if (!id.success) return { error: "Something went wrong. Please reload the page." };
  if (!title.success) return { error: title.error.issues[0].message };
  if (!details.success) return { error: details.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase
    .from("materials")
    .update({ ...details.data, description: details.data.description || null, title: title.data })
    .eq("id", id.data);
  if (error) return { error: "Couldn't save the changes. Please try again." };
  revalidatePath(`/admin/materials/${id.data}`);
  revalidatePath("/admin/materials");
  return { message: "Saved." };
}

// Tag with the ticked skills.
export async function addMaterialSkills(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const id = idSchema.safeParse(formData.get("id"));
  const skills = z.array(z.uuid()).max(300).safeParse(formData.getAll("skill"));
  if (!id.success || !skills.success) return { error: "Something went wrong. Please reload the page." };
  if (skills.data.length === 0) return { error: "Tick at least one skill." };

  const supabase = await createClient();
  const { error } = await supabase
    .from("material_skills")
    .upsert(
      skills.data.map((skill_id) => ({ material_id: id.data, skill_id })),
      { onConflict: "material_id,skill_id", ignoreDuplicates: true },
    );
  if (error) return { error: "Couldn't add those skills. Only skills from a confirmed curriculum can be used." };
  revalidatePath(`/admin/materials/${id.data}`);
  revalidatePath("/admin/materials");
  return { message: `Tagged with ${skills.data.length} skill${skills.data.length === 1 ? "" : "s"}.` };
}

export async function removeMaterialSkill(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const id = idSchema.safeParse(formData.get("id"));
  const skill = idSchema.safeParse(formData.get("skill"));
  if (!id.success || !skill.success) return { error: "Something went wrong. Please reload the page." };

  const supabase = await createClient();
  const { error } = await supabase.from("material_skills").delete().eq("material_id", id.data).eq("skill_id", skill.data);
  if (error) {
    return {
      error:
        error.code === "23514"
          ? "A published material needs at least one skill. Add another first, or retire the material."
          : "Couldn't remove it. Please try again.",
    };
  }
  revalidatePath(`/admin/materials/${id.data}`);
  revalidatePath("/admin/materials");
  return { message: "Removed." };
}

const statusSchema = z.object({
  id: z.uuid(),
  status: z.enum(["published", "retired"]),
  no_skills_reason: z.string().trim().max(300).optional(),
});

export async function setMaterialStatus(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = statusSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Something went wrong. Please reload the page." };

  const supabase = await createClient();
  const change: Record<string, string | null> = { status: parsed.data.status };
  if (parsed.data.no_skills_reason !== undefined) change.no_skills_reason = parsed.data.no_skills_reason || null;
  const { error } = await supabase.from("materials").update(change).eq("id", parsed.data.id);
  if (error) {
    return {
      error:
        error.code === "23514"
          ? "Tag at least one curriculum skill first, or if no curriculum fits, say why in the box."
          : "Couldn't change it. Please try again.",
    };
  }
  revalidatePath(`/admin/materials/${parsed.data.id}`);
  revalidatePath("/admin/materials");
  revalidatePath("/materials");
  return {
    message:
      parsed.data.status === "published"
        ? "Published. Tutors who teach this subject at these year levels can now open it."
        : "Retired. Tutors can no longer see it. You can publish it again at any time.",
  };
}

// Only drafts can be deleted (with their files).
export async function deleteDraftMaterial(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const id = idSchema.safeParse(formData.get("id"));
  if (!id.success) return { error: "Something went wrong. Please reload the page." };

  const supabase = await createClient();
  const { data: m } = await supabase
    .from("materials")
    .select("file_path, source_path, status")
    .eq("id", id.data)
    .maybeSingle();
  if (!m) return { error: "That material is already gone." };
  if (m.status !== "draft") return { error: "Only drafts can be deleted. Retire a published material instead." };
  const { error } = await supabase.from("materials").delete().eq("id", id.data);
  if (error) return { error: "Couldn't delete it. Please try again." };
  await supabase.storage.from("materials").remove([m.file_path, ...(m.source_path ? [m.source_path] : [])]);
  revalidatePath("/admin/materials");
  redirect("/admin/materials?section=library");
}
