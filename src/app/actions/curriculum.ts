"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// Loading curricula into the shared skill library. Admins only; the
// database checks again.

const frameworkSchema = z.object({
  code: z.string().trim().regex(/^[A-Za-z0-9_.-]{1,30}$/, "Use a short code such as AC9 or SACE."),
  name: z.string().trim().min(1, "Enter the curriculum's name.").max(200),
  version: z.string().trim().min(1, "Enter the version, for example 9.0.").max(40),
  starts_on: z.union([z.iso.date(), z.literal("")]).optional(),
});

export async function createFramework(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = frameworkSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.from("curriculum_frameworks").insert({
    code: parsed.data.code,
    name: parsed.data.name,
    version: parsed.data.version,
    starts_on: parsed.data.starts_on || null,
  });
  if (error) return { error: "Couldn't add it. That code and version may already exist." };

  revalidatePath("/admin");
  return { message: "Curriculum added. Now load its skills." };
}

// Splits one CSV line, allowing "quoted, text" with commas inside.
function splitCsvLine(line: string): string[] {
  const cells: string[] = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') {
        cell += '"';
        i++;
      } else if (ch === '"') {
        quoted = false;
      } else {
        cell += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === "," || ch === "\t") {
      cells.push(cell.trim());
      cell = "";
    } else {
      cell += ch;
    }
  }
  cells.push(cell.trim());
  return cells;
}

// Rows: code, subject, year or level, official wording, plain wording.
export async function importSkills(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const frameworkId = z.uuid().safeParse(formData.get("framework_id"));
  if (!frameworkId.success) return { error: "Choose a curriculum." };

  const lines = String(formData.get("rows") ?? "")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  if (lines.length === 0) return { error: "Paste at least one row." };
  if (lines.length > 3000) return { error: "Paste at most 3,000 rows at a time." };

  const rows = [];
  for (const [i, line] of lines.entries()) {
    const [code, subject, levelBand, description, plain] = splitCsvLine(line);
    if (i === 0 && code?.toLowerCase() === "code") continue; // header row
    if (!subject || !levelBand || !description) {
      return { error: `Row ${i + 1} needs at least a subject, a year or level, and the skill wording.` };
    }
    rows.push({
      framework_id: frameworkId.data,
      code: code || null,
      subject: subject.slice(0, 100),
      level_band: levelBand.slice(0, 60),
      description: description.slice(0, 2000),
      plain_description: plain ? plain.slice(0, 500) : null,
      sort_order: i,
    });
  }

  const supabase = await createClient();
  const { error } = await supabase.from("curriculum_skills").insert(rows);
  if (error) {
    return {
      error:
        error.code === "23505"
          ? "Some skill codes are already loaded for this curriculum. Remove those rows and try again."
          : "Couldn't load the skills. Check the rows and try again.",
    };
  }

  revalidatePath("/admin");
  return { message: `${rows.length} skills loaded.` };
}

export async function setStudentFramework(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = z
    .object({ student_id: z.uuid("Choose a student."), framework_id: z.uuid("Choose a curriculum.") })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase
    .from("student_frameworks")
    .upsert(parsed.data, { onConflict: "student_id,framework_id", ignoreDuplicates: true });
  if (error) return { error: "Couldn't set the curriculum." };

  revalidatePath("/admin");
  return { message: "Curriculum set for this student." };
}
