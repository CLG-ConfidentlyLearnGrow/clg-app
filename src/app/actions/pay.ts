"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { PAY, requireAdminLevel } from "@/lib/auth";
import type { FormState } from "@/lib/forms";
import { xeroConfig } from "@/lib/billing/config";
import { parseDollars } from "@/lib/billing/money";
import { sendTimesheets } from "@/lib/billing/payroll";
import { xeroConnection } from "@/lib/billing/xero";
import { createClient } from "@/lib/supabase/server";

// Tutor and staff pay. Every action re-checks admin access here, and the
// database checks again.

const PAGE = "/admin/billing";
const uuid = z.uuid();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Choose a date.");

function plain(error: { code?: string; message: string } | null, fallback: string): FormState {
  if (!error) return {};
  const ours = ["42501", "22023", "23505", "23514"].includes(error.code ?? "");
  return { error: ours ? `${error.message}.` : fallback };
}

// "" means not entered; otherwise dollars to cents. Undefined means invalid.
function rate(text: FormDataEntryValue | null): number | null | undefined {
  const t = String(text ?? "").trim();
  if (t === "") return null;
  return parseDollars(t) ?? undefined;
}

export async function saveStaffPay(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY);
  const parsed = z
    .object({
      account_id: uuid,
      employment: z.enum(["casual", "part_time", "full_time"]),
      xero_employee_id: z.string().max(100).optional(),
      xero_school_rate_id: z.string().max(100).optional(),
      xero_tertiary_rate_id: z.string().max(100).optional(),
      xero_admin_rate_id: z.string().max(100).optional(),
    })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Please check the details." };
  const rates = {
    school_rate_cents: rate(formData.get("school_rate")),
    tertiary_rate_cents: rate(formData.get("tertiary_rate")),
    admin_rate_cents: rate(formData.get("admin_rate")),
  };
  if (Object.values(rates).some((r) => r === undefined)) {
    return { error: "Enter hourly rates in dollars, for example 34 or 62.88. Leave a rate empty if it doesn't apply." };
  }
  const xero = (v?: string) => (v && v.trim() ? v.trim() : null);
  const supabase = await createClient();
  const { error } = await supabase.from("billing_staff_pay").upsert({
    account_id: parsed.data.account_id,
    employment: parsed.data.employment,
    ...rates,
    ...(formData.has("xero_employee_id")
      ? {
          xero_employee_id: xero(parsed.data.xero_employee_id),
          xero_school_rate_id: xero(parsed.data.xero_school_rate_id),
          xero_tertiary_rate_id: xero(parsed.data.xero_tertiary_rate_id),
          xero_admin_rate_id: xero(parsed.data.xero_admin_rate_id),
        }
      : {}),
  });
  if (error) return plain(error, "Couldn't save the pay details.");
  revalidatePath(PAGE);
  return { message: "Pay details saved. Pay already sent to Xero doesn't change." };
}

export async function addAdminTime(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY);
  const parsed = z
    .object({ account_id: uuid, day, hours: z.string(), note: z.string().max(300).optional() })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Choose the person, the day and the hours." };
  const hours = Number(parsed.data.hours.replace(",", "."));
  if (!Number.isFinite(hours) || hours <= 0) return { error: "Enter the hours, for example 1.5." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("billing_add_admin_time", {
    p_account: parsed.data.account_id,
    p_day: parsed.data.day,
    p_minutes: Math.round(hours * 60),
    p_note: parsed.data.note ?? "",
  });
  if (error) return plain(error, "Couldn't record the admin hours.");
  revalidatePath(PAGE);
  return { message: "Admin hours recorded." };
}

export async function removePayLine(formData: FormData) {
  await requireAdminLevel(PAY);
  const id = uuid.safeParse(formData.get("id"));
  if (!id.success) return;
  const supabase = await createClient();
  await supabase.rpc("billing_remove_pay_line", { p_line: id.data });
  revalidatePath(PAGE);
}

export async function workOutPay(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY);
  const parsed = z.object({ from: day, to: day }).safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Choose the pay period." };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("billing_build_pay", { p_from: parsed.data.from, p_to: parsed.data.to });
  if (error) return plain(error, "Couldn't work out pay.");
  revalidatePath(PAGE);
  return { message: `Pay worked out: ${data ?? 0} line(s) waiting to go to Xero.` };
}

export async function sendTimesheetsNow(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY);
  const start = day.safeParse(formData.get("period_start"));
  if (!start.success) return { error: "Choose the pay period." };
  if (!xeroConfig() || !(await xeroConnection())) {
    return { error: "Connect Xero first (Stripe and Xero section). Until then, use these lines to enter pay by hand." };
  }
  const supabase = await createClient();
  // Work it out again first so the latest confirmed times are used.
  const { data: period } = await supabase.rpc("billing_pay_period", { p_day: start.data }).single<{ period_start: string; period_end: string }>();
  if (period) await supabase.rpc("billing_build_pay", { p_from: period.period_start, p_to: period.period_end });
  const result = await sendTimesheets(start.data);
  revalidatePath(PAGE);
  const done = `Sent ${result.sent} draft timesheet(s) to Xero Payroll. Check and approve them in Xero before the pay run.`;
  return result.problems.length ? { error: `${done} Not sent: ${result.problems.join(" ")}` } : { message: done };
}

export async function savePayPeriod(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(PAY);
  const parsed = z
    .object({ pay_period_days: z.enum(["7", "14"]), pay_period_anchor: day, casual_min_enabled: z.string().optional() })
    .safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Choose weekly or fortnightly, and a day a pay period starts." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("billing_settings")
    .update({
      pay_period_days: Number(parsed.data.pay_period_days),
      pay_period_anchor: parsed.data.pay_period_anchor,
      casual_min_enabled: parsed.data.casual_min_enabled === "on",
    })
    .eq("id", true)
    .select("id");
  if (error || !data?.length) return { error: "Only the owner can change the pay period." };
  revalidatePath(PAGE);
  return { message: "Pay settings saved. The pay period must match the pay calendar in Xero. Use \"Work out pay again\" to apply a change to this period." };
}
