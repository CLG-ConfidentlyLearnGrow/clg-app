// Summary: shared pieces for the owner's reports: the shape of a saved
// report's figures, plain names for each kind of report, and turning a
// report into a spreadsheet file (CSV) to download.
//
import { LEAVING_REASONS } from "@/app/admin/leaving-reasons"; // The plain words for each leaving reason.
import { dollars } from "@/lib/billing/money"; // Shows cents as dollars, e.g. "$95.50".
import { shortDate } from "@/lib/scheduling"; // Shows a date as e.g. "1 Mar 2025".

// The kinds of report: three made automatically, and one for any dates.
export type ReportKind = "monthly" | "quarterly" | "yearly" | "custom"; // (the four kinds)

// The plain name of each kind of report.
export const REPORT_KIND_LABELS: Record<ReportKind, string> = { // Each kind's words:
  monthly: "Monthly", // made on the 1st for the month before,
  quarterly: "Quarterly", // made after each quarter,
  yearly: "Financial year", // made each July for the year to 30 June,
  custom: "Your dates", // made by the owner for dates they chose.
}; // End of the names.

// One tutor's week, as saved in a report.
export type TutorWeek = { // A tutor's figures:
  name: string; // their name,
  max_hours: number | null; // most hours a week they want (if set),
  available_hours: number; // hours a week they're available,
  booked_now: number; // hours a week booked when the report was made,
  period_weekly: number; // average hours a week of sessions in the period,
  full_now_percent: number | null; // how full they are now (if a limit is known),
  full_period_percent: number | null; // how full they were in the period (if a limit is known),
  room_hours: number | null; // hours a week still free now.
}; // End of TutorWeek.

// School or tertiary money figures.
export type LevelMoney = { // One level's figures:
  kind: "school" | "tertiary"; // which level,
  hours: number; // hours billed,
  income_cents: number; // income before GST,
  wages_cents: number; // tutor wages plus super,
  profit_cents: number; // what's left after tutor wages,
  profit_per_hour_cents: number | null; // and that per hour (none if no hours).
}; // End of LevelMoney.

// Every figure in a saved report (the database works these out).
export type ReportFigures = { // The figures:
  from: string; // first day,
  to: string; // last day,
  days: number; // number of days,
  matching: { // students who got a tutor in the period:
    matched: number; // how many,
    average_days: number | null; // average days waited,
    median_days: number | null; // the middle wait,
    longest_days: number | null; // the longest wait,
    within_7_days: number; // matched within a week,
    within_14_days: number; // within two weeks,
    within_28_days: number; // within four weeks.
  }; // (end of matching)
  waiting_now: { // students waiting when the report was made:
    as_at: string; // the day counted,
    waiting: number; // how many,
    on_waitlist: number; // of those, on the waitlist,
    average_days: number | null; // average days waiting so far,
    longest_days: number | null; // longest wait so far.
  }; // (end of waiting now)
  enquiries: { // students added in the period:
    new_students: number; // how many,
    booked: number; // how many booked,
    still_waiting: number; // how many are still waiting,
    did_not_go_ahead: number; // how many stopped without booking,
    booked_percent: number | null; // share that booked,
    average_days_to_book: number | null; // average days from being added to booking.
  }; // (end of enquiries)
  tutors: TutorWeek[]; // each tutor's week,
  leaving: { // people who left in the period:
    families: number; // families,
    tutors: number; // tutors,
    families_happy: number; // families who left happy,
    reasons: { who: "family" | "tutor"; reason: string; count: number }[]; // each reason and how many.
  }; // (end of leaving)
  money: { // money in the period:
    super_percent: number; // super used,
    levels: LevelMoney[]; // school and tertiary,
    other_income_cents: number; // income not from sessions,
    income_cents: number; // all income,
    discounts_cents: number; // bank-debit discounts,
    tutor_wages_cents: number; // tutor wages plus super,
    admin_wages_cents: number; // admin wages plus super,
    other_costs_cents: number; // other costs from settings,
    other_costs_set: boolean; // whether other costs have been entered,
    tutoring_hours: number; // tutoring hours billed,
    profit_after_tutors_cents: number; // left after tutor wages,
    profit_after_all_cents: number; // left after all costs,
    profit_per_hour_after_tutors_cents: number | null; // per tutoring hour, after tutor wages,
    profit_per_hour_after_all_cents: number | null; // per tutoring hour, after all costs,
    sessions_without_pay: number; // sessions with no pay worked out yet,
    sessions_not_billed: number; // sessions not on an invoice yet.
  }; // (end of money)
}; // End of ReportFigures.

// A saved report, as read from the database.
export type SavedReport = { // A report:
  id: string; // its id,
  kind: ReportKind; // its kind,
  period_start: string; // first day,
  period_end: string; // last day,
  figures: ReportFigures; // its figures,
  made_at: string; // when it was made,
  read_at: string | null; // when the owner first opened it (none = new).
}; // End of SavedReport.

// The plain words for a leaving reason (or the code if it's unknown).
export function reasonLabel(code: string): string { // Takes the reason's code.
  return LEAVING_REASONS[code] ?? code; // Hands back its words.
} // End of reasonLabel.

// A number, or a dash when there's nothing to show.
export function num(value: number | null | undefined, suffix = ""): string { // Takes the number and any words after it.
  return value === null || value === undefined ? "–" : `${value}${suffix}`; // A dash for nothing, otherwise the number and words.
} // End of num.

// Money in cents as dollars, or a dash when there's nothing to show.
export function money(cents: number | null | undefined): string { // Takes the cents.
  return cents === null || cents === undefined ? "–" : dollars(cents); // A dash for nothing, otherwise dollars.
} // End of money.

// The period in plain words, e.g. "1 Mar 2025 to 31 Mar 2025".
export function periodLabel(r: { period_start: string; period_end: string }): string { // Takes the report's dates.
  return `${shortDate(r.period_start)} to ${shortDate(r.period_end)}`; // Both dates in short form.
} // End of periodLabel.

// Makes one cell safe for a CSV file: wraps it in quotes if it has a comma,
// quote or new line, and stops spreadsheet programs treating it as a formula.
function cell(value: string | number | null | undefined): string { // Takes the cell's value.
  let text = value === null || value === undefined ? "" : String(value); // Turns it into text (empty for nothing).
  if (/^[=+\-@]/.test(text) && !/^-?\d/.test(text)) text = `'${text}`; // Text starting like a formula (but not a negative number) gets a ' in front.
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text; // Quotes it if needed, doubling any quotes inside.
} // End of cell.

// Turns a report into CSV text: one line per figure, grouped by section,
// so it opens neatly in Excel or Google Sheets.
export function reportCsv(r: SavedReport): string { // Takes the report.
  const f = r.figures; // Its figures.
  const rows: (string | number | null)[][] = []; // The lines, each a list of cells.
  const add = (...cells: (string | number | null)[]) => rows.push(cells); // Adds one line.
  const d = (cents: number | null) => (cents === null ? null : (cents / 100).toFixed(2)); // Cents as plain dollars for a spreadsheet, e.g. 95.50.
  add("CLG report", REPORT_KIND_LABELS[r.kind]); // Title and kind.
  add("From", f.from); // First day.
  add("To", f.to); // Last day.
  add("Made", r.made_at.slice(0, 10)); // The day it was made.
  add(); // A blank line.
  add("Matching", "Figure", "Value"); // Matching heading.
  add("Matching", "Students matched with a tutor", f.matching.matched); // How many matched.
  add("Matching", "Average days waited", f.matching.average_days); // Average wait.
  add("Matching", "Middle (median) days waited", f.matching.median_days); // Middle wait.
  add("Matching", "Longest days waited", f.matching.longest_days); // Longest wait.
  add("Matching", "Matched within 7 days", f.matching.within_7_days); // Within a week.
  add("Matching", "Matched within 14 days", f.matching.within_14_days); // Within two weeks.
  add("Matching", "Matched within 28 days", f.matching.within_28_days); // Within four weeks.
  add("Waiting now", `Waiting on ${f.waiting_now.as_at}`, f.waiting_now.waiting); // Waiting now.
  add("Waiting now", "Of those, on the waitlist", f.waiting_now.on_waitlist); // On the waitlist.
  add("Waiting now", "Average days waiting so far", f.waiting_now.average_days); // Average days so far.
  add("Waiting now", "Longest days waiting so far", f.waiting_now.longest_days); // Longest so far.
  add(); // A blank line.
  add("Enquiries", "New students added", f.enquiries.new_students); // New students.
  add("Enquiries", "Booked", f.enquiries.booked); // Booked.
  add("Enquiries", "Still waiting", f.enquiries.still_waiting); // Still waiting.
  add("Enquiries", "Did not go ahead", f.enquiries.did_not_go_ahead); // Didn't go ahead.
  add("Enquiries", "Booked (%)", f.enquiries.booked_percent); // Share booked.
  add("Enquiries", "Average days from added to booked", f.enquiries.average_days_to_book); // Days to book.
  add(); // A blank line.
  add("Tutor weeks", "Tutor", "Most hours wanted", "Hours available", "Hours booked now", "Full now (%)", "Average hours a week in period", "Full in period (%)", "Hours free now"); // Tutor heading.
  for (const t of f.tutors) add("Tutor weeks", t.name, t.max_hours, t.available_hours, t.booked_now, t.full_now_percent, t.period_weekly, t.full_period_percent, t.room_hours); // One line per tutor.
  add(); // A blank line.
  add("Leaving", "Families who left", f.leaving.families); // Families who left.
  add("Leaving", "Of those, left happy", f.leaving.families_happy); // Left happy.
  add("Leaving", "Tutors who left", f.leaving.tutors); // Tutors who left.
  for (const x of f.leaving.reasons) add("Leaving", `${x.who === "tutor" ? "Tutor" : "Family"}: ${reasonLabel(x.reason)}`, x.count); // One line per reason.
  add(); // A blank line.
  add("Money", "Level", "Hours billed", "Income ($)", "Tutor wages + super ($)", "Profit after tutor wages ($)", "Profit per hour ($)"); // Money heading.
  for (const l of f.money.levels) add("Money", l.kind === "school" ? "School" : "Tertiary", l.hours, d(l.income_cents), d(l.wages_cents), d(l.profit_cents), d(l.profit_per_hour_cents)); // One line per level.
  add("Money", "Other income ($)", d(f.money.other_income_cents)); // Other income.
  add("Money", "All income ($)", d(f.money.income_cents)); // All income.
  add("Money", "Bank-debit discounts ($)", d(f.money.discounts_cents)); // Discounts.
  add("Money", "Tutor wages + super ($)", d(f.money.tutor_wages_cents)); // Tutor wages.
  add("Money", "Admin wages + super ($)", d(f.money.admin_wages_cents)); // Admin wages.
  add("Money", "Other costs ($)", d(f.money.other_costs_cents)); // Other costs.
  add("Money", "Profit after tutor wages ($)", d(f.money.profit_after_tutors_cents)); // Profit after tutors.
  add("Money", "Profit after all costs ($)", d(f.money.profit_after_all_cents)); // Profit after all.
  add("Money", "Profit per tutoring hour after tutor wages ($)", d(f.money.profit_per_hour_after_tutors_cents)); // Per hour after tutors.
  add("Money", "Profit per tutoring hour after all costs ($)", d(f.money.profit_per_hour_after_all_cents)); // Per hour after all.
  add("Money", "Super used (%)", f.money.super_percent); // Super used.
  add("Money", "Sessions with no pay worked out yet", f.money.sessions_without_pay); // Missing pay.
  add("Money", "Sessions not on an invoice yet", f.money.sessions_not_billed); // Missing invoices.
  return rows.map((row) => row.map(cell).join(",")).join("\r\n") + "\r\n"; // Joins cells with commas and lines with Windows line endings (Excel likes these).
} // End of reportCsv.

// ---------------------------------------------------------------------------
// Goals (Carla, 20 Nov 2026): the owner sets a target for a quarter or a
// financial year, and the owner and Operations admins check how it is going
// each month. Goals only use figures without money, so Operations admins can
// see them.
// ---------------------------------------------------------------------------

// A report's figures with the money part left out (what Operations admins get).
export type FiguresNoMoney = Omit<ReportFigures, "money"> & { money?: ReportFigures["money"] }; // Every figure, with money only there for the owner.

// The two kinds of goal period.
export type GoalKind = "quarterly" | "yearly"; // a quarter, or a financial year (1 July to 30 June).

// One goal, as saved in the database.
export type ReportGoal = { // A goal:
  id: string; // its id,
  kind: GoalKind; // a quarter or a financial year,
  period_start: string; // the period's first day,
  metric: GoalMetricId; // which figure,
  target: number; // the target number,
  note: string | null; // why, or how it will be reached (optional).
}; // End of ReportGoal.

// Each figure a goal can be set on.
export const GOAL_METRICS = [ // The figures, in the order they are shown:
  { id: "matched", label: "Students matched with a tutor", unit: "", better: "up", grows: true, value: (f: FiguresNoMoney) => f.matching.matched }, // matched (more is better, adds up over the period),
  { id: "matched_within_14_days", label: "Students matched within 2 weeks", unit: "", better: "up", grows: true, value: (f: FiguresNoMoney) => f.matching.within_14_days }, // matched quickly (more is better, adds up),
  { id: "average_wait_days", label: "Average wait for a tutor", unit: " days", better: "down", grows: false, value: (f: FiguresNoMoney) => f.matching.average_days }, // average wait (fewer days is better),
  { id: "new_students", label: "New students added", unit: "", better: "up", grows: true, value: (f: FiguresNoMoney) => f.enquiries.new_students }, // new students (more is better, adds up),
  { id: "booked", label: "New students who booked", unit: "", better: "up", grows: true, value: (f: FiguresNoMoney) => f.enquiries.booked }, // booked (more is better, adds up),
  { id: "booked_percent", label: "Share of new students who booked", unit: "%", better: "up", grows: false, value: (f: FiguresNoMoney) => f.enquiries.booked_percent }, // share booked (higher is better),
  { id: "families_left", label: "Families who left", unit: "", better: "down", grows: true, value: (f: FiguresNoMoney) => f.leaving.families }, // families who left (fewer is better, adds up),
  { id: "waiting_now", label: "Students still waiting at the end", unit: "", better: "down", grows: false, value: (f: FiguresNoMoney) => f.waiting_now.waiting }, // still waiting (fewer is better).
] as const; // End of the figures (fixed).

// The id of a figure a goal can be set on.
export type GoalMetricId = (typeof GOAL_METRICS)[number]["id"]; // one of the ids above.

// Finds a figure's details by its id.
export function goalMetric(id: string) { // Takes the figure's id.
  return GOAL_METRICS.find((m) => m.id === id); // Hands back its details (or nothing if unknown).
} // End of goalMetric.

// The words for a goal's target, e.g. "at least 20" or "10 days or fewer".
export function goalTargetWords(id: string, target: number): string { // Takes the figure's id and the target.
  const m = goalMetric(id); // The figure's details.
  if (!m) return String(target); // Unknown figure: just the number.
  return m.better === "up" ? `at least ${target}${m.unit}` : `${target}${m.unit} or fewer`; // "at least" when more is better, "or fewer" when fewer is better.
} // End of goalTargetWords.

// Whether a finished period met its goal: true, false, or null if there is no figure.
export function goalMet(id: string, target: number, f: FiguresNoMoney): boolean | null { // Takes the figure's id, the target and the period's figures.
  const m = goalMetric(id); // The figure's details.
  const v = m?.value(f); // The period's figure.
  if (!m || v === null || v === undefined) return null; // No figure (for example no one matched, so no average wait): cannot say.
  return m.better === "up" ? v >= target : v <= target; // Met if at or above (more is better) or at or below (fewer is better).
} // End of goalMet.

// How a goal is going part-way through its period. Figures that add up over
// the period (like students matched) are compared with the share of the
// target expected by now; the others are compared with the target itself.
export function goalProgress(id: string, target: number, f: FiguresNoMoney, elapsedDays: number, totalDays: number): { value: number | null; expected: number; onTrack: boolean | null } { // Takes the figure's id, target, figures so far, and days gone and in total.
  const m = goalMetric(id); // The figure's details.
  const v = m?.value(f) ?? null; // The figure so far.
  const share = totalDays > 0 ? Math.min(1, elapsedDays / totalDays) : 1; // How far through the period it is (0 to 1).
  const expected = m?.grows ? Math.round(target * share * 10) / 10 : target; // What it should be by now (part of the target for figures that add up).
  if (!m || v === null) return { value: v, expected, onTrack: null }; // No figure yet: cannot say.
  return { value: v, expected, onTrack: m.better === "up" ? v >= expected : v <= expected }; // On track if at or past what is expected by now.
} // End of goalProgress.

// The first day of the quarter a date falls in (1 Jan, 1 Apr, 1 Jul or 1 Oct).
export function quarterStart(day: string): string { // Takes a date (YYYY-MM-DD).
  const [y, m] = day.split("-").map(Number); // The year and month.
  const q = Math.floor((m - 1) / 3) * 3 + 1; // The quarter's first month.
  return `${y}-${String(q).padStart(2, "0")}-01`; // The 1st of that month.
} // End of quarterStart.

// The first day of the financial year a date falls in (1 July).
export function yearStart(day: string): string { // Takes a date (YYYY-MM-DD).
  const [y, m] = day.split("-").map(Number); // The year and month.
  return `${m >= 7 ? y : y - 1}-07-01`; // 1 July this year from July, otherwise last year.
} // End of yearStart.

// The words for a goal period, e.g. "Jan to Mar 2027" or "2026 to 2027 financial year".
export function goalPeriodLabel(kind: GoalKind, start: string): string { // Takes the kind and first day.
  const [y, m] = start.split("-").map(Number); // The year and month it starts.
  if (kind === "yearly") return `${y} to ${y + 1} financial year`; // A financial year.
  const names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]; // Short month names.
  return `${names[m - 1]} to ${names[m + 1]} ${y}`; // A quarter, e.g. "Jan to Mar 2027".
} // End of goalPeriodLabel.
