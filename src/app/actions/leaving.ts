"use server";

// When a family or tutor leaves CLG, an admin records why. The database
// checks who can do this (full admins only).

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

const schema = z.object({
  who: z.string().regex(/^(family|tutor):[0-9a-f-]{36}$/, "Choose who left."),
  left_on: z.iso.date("Choose the day they left."),
  reason: z.string().min(1, "Choose the main reason."),
  details: z.string().trim().max(2000).optional(),
  left_happy: z.enum(["", "yes", "no"]).optional(),
});

export async function recordLeaving(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;
  const [kind, personId] = v.who.split(":");
  const supabase = await createClient();
  const { error } = await supabase.rpc("record_leaving", {
    p_who: kind,
    p_family: kind === "family" ? personId : null,
    p_tutor: kind === "tutor" ? personId : null,
    p_left_on: v.left_on,
    p_reason: v.reason,
    p_details: v.details || null,
    p_left_happy: v.left_happy === "yes" ? true : v.left_happy === "no" ? false : null,
    p_review_asked: formData.get("review_asked") === "on",
  });
  if (error) return { error: "Couldn't save the record. Only full admins can record why someone left." };
  revalidatePath("/admin");
  return { message: "Saved." };
}
