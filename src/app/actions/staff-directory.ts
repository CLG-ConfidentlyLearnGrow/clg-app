"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// Staff directory module. Only this file changes job titles, and the
// database checks again that the person is the owner or an operations admin.

const titleSchema = z.object({
  account_id: z.uuid(),
  job_title: z.string().trim().max(80, "Keep the job title to 80 characters or fewer."),
});

export async function setJobTitle(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = titleSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const { account_id, job_title } = parsed.data;
  if (job_title.length === 1) return { error: "A job title needs at least 2 characters." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("set_staff_job_title", { p_account: account_id, p_title: job_title });
  if (error) {
    const plain = ["42501", "22023"].includes(error.code ?? "");
    return { error: plain ? `${error.message}.` : "Couldn't save the job title. Please try again." };
  }
  revalidatePath("/admin/staff");
  return { message: job_title ? "Saved" : "Removed" };
}
