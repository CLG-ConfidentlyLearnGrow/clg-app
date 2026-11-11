// Summary: sends pay lines to Xero Payroll as draft timesheets, one per
// person per pay period, for Carla to check and approve in Xero before the
// pay run. Each kind of work (school, tertiary, admin) goes on its own
// earnings rate.

// Stops this file ever being sent to the browser.
import "server-only";
// The all-powerful database helper, used because this runs as a background job.
import { createAdminClient } from "@/lib/supabase/admin";
// The helper that sends requests to Xero Payroll.
import { xeroPayroll } from "./xero";

// One employee as Xero describes them.
export type XeroEmployee = { EmployeeID: string; FirstName: string; LastName: string; Email?: string; Status?: string };
// One earnings rate (a kind of pay) as Xero describes it.
export type XeroEarningsRate = { EarningsRateID: string; Name: string };

// Gets CLG's current employees from Xero, for matching staff to Xero.
export async function listXeroEmployees(): Promise<XeroEmployee[]> {
  const res = await xeroPayroll<{ Employees: XeroEmployee[] }>("GET", "Employees"); // Asks Xero for the employee list.
  return (res.Employees ?? []).filter((e) => e.Status !== "TERMINATED"); // Leaves out people who have left.
} // End of listXeroEmployees.

// Gets CLG's earnings rates from Xero, so admin can pick one per kind of work.
export async function listXeroEarningsRates(): Promise<XeroEarningsRate[]> {
  const res = await xeroPayroll<{ PayItems: { EarningsRates: XeroEarningsRate[] } }>("GET", "PayItems"); // Asks Xero for its pay items.
  return res.PayItems?.EarningsRates ?? []; // Hands back just the earnings rates (none if missing).
} // End of listXeroEarningsRates.

// Hours per day across the period, as Xero's timesheet lines expect.
function dailyUnits(start: string, days: number, lines: { work_date: string; minutes: number }[]): number[] {
  const units = new Array(days).fill(0); // One slot per day, all starting at 0 hours.
  const first = Date.parse(`${start}T00:00:00Z`); // The first day of the period, as a number.
  for (const l of lines) { // Goes through each piece of work.
    const i = Math.round((Date.parse(`${l.work_date}T00:00:00Z`) - first) / 86400000); // Which day of the period it falls on (86,400,000 ms = 1 day).
    if (i >= 0 && i < days) units[i] += l.minutes / 60; // Adds its hours to that day, if inside the period.
  } // End of the loop over work.
  return units.map((u) => Math.round(u * 100) / 100); // Rounds each day to 2 decimal places.
} // End of dailyUnits.

// Sends draft timesheets for the pay period that includes this date.
export async function sendTimesheets(periodStart: string): Promise<{ sent: number; problems: string[] }> {
  const db = createAdminClient(); // Connects to the database with full access.
  const problems: string[] = []; // Plain messages about anyone who couldn't be sent.
  const { data: period } = await db.rpc("billing_pay_period", { p_day: periodStart }).single<{ period_start: string; period_end: string }>(); // Asks the database for the pay period's first and last day.
  if (!period) return { sent: 0, problems: ["Couldn't work out the pay period."] }; // Stops if it couldn't.
  const days = Math.round((Date.parse(period.period_end) - Date.parse(period.period_start)) / 86400000) + 1; // How many days the period covers.

  const { data: lines } = await db // Reads the pay lines waiting to be sent:
    .from("billing_pay_lines") // from the pay lines table,
    .select("id, account_id, staff_name, work_date, work_kind, minutes") // with who, when, what kind and how long,
    .eq("status", "pending") // only those not yet sent,
    .gte("work_date", period.period_start) // on or after the first day,
    .lte("work_date", period.period_end); // and on or before the last day.
  const people = new Map<string, NonNullable<typeof lines>>(); // Groups the lines by person.
  for (const l of lines ?? []) { // Goes through each line.
    if (!l.account_id) continue; // Skips lines not linked to a person.
    people.set(l.account_id, [...(people.get(l.account_id) ?? []), l]); // Adds it to that person's group.
  } // End of the grouping loop.
  if (people.size === 0) return { sent: 0, problems: [] }; // Nothing to send.

  const { data: pay } = await db // Reads each person's Xero links:
    .from("billing_staff_pay") // from the staff pay table,
    .select("account_id, xero_employee_id, xero_school_rate_id, xero_tertiary_rate_id, xero_admin_rate_id") // their Xero employee and rate ids,
    .in("account_id", [...people.keys()]); // for just the people with lines.
  const payOf = new Map((pay ?? []).map((p) => [p.account_id, p])); // Makes them quick to look up by person.

  let sent = 0; // Counts timesheets sent.
  for (const [accountId, own] of people) { // Goes through each person and their lines.
    const name = own[0].staff_name; // Their name, for messages.
    const p = payOf.get(accountId); // Their Xero links.
    if (!p?.xero_employee_id) { // Not linked to a Xero employee:
      problems.push(`${name}: not matched to a Xero employee yet.`); // notes the problem,
      continue; // and moves on to the next person.
    } // End of the employee check.
    const rateId: Record<string, string | null> = { // Which Xero rate each kind of work uses:
      school: p.xero_school_rate_id, // school tutoring rate,
      tertiary: p.xero_tertiary_rate_id, // tertiary tutoring rate,
      admin: p.xero_admin_rate_id, // office admin rate.
    }; // End of the rate list.
    const kinds = [...new Set(own.map((l) => l.work_kind))]; // The kinds of work this person did (no repeats).
    const missing = kinds.filter((k) => !rateId[k]); // Kinds with no rate chosen yet.
    if (missing.length) { // Some rate is missing:
      problems.push(`${name}: choose a Xero earnings rate for ${missing.join(" and ")} work.`); // notes which,
      continue; // and moves on.
    } // End of the rate check.
    try { // Sending to Xero could fail.
      const res = await xeroPayroll<{ Timesheets: { TimesheetID: string }[] }>( // Sends a timesheet to Xero:
        "POST", // creating something new,
        "Timesheets", // a timesheet,
        [ // with this content:
          { // One timesheet:
            EmployeeID: p.xero_employee_id, // for this employee,
            StartDate: period.period_start, // from the first day,
            EndDate: period.period_end, // to the last day,
            Status: "DRAFT", // as a draft for Carla to approve,
            TimesheetLines: kinds.map((k) => ({ // with one line per kind of work:
              EarningsRateID: rateId[k], // paid at that kind's rate,
              NumberOfUnits: dailyUnits(period.period_start, days, own.filter((l) => l.work_kind === k)), // with hours for each day.
            })), // End of the lines.
          }, // End of the timesheet.
        ], // End of the content.
        `timesheet-${accountId}-${period.period_start}`, // A unique key so a retry can't make a second copy.
      ); // End of the Xero request.
      const id = res.Timesheets?.[0]?.TimesheetID; // The new timesheet's id in Xero.
      if (!id) throw new Error("Xero didn't return a timesheet."); // No id means it didn't work.
      const { error } = await db.rpc("billing_mark_pay_sent", { p_lines: own.map((l) => l.id), p_timesheet: id }); // Marks these lines as sent.
      if (error) throw new Error(error.message); // Treats a save failure as a problem.
      sent++; // Counts this person as sent.
    } catch (e) { // Something went wrong for this person:
      problems.push(`${name}: ${(e as Error).message}`); // notes what.
    } // End of the error handling.
  } // End of the loop over people.
  return { sent, problems }; // Reports how many went and any problems.
} // End of sendTimesheets.
