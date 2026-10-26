"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import { checkDates } from "@/lib/check-dates";
import { CHECK_KINDS } from "@/lib/checks";
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

// A tutor adds or renews one of their own checks. It is logged and waits for
// CLG to confirm it against the official record before it counts.
export async function submitMyCheck(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireTutor();
  const parsed = myCheckSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const dates = checkDates(v.kind, v.reference, v.completed_on || undefined, v.expires_on || undefined);
  if ("error" in dates) return dates;

  const supabase = await createClient();
  const { error } = await supabase.from("tutor_checks").insert({
    tutor_id: viewer.id,
    kind: v.kind,
    reference: v.reference || null,
    completed_on: v.completed_on || null,
    expires_on: dates.expiresOn,
  });
  if (error) {
    return { error: error.code === "23514" ? `${error.message}.` : "Couldn't save your check. Please try again." };
  }

  revalidatePath("/dashboard", "layout");
  revalidatePath("/admin");
  return { message: "Saved. CLG will confirm it against the official record." };
}
