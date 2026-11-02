"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requireAdmin, requireViewer } from "@/lib/auth";
import { POLICY_VERSION, type FormState } from "@/lib/forms";
import { giveParentalConsent } from "@/lib/consent";
import { PRIVACY_REQUEST_KINDS, REGIONS } from "@/lib/privacy";
import { createClient } from "@/lib/supabase/server";

// ---------------------------------------------------------------------------
// For everyone: requests, marketing emails, parental consent
// ---------------------------------------------------------------------------

const requestSchema = z.object({
  kind: z.enum(PRIVACY_REQUEST_KINDS.map((k) => k.id) as [string, ...string[]], { message: "Please choose what you'd like." }),
  details: z.string().trim().min(3, "Please tell us a little more.").max(2000, "Please keep it under 2000 characters."),
  student_id: z.union([z.uuid(), z.literal("")]).optional(),
});

export async function makePrivacyRequest(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const parsed = requestSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("make_privacy_request", {
    p_kind: parsed.data.kind,
    p_details: parsed.data.details,
    p_student: parsed.data.student_id || undefined,
  });
  if (error) {
    return { error: error.code === "54000" ? error.message : "We couldn't send that. Please try again, or email CLG." };
  }
  revalidatePath("/my-privacy");
  return { message: "Sent. CLG will reply within 28 days, and you can follow it below." };
}

export async function setMarketingEmail(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const on = formData.get("marketing") === "on";
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_marketing_email", { p_on: on, p_version: POLICY_VERSION });
  if (error) return { error: "We couldn't save that. Please try again." };
  revalidatePath("/my-privacy");
  return { message: on ? "You'll get CLG news and offers by email. You can turn this off any time." : "You won't get news or offers. You'll still get messages about your sessions and invoices." };
}

export async function agreeForChildren(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer();
  const supabase = await createClient();
  const { data } = await supabase.rpc("children_needing_consent");
  const needed = ((data ?? []) as { student_id: string }[]).map((c) => c.student_id);
  const ticked = needed.filter((id) => formData.get(`child_${id}`) === "on");
  if (ticked.length < needed.length) return { error: "Please tick the box for each child to carry on." };
  if (!(await giveParentalConsent(ticked))) return { error: "We couldn't save that. Please try again." };
  redirect("/dashboard");
}

// ---------------------------------------------------------------------------
// For admins (owner or operations): requests and the breach register
// ---------------------------------------------------------------------------

const updateSchema = z.object({
  id: z.uuid(),
  status: z.enum(["in_progress", "done", "refused"]),
  outcome: z.string().trim().max(2000).optional(),
  extend_to: z.union([z.iso.date(), z.literal("")]).optional(),
  extension_reason: z.string().trim().max(500).optional(),
});

export async function updatePrivacyRequest(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = updateSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const supabase = await createClient();
  const { error } = await supabase.rpc("update_privacy_request", {
    p_id: parsed.data.id,
    p_status: parsed.data.status,
    p_outcome: parsed.data.outcome || undefined,
    p_extend_to: parsed.data.extend_to || undefined,
    p_extension_reason: parsed.data.extension_reason || undefined,
  });
  if (error) return { error: error.message };
  revalidatePath("/admin/privacy");
  return { message: "Saved. Remember to tell the person what's happening." };
}

const incidentSchema = z.object({
  title: z.string().trim().min(3, "Give it a short title.").max(200),
  what_happened: z.string().trim().min(3, "Say briefly what happened.").max(4000),
  found_at: z.string().min(1, "When did CLG find out?"),
  data_involved: z.string().trim().max(1000).optional(),
  people_affected: z.union([z.coerce.number().int().min(0), z.literal("")]).optional(),
});

// Times typed into the form are Adelaide times.
function adelaideToIso(local: string): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(local);
  if (!m) return null;
  const asUtc = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
  // Adelaide's offset at that moment (+9:30 or +10:30).
  const parts = new Intl.DateTimeFormat("en-AU", { timeZone: "Australia/Adelaide", timeZoneName: "longOffset" })
    .formatToParts(new Date(asUtc))
    .find((p) => p.type === "timeZoneName")?.value;
  const off = /GMT([+-])(\d{2}):(\d{2})/.exec(parts ?? "");
  const minutes = off ? (off[1] === "-" ? -1 : 1) * (+off[2] * 60 + +off[3]) : 570;
  return new Date(asUtc - minutes * 60_000).toISOString();
}

export async function recordIncident(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = incidentSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const foundAt = adelaideToIso(parsed.data.found_at);
  if (!foundAt) return { error: "Please check the date and time found." };
  const regions = formData.getAll("regions").map(String).filter((r) => REGIONS.some((x) => x.id === r));
  if (regions.length === 0) return { error: "Tick where the people affected live (Australia if unsure)." };
  const supabase = await createClient();
  const { error } = await supabase.from("privacy_incidents").insert({
    title: parsed.data.title,
    what_happened: parsed.data.what_happened,
    found_at: foundAt,
    data_involved: parsed.data.data_involved || null,
    people_affected: parsed.data.people_affected === "" || parsed.data.people_affected === undefined ? null : parsed.data.people_affected,
    children_affected: formData.get("children_affected") === "on",
    regions,
  });
  if (error) return { error: "We couldn't save that. Check the date isn't in the future, then try again." };
  revalidatePath("/admin/privacy");
  return { message: "Recorded. The 72-hr clock has started: follow the next step shown." };
}

const incidentUpdateSchema = z.object({
  id: z.uuid(),
  step: z.enum(["contained", "assessed_serious", "assessed_not_serious", "regulators", "people", "close"]),
  note: z.string().trim().max(2000).optional(),
});

export async function updateIncident(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = incidentUpdateSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please choose what's happened." };
  const now = new Date().toISOString();
  const note = parsed.data.note || null;
  const change: Record<string, unknown> =
    parsed.data.step === "contained"
      ? { contained_at: now }
      : parsed.data.step === "assessed_serious"
        ? { serious_harm_likely: true, decision_reason: note }
        : parsed.data.step === "assessed_not_serious"
          ? { serious_harm_likely: false, decision_reason: note }
          : parsed.data.step === "regulators"
            ? { regulators_told_at: now, regulators_told: note }
            : parsed.data.step === "people"
              ? { people_told_at: now }
              : { closed_at: now, lessons: note };
  if ((parsed.data.step.startsWith("assessed") || parsed.data.step === "regulators") && !note) {
    return { error: parsed.data.step === "regulators" ? "Write which regulators were told." : "Write the reason for the decision." };
  }
  const supabase = await createClient();
  const { error } = await supabase.from("privacy_incidents").update(change).eq("id", parsed.data.id);
  if (error) {
    return {
      error:
        parsed.data.step === "close"
          ? "It can't be closed yet: decide on serious harm first, and if harm is likely, record telling the regulators."
          : "We couldn't save that. Please try again.",
    };
  }
  revalidatePath("/admin/privacy");
  return { message: "Saved." };
}
