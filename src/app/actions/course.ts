"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdminLevel } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// An admin writes a short overview of a university or TAFE unit, so the
// tutor can read about it before the first session. Blank clears it.
// See docs/features/tertiary-study-details.md.
const schema = z.object({
  subject_id: z.uuid(),
  overview: z.string().trim().max(4000, "Please keep the overview under 4,000 characters."),
});

export async function setCourseOverview(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner", "operations", "support"]);
  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_course_overview", {
    p_subject: parsed.data.subject_id,
    p_overview: parsed.data.overview,
  });
  if (error) {
    console.error("Set course overview failed:", error.code, error.message);
    return { error: error.code === "22023" ? `${error.message}.` : "We couldn't save the overview. Please try again." };
  }
  revalidatePath("/admin");
  return { message: parsed.data.overview ? "Overview saved. The tutor will see it." : "Overview cleared." };
}
