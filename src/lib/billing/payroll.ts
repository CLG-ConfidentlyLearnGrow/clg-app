import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { xeroPayroll } from "./xero";

// Sends pay lines to Xero Payroll as draft timesheets, one per person per
// pay period, for Carla to check and approve in Xero before the pay run.
// Each kind of work (school, tertiary, admin) goes on its own earnings rate.

export type XeroEmployee = { EmployeeID: string; FirstName: string; LastName: string; Email?: string; Status?: string };
export type XeroEarningsRate = { EarningsRateID: string; Name: string };

export async function listXeroEmployees(): Promise<XeroEmployee[]> {
  const res = await xeroPayroll<{ Employees: XeroEmployee[] }>("GET", "Employees");
  return (res.Employees ?? []).filter((e) => e.Status !== "TERMINATED");
}

export async function listXeroEarningsRates(): Promise<XeroEarningsRate[]> {
  const res = await xeroPayroll<{ PayItems: { EarningsRates: XeroEarningsRate[] } }>("GET", "PayItems");
  return res.PayItems?.EarningsRates ?? [];
}

// Hours per day across the period, as Xero's timesheet lines expect.
function dailyUnits(start: string, days: number, lines: { work_date: string; minutes: number }[]): number[] {
  const units = new Array(days).fill(0);
  const first = Date.parse(`${start}T00:00:00Z`);
  for (const l of lines) {
    const i = Math.round((Date.parse(`${l.work_date}T00:00:00Z`) - first) / 86400000);
    if (i >= 0 && i < days) units[i] += l.minutes / 60;
  }
  return units.map((u) => Math.round(u * 100) / 100);
}

export async function sendTimesheets(periodStart: string): Promise<{ sent: number; problems: string[] }> {
  const db = createAdminClient();
  const problems: string[] = [];
  const { data: period } = await db.rpc("billing_pay_period", { p_day: periodStart }).single<{ period_start: string; period_end: string }>();
  if (!period) return { sent: 0, problems: ["Couldn't work out the pay period."] };
  const days = Math.round((Date.parse(period.period_end) - Date.parse(period.period_start)) / 86400000) + 1;

  const { data: lines } = await db
    .from("billing_pay_lines")
    .select("id, account_id, staff_name, work_date, work_kind, minutes")
    .eq("status", "pending")
    .gte("work_date", period.period_start)
    .lte("work_date", period.period_end);
  const people = new Map<string, NonNullable<typeof lines>>();
  for (const l of lines ?? []) {
    if (!l.account_id) continue;
    people.set(l.account_id, [...(people.get(l.account_id) ?? []), l]);
  }
  if (people.size === 0) return { sent: 0, problems: [] };

  const { data: pay } = await db
    .from("billing_staff_pay")
    .select("account_id, xero_employee_id, xero_school_rate_id, xero_tertiary_rate_id, xero_admin_rate_id")
    .in("account_id", [...people.keys()]);
  const payOf = new Map((pay ?? []).map((p) => [p.account_id, p]));

  let sent = 0;
  for (const [accountId, own] of people) {
    const name = own[0].staff_name;
    const p = payOf.get(accountId);
    if (!p?.xero_employee_id) {
      problems.push(`${name}: not matched to a Xero employee yet.`);
      continue;
    }
    const rateId: Record<string, string | null> = {
      school: p.xero_school_rate_id,
      tertiary: p.xero_tertiary_rate_id,
      admin: p.xero_admin_rate_id,
    };
    const kinds = [...new Set(own.map((l) => l.work_kind))];
    const missing = kinds.filter((k) => !rateId[k]);
    if (missing.length) {
      problems.push(`${name}: choose a Xero earnings rate for ${missing.join(" and ")} work.`);
      continue;
    }
    try {
      const res = await xeroPayroll<{ Timesheets: { TimesheetID: string }[] }>(
        "POST",
        "Timesheets",
        [
          {
            EmployeeID: p.xero_employee_id,
            StartDate: period.period_start,
            EndDate: period.period_end,
            Status: "DRAFT",
            TimesheetLines: kinds.map((k) => ({
              EarningsRateID: rateId[k],
              NumberOfUnits: dailyUnits(period.period_start, days, own.filter((l) => l.work_kind === k)),
            })),
          },
        ],
        `timesheet-${accountId}-${period.period_start}`,
      );
      const id = res.Timesheets?.[0]?.TimesheetID;
      if (!id) throw new Error("Xero didn't return a timesheet.");
      const { error } = await db.rpc("billing_mark_pay_sent", { p_lines: own.map((l) => l.id), p_timesheet: id });
      if (error) throw new Error(error.message);
      sent++;
    } catch (e) {
      problems.push(`${name}: ${(e as Error).message}`);
    }
  }
  return { sent, problems };
}
