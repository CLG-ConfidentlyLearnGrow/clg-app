"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import { checkDates } from "@/lib/check-dates";
import { CHECK_KINDS } from "@/lib/checks";
import { MAX_DOCUMENT_BYTES, documentType } from "@/lib/documents";
import { PLAIN_MATHS, YEAR_LEVELS } from "@/lib/students";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

async function requireTutor() {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("tutor")) throw new Error("Not a tutor");
  return viewer;
}

const hoursSchema = z.object({
  max_weekly_hours: z.coerce.number("Enter a number of hours.").min(0).max(60, "60 hours is the most allowed."),
});

// The most hours a tutor can work each week. Separate from availability.
export async function saveMaxHours(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireTutor();
  const parsed = hoursSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase
    .from("tutor_work_settings")
    .update({ max_weekly_hours: parsed.data.max_weekly_hours })
    .eq("tutor_id", viewer.id);
  if (error) return { error: "Couldn't save your hours." };

  revalidatePath("/dashboard", "layout");
  return { message: "Saved." };
}

const slotSchema = z
  .object({
    weekday: z.coerce.number().int().min(1).max(7),
    starts_at: z.iso.time("Enter a start time."),
    ends_at: z.iso.time("Enter an end time."),
  })
  .refine((v) => v.ends_at > v.starts_at, { message: "The end time must be after the start time." });

export async function addAvailability(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireTutor();
  const parsed = slotSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.from("tutor_availability").insert({ tutor_id: viewer.id, ...parsed.data });
  if (error) return { error: "Couldn't add that time." };

  revalidatePath("/dashboard", "layout");
  return { message: "Added." };
}

export async function removeAvailability(formData: FormData) {
  const viewer = await requireTutor();
  const id = z.uuid().safeParse(formData.get("id"));
  if (!id.success) return;

  const supabase = await createClient();
  await supabase.from("tutor_availability").delete().eq("id", id.data).eq("tutor_id", viewer.id);
  revalidatePath("/dashboard", "layout");
}

const myCheckSchema = z.object({
  kind: z.enum(CHECK_KINDS, "Choose the check."),
  reference: z.string().trim().max(100).optional(),
  completed_on: z.union([z.iso.date(), z.literal("")]).optional(),
  expires_on: z.union([z.iso.date(), z.literal("")]).optional(),
});

// A tutor adds or renews one of their own checks, with a copy of the
// certificate. It is logged and waits for CLG to confirm it against the
// official record before it counts.
export async function submitMyCheck(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireTutor();
  const { document, ...fields } = Object.fromEntries(formData);
  const parsed = myCheckSchema.safeParse(fields);
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const dates = checkDates(v.kind, v.reference, v.completed_on || undefined, v.expires_on || undefined);
  if ("error" in dates) return dates;

  if (!(document instanceof File) || document.size === 0) {
    return { error: "Attach a copy of your certificate or card (a PDF or a photo)." };
  }
  if (document.size > MAX_DOCUMENT_BYTES) {
    return { error: "That file is too big. Please use a file under 3.5 MB, or take a photo instead." };
  }
  const bytes = new Uint8Array(await document.arrayBuffer());
  const kind = documentType(bytes);
  if (!kind) return { error: "Please attach a PDF or a photo (JPG, PNG or WebP)." };

  const supabase = await createClient();
  const path = `${viewer.id}/${randomUUID()}.${kind.ext}`;
  const upload = await supabase.storage
    .from("check-documents")
    .upload(path, bytes, { contentType: kind.type, upsert: false });
  if (upload.error) return { error: "Couldn't upload your file. Please try again." };

  const { error } = await supabase.from("tutor_checks").insert({
    tutor_id: viewer.id,
    kind: v.kind,
    reference: v.reference || null,
    completed_on: v.completed_on || null,
    expires_on: dates.expiresOn,
    document_path: path,
  });
  if (error) {
    // Don't leave an unattached copy behind.
    await supabase.storage.from("check-documents").remove([path]);
    return { error: error.code === "23514" ? `${error.message}.` : "Couldn't save your check. Please try again." };
  }

  revalidatePath("/dashboard", "layout");
  revalidatePath("/admin");
  return { message: "Saved. CLG will check your copy against the official record." };
}

const teachingSchema = z
  .object({
    subject: z.string().trim().min(2, "Enter the subject.").max(100),
    from_level: z.enum(YEAR_LEVELS, "Choose the lowest year level."),
    to_level: z.enum(YEAR_LEVELS, "Choose the highest year level."),
  })
  .refine((v) => !PLAIN_MATHS.has(v.subject.toLowerCase()), {
    message: "Choose General Maths, Essential Maths or Advanced Maths. Add each one you teach separately.",
  })
  .refine((v) => YEAR_LEVELS.indexOf(v.from_level) <= YEAR_LEVELS.indexOf(v.to_level), {
    message: "The first year level needs to be the same as or below the second.",
  });

// A subject the tutor teaches, and the year levels they teach it for.
export async function addTeaching(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireTutor();
  const parsed = teachingSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.from("tutor_teaching").insert({ tutor_id: viewer.id, ...parsed.data });
  if (error) {
    return {
      error:
        error.code === "23505"
          ? "You've already added that subject. Remove it first to change its year levels."
          : "Couldn't save. Please try again.",
    };
  }
  revalidatePath("/dashboard", "layout");
  return { message: `${parsed.data.subject} added.` };
}

export async function removeTeaching(formData: FormData) {
  await requireTutor();
  const id = z.uuid().safeParse(formData.get("id"));
  if (!id.success) return;
  const supabase = await createClient();
  await supabase.from("tutor_teaching").delete().eq("id", id.data);
  revalidatePath("/dashboard", "layout");
}
