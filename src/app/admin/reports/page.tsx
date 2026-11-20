// Summary: the Reports page: the monthly, quarterly and yearly reports the
// app makes by itself, reports for any dates, the settings used for profit
// (super and other costs), and quarterly and yearly goals.
// The owner sees everything. Operations admins (Carla, 20 Nov 2026, for
// Emma's role) see every report without the money part, and the goals; the
// database takes the money out before it reaches them.
//
import type { ReactNode } from "react"; // The type for anything React can show.
import { deleteReport, removeGoal } from "@/app/actions/reports"; // The actions that delete a report made for chosen dates and remove a goal.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { BackButton, BusyButton, Card, Empty, SubHeading, Table, TextLink } from "@/components/ui"; // Shared page parts: back button, button that shows a spinner while saving, card, empty line, small heading, table and text link.
import { requireAdminLevel } from "@/lib/auth"; // Makes sure the person is an admin at the right level.
import { addDays, localToday, shortDate } from "@/lib/scheduling"; // Date helpers.
import { REPORT_KIND_LABELS, goalMet, goalMetric, goalPeriodLabel, goalProgress, goalTargetWords, money, num, periodLabel, quarterStart, reasonLabel, yearStart, type FiguresNoMoney, type GoalKind, type ReportGoal, type SavedReport } from "@/lib/reports"; // Report names, number and money display, goal helpers, and the report types.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { GoalForm, MakeReportForm, ReportSettingsForm } from "./forms"; // The forms on this page.
import { REPORTS_TABS } from "@/lib/menu-sub-tabs"; // This page's sub-tabs (shared with the side menu, Carla 20 Nov 2026).

// The page's sections.
const SECTIONS = REPORTS_TABS; // This page's sub-tabs, from the shared list the side menu also uses (so the menu can show them from any page).
const OPERATIONS_SECTIONS = ["reports", "goals"]; // The sections Operations admins can open (no making reports or settings).

// A report as this page reads it: the money part is only there for the owner.
type ViewReport = Omit<SavedReport, "figures"> & { figures: FiguresNoMoney; has_money: boolean }; // The report, plus whether money is included.

// How a goal is going or turned out, as a small coloured label.
function GoalStatus({ ok, during }: { ok: boolean | null; during: boolean }) { // Takes good (true), not (false) or unknown (null), and whether the period is still going.
  if (ok === null) return <span className="text-sm text-zinc-500">No figure yet</span>; // Unknown: grey words.
  return ok // Known:
    ? <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-800">{during ? "On track" : "Met"}</span> // green when on track or met,
    : <span className="rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-900">{during ? "Behind" : "Not met"}</span>; // amber when behind or not met.
} // End of GoalStatus.

// The common ranges offered as one-tap buttons, worked out from today.
function quickRanges(today: string) { // Takes today's date (YYYY-MM-DD).
  const [y, m] = today.split("-").map(Number); // This year and month as numbers.
  const pad = (n: number) => String(n).padStart(2, "0"); // Puts a 0 in front of single digits.
  const monthStart = `${y}-${pad(m)}-01`; // The 1st of this month.
  const lastMonthEnd = addDays(monthStart, -1); // The last day of last month.
  const lastMonthStart = `${lastMonthEnd.slice(0, 7)}-01`; // The 1st of last month.
  const qMonth = Math.floor((m - 1) / 3) * 3 + 1; // The first month of this quarter.
  const fyYear = m >= 7 ? y : y - 1; // The year this financial year started (it starts 1 July).
  return [ // Hands back:
    { label: "This month so far", from: monthStart, to: today }, // this month so far,
    { label: "Last month", from: lastMonthStart, to: lastMonthEnd }, // last month,
    { label: "This quarter so far", from: `${y}-${pad(qMonth)}-01`, to: today }, // this quarter so far,
    { label: "Last 12 months", from: addDays(today, -364), to: today }, // the last 12 months,
    { label: "This financial year so far", from: `${fyYear}-07-01`, to: today }, // this financial year so far,
    { label: "Last financial year", from: `${fyYear - 1}-07-01`, to: `${fyYear}-06-30` }, // last financial year.
  ]; // End of the ranges.
} // End of quickRanges.

// One big number with a label, for the top of each part of a report.
function Stat({ label, value, note }: { label: string; value: string; note?: string }) {
  return ( // Shows:
    <div className="rounded-xl bg-zinc-50 px-4 py-3">{/* a pale box: */}
      <p className="text-xs text-zinc-600">{label}</p>{/* the label, small, */}
      <p className="mt-1 text-xl font-semibold tabular-nums">{value}</p>{/* the number, large, */}
      {note && <p className="mt-0.5 text-xs text-zinc-500">{note}</p>}{/* and a note under it, if any. */}
    </div> // End of the box.
  ); // End of what's shown.
} // End of Stat.

// A row of big numbers that wraps on small screens.
function Stats({ children }: { children: ReactNode }) {
  return <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">{children}</div>; // Two across on phones, four on wider screens.
} // End of Stats.

// Shows one report in full. The money card and the spreadsheet download are
// only for the owner; goals show on quarterly and yearly reports.
function ReportView({ report, goals, isOwner }: { report: ViewReport; goals: ReportGoal[]; isOwner: boolean }) { // Takes the report, its period's goals, and whether the viewer is the owner.
  const f = report.figures; // The report's figures.
  const m = report.has_money ? f.money : undefined; // The money figures (owner only).
  const hasGoals = report.kind === "quarterly" || report.kind === "yearly"; // Whether this kind of report has goals.
  return ( // Shows:
    <>{/* (a group:) */}
      <p><BackButton href="/admin/reports">Back to all reports</BackButton></p>{/* a button back to the list, */}
      <Card // a card for the report's heading:
        title={`${REPORT_KIND_LABELS[report.kind]} report: ${periodLabel(report)}`} // the kind and dates,
        description={`Made ${shortDate(report.made_at)}. Figures are saved as they were on that day.`} // when it was made.
      >{/* (end of the card's settings) */}
        {isOwner && ( // Only the owner can download (the file includes money):
          <div className="flex flex-wrap gap-3">{/* a row of buttons: */}
            <a href={`/admin/reports/csv?id=${report.id}`} className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white">{/* download as a spreadsheet, */}
              Download spreadsheet (CSV){/* (its words) */}
            </a>{/* (end of the link) */}
          </div> // End of the row.
        )}{/* End of the download. */}
        {!isOwner && <p className="text-sm text-zinc-600">Money (income, wages and profit) is only shown to the owner.</p>}{/* Operations: a note that money is left out. */}
        {report.kind === "monthly" && <p className="mt-2 text-sm text-zinc-600">For the monthly check-in, see how this quarter and year are going under <TextLink href="/admin/reports?section=goals">Goals</TextLink>.</p>}{/* Monthly reports: a link to the goals. */}
      </Card>{/* End of the heading card. */}

      {hasGoals && ( // Quarterly and yearly reports: were the goals met?
        <Card title="Goals" description="The goals set for this period, and whether each was met.">{/* the goals card: */}
          {goals.length === 0 ? ( // No goals were set:
            <Empty>No goals were set for this period. Goals can be set under Reports, Goals.</Empty> // says so.
          ) : ( // Otherwise:
            <Table headings={["Figure", "Goal", "Result", ""]}>{/* a table: */}
              {goals.map((g) => { // for each goal:
                const metric = goalMetric(g.metric); // the figure's details,
                const value = metric?.value(f) ?? null; // the period's figure,
                return ( // shows:
                  <tr key={g.id}>{/* a row: */}
                    <td>{metric?.label ?? g.metric}</td>{/* the figure's name, */}
                    <td>{goalTargetWords(g.metric, Number(g.target))}</td>{/* the goal, */}
                    <td className="tabular-nums">{num(value, metric?.unit ?? "")}</td>{/* the result, */}
                    <td><GoalStatus ok={goalMet(g.metric, Number(g.target), f)} during={false} /></td>{/* and met or not met. */}
                  </tr> // End of the row.
                ); // End of what is shown.
              })}{/* End of the goals loop. */}
            </Table> // End of the table.
          )}{/* End of the choice. */}
        </Card> // End of the goals card.
      )}{/* End of the goals. */}

      <Card title="Matching" description="How long students waited for a tutor. A wait starts when a subject is asked for, or when their last tutor finished.">{/* The matching card: */}
        <Stats>{/* big numbers: */}
          <Stat label="Matched with a tutor" value={num(f.matching.matched)} />{/* how many matched, */}
          <Stat label="Average wait" value={num(f.matching.average_days, " days")} note={`Middle wait ${num(f.matching.median_days, " days")}`} />{/* average and middle wait, */}
          <Stat label="Longest wait" value={num(f.matching.longest_days, " days")} />{/* longest wait, */}
          <Stat label="Matched within 2 weeks" value={num(f.matching.within_14_days)} note={`${num(f.matching.within_7_days)} within 1 week, ${num(f.matching.within_28_days)} within 4`} />{/* within two weeks. */}
        </Stats>{/* End of the numbers. */}
        <SubHeading>Waiting on {shortDate(f.waiting_now.as_at)} (the day this report was made)</SubHeading>{/* A heading for who is waiting now. */}
        <Stats>{/* big numbers: */}
          <Stat label="Still waiting" value={num(f.waiting_now.waiting)} note={`${num(f.waiting_now.on_waitlist)} on the waitlist`} />{/* how many are waiting, */}
          <Stat label="Average wait so far" value={num(f.waiting_now.average_days, " days")} />{/* average so far, */}
          <Stat label="Longest wait so far" value={num(f.waiting_now.longest_days, " days")} />{/* longest so far. */}
        </Stats>{/* End of the numbers. */}
      </Card>{/* End of the matching card. */}

      <Card title="Enquiries" description="Students added in this period, and whether they went on to book a tutor.">{/* The enquiries card: */}
        <Stats>{/* big numbers: */}
          <Stat label="New students" value={num(f.enquiries.new_students)} />{/* new students, */}
          <Stat label="Booked" value={num(f.enquiries.booked)} note={f.enquiries.booked_percent === null ? undefined : `${f.enquiries.booked_percent}% of new students`} />{/* booked, with the share, */}
          <Stat label="Still waiting" value={num(f.enquiries.still_waiting)} />{/* still waiting, */}
          <Stat label="Did not go ahead" value={num(f.enquiries.did_not_go_ahead)} />{/* didn't go ahead. */}
        </Stats>{/* End of the numbers. */}
        <p className="mt-3 text-sm text-zinc-600">Average time from being added to booking: {num(f.enquiries.average_days_to_book, " days")}.</p>{/* Average days to book. */}
      </Card>{/* End of the enquiries card. */}

      <Card title="How full each tutor's week is" description="Compared with the most hours each tutor wants a week (or the hours they are available, if no limit is set). Fullest first.">{/* The tutor weeks card: */}
        {f.tutors.length === 0 ? ( // No tutors:
          <Empty>No tutors yet.</Empty> // says so.
        ) : ( // Otherwise:
          <Table headings={["Tutor", "Booked now", "Full now", "Hours free", "Average in period", "Full in period"]}>{/* a table: */}
            {f.tutors.map((t) => ( // for each tutor:
              <tr key={t.name}>{/* a row: */}
                <td>{t.name}</td>{/* their name, */}
                <td className="tabular-nums">{/* hours booked now, out of their limit: */}
                  {t.booked_now} h{t.max_hours !== null ? ` of ${t.max_hours} h` : t.available_hours > 0 ? ` of ${t.available_hours} h available` : ""}{/* (e.g. "6 h of 10 h") */}
                </td>{/* (end of the cell) */}
                <td className="tabular-nums">{num(t.full_now_percent, "%")}</td>{/* how full now, */}
                <td className="tabular-nums">{num(t.room_hours, " h")}</td>{/* hours still free, */}
                <td className="tabular-nums">{t.period_weekly} h a week</td>{/* average in the period, */}
                <td className="tabular-nums">{num(t.full_period_percent, "%")}</td>{/* how full in the period. */}
              </tr> // End of the row.
            ))}{/* End of the tutors loop. */}
          </Table> // End of the table.
        )}{/* End of the choice. */}
      </Card>{/* End of the tutor weeks card. */}

      <Card title="Why people left" description="Families and tutors recorded as leaving in this period (Admin, Leaving).">{/* The leaving card: */}
        <Stats>{/* big numbers: */}
          <Stat label="Families left" value={num(f.leaving.families)} note={`${num(f.leaving.families_happy)} left happy`} />{/* families who left, */}
          <Stat label="Tutors left" value={num(f.leaving.tutors)} />{/* tutors who left. */}
        </Stats>{/* End of the numbers. */}
        {f.leaving.reasons.length > 0 && ( // If any reasons:
          <div className="mt-4">{/* a block with space above: */}
            <Table headings={["Who", "Reason", "How many"]}>{/* a table: */}
              {f.leaving.reasons.map((x) => ( // for each reason:
                <tr key={`${x.who}-${x.reason}`}>{/* a row: */}
                  <td>{x.who === "tutor" ? "Tutor" : "Family"}</td>{/* family or tutor, */}
                  <td>{reasonLabel(x.reason)}</td>{/* the reason, */}
                  <td className="tabular-nums">{x.count}</td>{/* how many. */}
                </tr> // End of the row.
              ))}{/* End of the reasons loop. */}
            </Table>{/* End of the table. */}
          </div> // End of the block.
        )}{/* End of the reasons. */}
      </Card>{/* End of the leaving card. */}

      {m && ( // Only the owner gets the money part:
      <Card title="Money and profit per hour" description={`Income is invoiced sessions in this period (before GST, cancelled invoices left out). Wages include ${m.super_percent}% super.`}>{/* The money card: */}
        <Stats>{/* big numbers: */}
          <Stat label="Profit per tutoring hour" value={money(m.profit_per_hour_after_tutors_cents)} note="After tutor wages" />{/* per hour after tutors, */}
          <Stat label="Profit per tutoring hour" value={money(m.profit_per_hour_after_all_cents)} note={m.other_costs_set ? "After all costs" : "After all wages (other costs not set)"} />{/* per hour after all costs, */}
          <Stat label="Income" value={money(m.income_cents)} note={`${m.tutoring_hours} tutoring hours`} />{/* income and hours, */}
          <Stat label="Profit after all costs" value={money(m.profit_after_all_cents)} />{/* profit after all costs. */}
        </Stats>{/* End of the numbers. */}
        <div className="mt-4">{/* A block with space above: */}
          <Table headings={["Level", "Hours", "Income", "Tutor wages + super", "Profit", "Per hour"]}>{/* a table by level: */}
            {m.levels.map((l) => ( // for school and tertiary:
              <tr key={l.kind}>{/* a row: */}
                <td>{l.kind === "school" ? "School" : "Tertiary"}</td>{/* the level, */}
                <td className="tabular-nums">{l.hours}</td>{/* hours, */}
                <td className="tabular-nums">{money(l.income_cents)}</td>{/* income, */}
                <td className="tabular-nums">{money(l.wages_cents)}</td>{/* wages, */}
                <td className="tabular-nums">{money(l.profit_cents)}</td>{/* profit, */}
                <td className="tabular-nums">{money(l.profit_per_hour_cents)}</td>{/* per hour. */}
              </tr> // End of the row.
            ))}{/* End of the levels loop. */}
          </Table>{/* End of the table. */}
        </div>{/* End of the block. */}
        <dl className="mt-4 grid grid-cols-1 gap-x-6 gap-y-1 text-sm sm:grid-cols-2">{/* The full breakdown, two columns on wider screens: */}
          <div className="flex justify-between"><dt>Other income (not sessions)</dt><dd className="tabular-nums">{money(m.other_income_cents)}</dd></div>{/* other income, */}
          <div className="flex justify-between"><dt>Bank-debit discounts</dt><dd className="tabular-nums">−{money(m.discounts_cents)}</dd></div>{/* discounts, */}
          <div className="flex justify-between"><dt>Tutor wages + super</dt><dd className="tabular-nums">−{money(m.tutor_wages_cents)}</dd></div>{/* tutor wages, */}
          <div className="flex justify-between"><dt>Admin wages + super</dt><dd className="tabular-nums">−{money(m.admin_wages_cents)}</dd></div>{/* admin wages, */}
          <div className="flex justify-between"><dt>Other costs</dt><dd className="tabular-nums">−{money(m.other_costs_cents)}</dd></div>{/* other costs, */}
          <div className="flex justify-between font-medium"><dt>Profit after tutor wages</dt><dd className="tabular-nums">{money(m.profit_after_tutors_cents)}</dd></div>{/* profit after tutors. */}
        </dl>{/* End of the breakdown. */}
        {(m.sessions_without_pay > 0 || m.sessions_not_billed > 0 || !m.other_costs_set) && ( // If anything could make these figures off:
          <ul className="mt-4 list-disc space-y-1 rounded-xl bg-amber-50 py-3 pr-4 pl-8 text-sm text-amber-900">{/* a pale amber note listing: */}
            {m.sessions_without_pay > 0 && <li>{m.sessions_without_pay} sessions have no pay worked out yet, so wages are missing and profit looks higher than it is.</li>}{/* sessions with no pay, */}
            {m.sessions_not_billed > 0 && <li>{m.sessions_not_billed} sessions are not on an invoice yet, so income is missing and profit looks lower than it is.</li>}{/* sessions not billed, */}
            {!m.other_costs_set && <li>Other running costs are not set (Reports, Settings), so &ldquo;after all costs&rdquo; only takes off wages.</li>}{/* other costs not set. */}
          </ul> // End of the note.
        )}{/* End of the note. */}
      </Card> // End of the money card.
      )}{/* End of the owner-only money part. */}
      <p><BackButton href="/admin/reports">Back to all reports</BackButton></p>{/* The same back button at the bottom, so it's there after scrolling down. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of ReportView.

// Shows the Reports page (the owner, and Operations admins without money).
export default async function ReportsPage({ searchParams }: PageProps<"/admin/reports">) {
  const viewer = await requireAdminLevel(["owner", "operations"]); // Must be the owner or an Operations admin (Carla, 20 Nov 2026).
  const isOwner = viewer.level === "owner"; // Whether this is the owner (money, making reports and settings are theirs only).
  const params = await searchParams; // Reads the address settings.
  const supabase = await createClient(); // Connects to the database.
  const id = typeof params.id === "string" ? params.id : null; // The report to open, if any.
  const asked = SECTIONS.find((s) => s.id === params.section)?.id ?? "reports"; // The section asked for (the list by default).
  const section = id ? "reports" : isOwner || OPERATIONS_SECTIONS.includes(asked) ? asked : "reports"; // Operations asking for an owner-only section gets the list instead.
  const sections = isOwner ? SECTIONS : SECTIONS.filter((s) => OPERATIONS_SECTIONS.includes(s.id)); // The sub-tabs this person sees.
  const today = localToday(); // Today's date.

  let report: ViewReport | null = null; // The open report, if any.
  let reportGoals: ReportGoal[] = []; // The goals for the open report's period, if any.
  if (id && /^[0-9a-f-]{36}$/.test(id)) { // A report id that looks right:
    const { data } = await supabase.rpc("report_get", { p_id: id }); // reads it (the database leaves out money for Operations),
    report = ((data as ViewReport[] | null) ?? [])[0] ?? null; // keeps it (or nothing if not found),
    if (report && isOwner && !report.read_at) await supabase.rpc("report_mark_read", { p_id: report.id }); // marks it read the first time the owner opens it,
    if (report && (report.kind === "quarterly" || report.kind === "yearly")) { // and for a quarterly or yearly report:
      const { data: g } = await supabase.from("report_goals").select("id, kind, period_start, metric, target, note").eq("kind", report.kind).eq("period_start", report.period_start).order("metric"); // reads that period's goals.
      reportGoals = (g ?? []) as ReportGoal[]; // Keeps them.
    } // End of the goals.
  } // End of reading the report.

  // The goal periods shown: this quarter and this financial year, plus the
  // next of each so goals can be set ahead.
  const thisQuarter = quarterStart(today); // This quarter's first day.
  const nextQuarter = quarterStart(addDays(thisQuarter, 95)); // Next quarter's first day (95 days on is always in the next quarter).
  const thisYear = yearStart(today); // This financial year's first day.
  const nextYear = `${Number(thisYear.slice(0, 4)) + 1}-07-01`; // Next financial year's first day.
  const goalPeriods: { kind: GoalKind; start: string }[] = [ // The periods, in order:
    { kind: "quarterly", start: thisQuarter }, // this quarter,
    { kind: "yearly", start: thisYear }, // this financial year,
    { kind: "quarterly", start: nextQuarter }, // next quarter,
    { kind: "yearly", start: nextYear }, // next financial year.
  ]; // End of the periods.

  const [listRes, settingsRes, goalsRes, quarterRes, yearRes] = await Promise.all([ // Reads these at once:
    section === "reports" && !report ? supabase.rpc("report_list") : Promise.resolve({ data: [] }), // on the list: the newest 200 reports,
    isOwner ? supabase.from("report_settings").select("super_percent, monthly_other_costs_cents").maybeSingle() : Promise.resolve({ data: null }), // the settings (owner only),
    section === "goals" ? supabase.from("report_goals").select("id, kind, period_start, metric, target, note").gte("period_start", thisYear).order("metric") : Promise.resolve({ data: [] }), // on Goals: the goals from this financial year on,
    section === "goals" ? supabase.rpc("report_goal_progress", { p_kind: "quarterly", p_period_start: thisQuarter }) : Promise.resolve({ data: null }), // how this quarter is going,
    section === "goals" ? supabase.rpc("report_goal_progress", { p_kind: "yearly", p_period_start: thisYear }) : Promise.resolve({ data: null }), // and how this financial year is going.
  ]); // End of the reads.
  const list = (listRes.data ?? []) as Omit<SavedReport, "figures">[]; // The reports listed.
  const unread = isOwner ? list.filter((r) => !r.read_at).length : 0; // How many are new (the owner's marker only).
  const settings = settingsRes.data as { super_percent: number; monthly_other_costs_cents: number } | null; // The settings.
  const allGoals = (goalsRes.data ?? []) as ReportGoal[]; // Every goal from this financial year on.
  type Progress = FiguresNoMoney & { elapsed_days: number; total_days: number; period_end: string }; // How a period is going: its figures so far and how far through it is.
  const progress: Record<string, Progress | null> = { [`quarterly:${thisQuarter}`]: quarterRes.data as Progress | null, [`yearly:${thisYear}`]: yearRes.data as Progress | null }; // The figures so far for this quarter and year.

  return ( // Shows:
    <DashboardFrame // the dashboard frame:
      role="admin" // the admin dashboard,
      roles={viewer.roles} // the person's roles (for the tabs and numbers),
      current="reports" // this page's tab open,
      sub={section} // on the open section,
      items={sections.map((s) => ({ ...s, href: `/admin/reports?section=${s.id}`, count: s.id === "reports" ? unread || undefined : undefined }))} // with this person's sections under the tab.
    >{/* (end of the frame's settings) */}
      {report ? ( // A report is open:
        <ReportView report={report} goals={reportGoals} isOwner={isOwner} /> // shows it.
      ) : id ? ( // An id was given but no report found:
        <Card title="Report not found">{/* a card saying so: */}
          <p className="text-sm">It may have been deleted. <TextLink href="/admin/reports">Back to all reports</TextLink></p>{/* with a link back. */}
        </Card> // End of the card.
      ) : section === "reports" ? ( // The list:
        <Card // a card:
          title="All reports" // titled "All reports",
          description="The app makes a monthly report on the 1st, a quarterly report after each quarter, and a financial year report each July. You will see a number on Reports when a new one is ready." // explaining when reports are made.
        >{/* (end of the card's settings) */}
          {list.length === 0 ? ( // No reports yet:
            <Empty>No reports yet. The first monthly report (November 2026) arrives on 1 December. You can make one for any dates now under &ldquo;Report for your dates&rdquo;.</Empty> // says when the first arrives.
          ) : ( // Otherwise:
            <Table headings={["Report", "Covers", "Made", ""]}>{/* a table: */}
              {list.map((r) => ( // for each report:
                <tr key={r.id}>{/* a row: */}
                  <td>{/* the kind, with "New" if not opened yet: */}
                    {REPORT_KIND_LABELS[r.kind]}{/* the kind, */}
                    {isOwner && !r.read_at && <span className="ml-2 rounded-full bg-brand px-2 py-0.5 text-xs text-white">New</span>}{/* and a "New" label if unread. */}
                  </td>{/* (end of the cell) */}
                  <td>{periodLabel(r)}</td>{/* the dates, */}
                  <td>{shortDate(r.made_at)}</td>{/* when it was made, */}
                  <td className="text-right">{/* the actions: */}
                    <div className="flex items-center justify-end gap-3">{/* side by side: */}
                      <TextLink href={`/admin/reports?id=${r.id}`}>Open</TextLink>{/* open it, */}
                      {isOwner && r.kind === "custom" && ( // the owner can delete reports for chosen dates:
                        <form action={deleteReport}>{/* a delete form: */}
                          <input type="hidden" name="id" value={r.id} />{/* the report's id, hidden, */}
                          <BusyButton type="submit" className="text-sm text-red-700 hover:underline">Delete</BusyButton>{/* and the delete button (shows a spinner and cannot be pressed twice while deleting). */}
                        </form> // End of the form.
                      )}{/* End of delete. */}
                    </div>{/* End of the actions. */}
                  </td>{/* (end of the cell) */}
                </tr> // End of the row.
              ))}{/* End of the reports loop. */}
            </Table> // End of the table.
          )}{/* End of the choice. */}
        </Card> // End of the card.
      ) : section === "goals" ? ( // Goals:
        <>{/* (a group:) */}
          <Card title="Goals" description="Goals for each quarter and financial year, and how each is going so far. Check these at the monthly review: figures that add up over time (such as students matched) are compared with the share of the goal expected by now.">{/* a card explaining goals, */}
            {!isOwner && <p className="text-sm text-zinc-600">The owner sets the goals. Talk to the owner about any you think should change.</p>}{/* Operations: who sets goals. */}
          </Card>{/* End of the card. */}
          {goalPeriods.map((p) => { // For each period:
            const key = `${p.kind}:${p.start}`; // its key,
            const goals = allGoals.filter((g) => g.kind === p.kind && g.period_start === p.start); // its goals,
            const sofar = progress[key] ?? null; // its figures so far (this quarter and year only),
            const started = p.start <= today; // whether it has started,
            if (!started && goals.length === 0) return null; // a future period with no goals: not shown.
            return ( // shows:
              <Card // a card:
                key={key} // (one per period)
                title={`${p.kind === "quarterly" ? "Quarter" : "Financial year"}: ${goalPeriodLabel(p.kind, p.start)}`} // the period,
                description={sofar ? `${sofar.elapsed_days} of ${sofar.total_days} days gone. Figures so far, up to today.` : started ? undefined : `Starts ${shortDate(p.start)}.`} // how far through it is, or when it starts.
              >{/* (end of the card's settings) */}
                {goals.length === 0 ? ( // No goals:
                  <Empty>No goals set for this period yet.</Empty> // says so.
                ) : ( // Otherwise:
                  <Table headings={["Figure", "Goal", "So far", "Expected by now", "", ...(isOwner ? [""] : [])]}>{/* a table: */}
                    {goals.map((g) => { // for each goal:
                      const metric = goalMetric(g.metric); // the figure's details,
                      const how = sofar ? goalProgress(g.metric, Number(g.target), sofar, sofar.elapsed_days, sofar.total_days) : null; // how it is going (if started),
                      return ( // shows:
                        <tr key={g.id}>{/* a row: */}
                          <td>{metric?.label ?? g.metric}{g.note && <span className="block text-xs text-zinc-500">{g.note}</span>}</td>{/* the figure's name and any note, */}
                          <td>{goalTargetWords(g.metric, Number(g.target))}</td>{/* the goal, */}
                          <td className="tabular-nums">{how ? num(how.value, metric?.unit ?? "") : "Not started"}</td>{/* the figure so far, */}
                          <td className="tabular-nums">{how && metric?.grows ? num(how.expected, metric.unit) : how ? "Same as the goal" : ""}</td>{/* what is expected by now, */}
                          <td>{how && <GoalStatus ok={how.onTrack} during />}</td>{/* on track or behind, */}
                          {isOwner && ( // the owner can remove it:
                            <td className="text-right">{/* a cell on the right: */}
                              <form action={removeGoal}>{/* a remove form: */}
                                <input type="hidden" name="id" value={g.id} />{/* the goal's id, hidden, */}
                                <BusyButton type="submit" className="text-sm text-red-700 hover:underline">Remove</BusyButton>{/* and the remove button. */}
                              </form>{/* End of the form. */}
                            </td> // End of the cell.
                          )}{/* End of remove. */}
                        </tr> // End of the row.
                      ); // End of what is shown.
                    })}{/* End of the goals loop. */}
                  </Table> // End of the table.
                )}{/* End of the choice. */}
              </Card> // End of the card.
            ); // End of what is shown.
          })}{/* End of the periods loop. */}
          {isOwner && ( // The owner sets goals:
            <Card title="Set a goal" description="Choose the period, the figure and the target. Setting a goal for a figure that already has one in that period changes it. Goals only use figures without money, so Operations admins can see them.">{/* a card: */}
              <GoalForm periods={goalPeriods.map((p) => ({ value: `${p.kind}:${p.start}`, label: `${p.kind === "quarterly" ? "Quarter" : "Financial year"}: ${goalPeriodLabel(p.kind, p.start)}` }))} />{/* the form, with the four periods. */}
            </Card> // End of the card.
          )}{/* End of setting goals. */}
        </> // (end of the group)
      ) : section === "make" ? ( // Making a report for chosen dates:
        <Card title="Report for your dates" description="Choose any dates. The report is saved so you can open or download it again later.">{/* a card: */}
          <MakeReportForm today={today} ranges={quickRanges(today)} />{/* the form, with quick ranges. */}
        </Card> // End of the card.
      ) : ( // Settings:
        <Card title="Settings" description="Used to work out profit in new reports. Reports already made keep the figures they were made with.">{/* a card: */}
          <ReportSettingsForm // the settings form:
            superPercent={Number(settings?.super_percent ?? 12)} // the saved super (12% if not set),
            otherCosts={settings && settings.monthly_other_costs_cents > 0 ? (settings.monthly_other_costs_cents / 100).toFixed(2) : ""} // the saved other costs, in dollars (blank if none).
          />{/* End of the form. */}
        </Card> // End of the card.
      )}{/* End of the choice. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of ReportsPage.
