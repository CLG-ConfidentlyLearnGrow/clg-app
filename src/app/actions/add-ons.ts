"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { FULL_ADMIN, requireAdminLevel } from "@/lib/auth";
import { parseDollars } from "@/lib/billing/money";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// Add-ons: extras on top of tutoring, such as study plans. The owner
// decides whether each one is free, paid or off; admins give a paid add-on
// to the students who pay for it. Every action re-checks who is asking
// here, and the database checks again.

const ADMIN_PAGE = "/admin";
const day = z.union([z.literal(""), z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Choose a date.")]);

const setSchema = z.object({
  code: z.string().regex(/^[a-z0-9_]{2,40}$/),
  mode: z.enum(["free", "paid", "off"]),
  price: z.string().trim().max(20).optional().default(""),
  price_period: z.enum(["week", "month", "term"]),
});

export async function setAddOn(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireAdminLevel(FULL_ADMIN);
  if (viewer.level !== "owner") return { error: "Only the owner can change an add-on." };
  const parsed = setSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please check the form and try again." };
  const v = parsed.data;

  let cents: number | null = null;
  if (v.price !== "") {
    cents = parseDollars(v.price);
    if (cents === null) return { error: "Enter the price in dollars, for example 25 or 29.50." };
  }
  if (v.mode === "paid" && !cents) return { error: "Set a price before making it paid." };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("add_ons")
    .update({ mode: v.mode, price_cents: cents, price_period: v.price_period, gst_applies: formData.get("gst_applies") === "on" })
    .eq("code", v.code)
    .select("code");
  if (error || !data?.length) return { error: "Couldn't save it. Please try again." };
  revalidatePath(ADMIN_PAGE);
  return {
    message:
      v.mode === "paid"
        ? "Saved. Only students you give it to below can use it now. No one is charged automatically yet."
        : "Saved.",
  };
}

const giveSchema = z.object({
  add_on: z.string().regex(/^[a-z0-9_]{2,40}$/),
  student_id: z.uuid("Choose a student."),
  starts_on: day,
  ends_on: day,
  note: z.string().trim().max(300, "Keep the note under 300 characters.").optional().default(""),
});

export async function giveAddOn(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FULL_ADMIN);
  const parsed = giveSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  if (v.starts_on && v.ends_on && v.ends_on < v.starts_on) return { error: "The end date is before the start date." };

  const supabase = await createClient();
  const row: Record<string, string | null> = {
    add_on: v.add_on,
    student_id: v.student_id,
    ends_on: v.ends_on || null,
    note: v.note || null,
  };
  if (v.starts_on) row.starts_on = v.starts_on;
  const { error } = await supabase.from("add_on_members").upsert(row, { onConflict: "add_on,student_id" });
  if (error) return { error: "Couldn't save it. Please try again." };
  revalidatePath(ADMIN_PAGE);
  return { message: "Saved." };
}

export async function endAddOn(formData: FormData) {
  await requireAdminLevel(FULL_ADMIN);
  const parsed = z
    .object({ add_on: z.string().regex(/^[a-z0-9_]{2,40}$/), student_id: z.uuid() })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return;
  const supabase = await createClient();
  await supabase.from("add_on_members").delete().eq("add_on", parsed.data.add_on).eq("student_id", parsed.data.student_id);
  revalidatePath(ADMIN_PAGE);
}
