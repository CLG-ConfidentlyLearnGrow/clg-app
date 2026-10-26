"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import { STATES } from "@/lib/checks";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

const childSchema = z.object({
  full_name: z.string().trim().min(1, "Enter your child's name.").max(200),
  date_of_birth: z.iso.date("Enter your child's date of birth."),
  state: z.enum(STATES, "Choose the state your child lives in."),
  year_level: z.string().trim().max(40).optional(),
  school: z.string().trim().max(200).optional(),
});

export async function addChild(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("parent")) return { error: "Only parents can add a child." };

  const parsed = childSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.rpc("add_my_child", {
    p_full_name: parsed.data.full_name,
    p_date_of_birth: parsed.data.date_of_birth,
    p_state: parsed.data.state,
    p_year_level: parsed.data.year_level || null,
    p_school: parsed.data.school || null,
  });
  if (error) return { error: "We couldn't add your child. Please check the details and try again." };

  revalidatePath("/dashboard");
  return { message: `${parsed.data.full_name} has been added. CLG will confirm the details before a tutor is assigned.` };
}
