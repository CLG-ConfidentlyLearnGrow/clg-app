// Summary: admin actions for Teams meeting links: save settings, run the
// links job now, and paste or clear a link by hand.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is a full admin.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { graphConfig } from "@/lib/teams/graph"; // Checks whether the Microsoft settings are in Vercel.
import { runTeamsSync } from "@/lib/teams/sync"; // The Teams links job.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Teams links: admin actions. Each re-checks the admin here, and the
// database checks again.

const PAGE = "/admin/teams"; // The admin Teams page, refreshed after changes.

// Turns a database error into a reply: its own plain message, or a general one.
function plain(error: { code?: string; message: string } | null, fallback: string): FormState {
  if (!error) return {}; // No error: nothing to report.
  const ours = ["42501", "22023", "P0002"].includes(error.code ?? ""); // True for the database's own plain refusals.
  return { error: ours ? error.message : fallback }; // Shows that message, or the general one.
} // End of plain.

// The rules for the settings form:
const settingsSchema = z.object({
  enabled: z.literal("on").optional(), // switched on (tick box),
  organiser_email: z.string().trim().max(320).optional(), // the organiser's Microsoft email (optional),
  organiser_id: z.string().trim().max(100).optional(), // the organiser's Microsoft Object ID (optional; the database checks its shape),
  days_ahead: z.coerce.number().int().min(1, "Days ahead must be 1 to 28.").max(28, "Days ahead must be 1 to 28."), // how many days ahead to make links (1 to 28).
}); // End of the rules.

// Saves the Teams settings.
export async function saveTeamsSettings(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  const parsed = settingsSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Please check the settings." }; // Shows the first problem.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("save_teams_settings", { // Asks the database to save:
    p_enabled: parsed.data.enabled === "on", // on or off,
    p_organiser: parsed.data.organiser_email || null, // the organiser email (or none),
    p_organiser_id: parsed.data.organiser_id || null, // the organiser's Object ID (or none),
    p_days_ahead: parsed.data.days_ahead, // and the days ahead.
  }); // End of the save.
  if (error) return plain(error, "Couldn't save the Teams settings."); // Failed: plain message.
  revalidatePath(PAGE); // Refreshes the Teams page.
  return { message: "Saved." }; // Tells the person it worked.
} // End of saveTeamsSettings.

// Runs the Teams links job straight away (the admin button).
export async function runTeamsNow(): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  if (!graphConfig()) { // Microsoft settings missing:
    return { error: "The Microsoft app details aren't set in Vercel yet (MS_TENANT_ID, MS_CLIENT_ID, MS_CLIENT_SECRET)." }; // explains which settings are needed.
  } // End of that case.
  const s = await runTeamsSync({ force: true }); // Runs the job, skipping the usual wait.
  revalidatePath(PAGE); // Refreshes the Teams page.
  revalidatePath("/schedule"); // Refreshes the schedule page.
  if (!s.ran && !s.problems.length) { // Nothing ran and no problems:
    return { error: "Nothing ran. Check Teams links are switched on with an organiser email and Object ID, or wait 10 seconds and try again." }; // explains why that might be.
  } // End of that case.
  const done = `Made ${s.made} link(s), deleted ${s.removed} finished or cancelled meeting(s).`; // What was done.
  return s.problems.length ? { error: `${done} Problems: ${[...new Set(s.problems)].join(" ")}` } : { message: done }; // Shows that with any problems (no repeats), or just what was done.
} // End of runTeamsNow.

const linkSchema = z.object({ session_id: z.uuid(), url: z.string().trim().max(2000) }); // The rules for the link form: which session, and the link (up to 2,000 letters).

// Paste a link by hand (any meeting service), or clear one. The app then
// leaves that session alone.
// Saves or clears one session's meeting link.
export async function setMeetingLink(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is a full admin (sends anyone else away).
  const parsed = linkSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: "Please paste the full meeting link." }; // Problem: asks for the full link.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("set_session_meeting_url", { // Asks the database to save:
    p_session: parsed.data.session_id, // for this session,
    p_url: parsed.data.url || null, // this link (blank clears it).
  }); // End of the save.
  if (error) return plain(error, "Couldn't save the link."); // Failed: plain message.
  revalidatePath(PAGE); // Refreshes the Teams page.
  revalidatePath("/schedule"); // Refreshes the schedule page.
  return { message: parsed.data.url ? "Link saved." : "Link cleared." }; // Confirms saved or cleared.
} // End of setMeetingLink.
