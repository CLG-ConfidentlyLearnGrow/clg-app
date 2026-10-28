"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { graphConfig } from "@/lib/teams/graph";
import { runTeamsSync } from "@/lib/teams/sync";
import { createClient } from "@/lib/supabase/server";

// Teams links: admin actions. Each re-checks the admin here, and the
// database checks again.

const PAGE = "/admin/teams";

function plain(error: { code?: string; message: string } | null, fallback: string): FormState {
  if (!error) return {};
  const ours = ["42501", "22023", "P0002"].includes(error.code ?? "");
  return { error: ours ? error.message : fallback };
}

const settingsSchema = z.object({
  enabled: z.literal("on").optional(),
  organiser_email: z.string().trim().max(320).optional(),
  days_ahead: z.coerce.number().int().min(1, "Days ahead must be 1 to 28.").max(28, "Days ahead must be 1 to 28."),
});

export async function saveTeamsSettings(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = settingsSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Please check the settings." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("save_teams_settings", {
    p_enabled: parsed.data.enabled === "on",
    p_organiser: parsed.data.organiser_email || null,
    p_days_ahead: parsed.data.days_ahead,
  });
  if (error) return plain(error, "Couldn't save the Teams settings.");
  revalidatePath(PAGE);
  return { message: "Saved." };
}

export async function runTeamsNow(): Promise<FormState> {
  await requireAdmin();
  if (!graphConfig()) {
    return { error: "The Microsoft app details aren't set in Vercel yet (MS_TENANT_ID, MS_CLIENT_ID, MS_CLIENT_SECRET)." };
  }
  const s = await runTeamsSync({ force: true });
  revalidatePath(PAGE);
  revalidatePath("/schedule");
  if (!s.ran && !s.problems.length) {
    return { error: "Nothing ran. Check Teams links are switched on with an organiser email, or wait 10 seconds and try again." };
  }
  const done = `Made ${s.made} link(s), deleted ${s.removed} finished or cancelled meeting(s).`;
  return s.problems.length ? { error: `${done} Problems: ${[...new Set(s.problems)].join(" ")}` } : { message: done };
}

const linkSchema = z.object({ session_id: z.uuid(), url: z.string().trim().max(2000) });

// Paste a link by hand (any meeting service), or clear one. The app then
// leaves that session alone.
export async function setMeetingLink(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = linkSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please paste the full meeting link." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_session_meeting_url", {
    p_session: parsed.data.session_id,
    p_url: parsed.data.url || null,
  });
  if (error) return plain(error, "Couldn't save the link.");
  revalidatePath(PAGE);
  revalidatePath("/schedule");
  return { message: parsed.data.url ? "Link saved." : "Link cleared." };
}
