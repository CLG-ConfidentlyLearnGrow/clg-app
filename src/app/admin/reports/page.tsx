// Summary: the owner's Reports page: the monthly, quarterly and yearly
// reports the app makes by itself, reports for any dates, and the settings
// used for profit (super and other costs).
//
import type { ReactNode } from "react"; // The type for anything React can show.
import { deleteReport } from "@/app/actions/reports"; // The action that deletes a report made for chosen dates.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, SubHeading, Table, TextLink } from "@/components/ui"; // Shared page parts: card, empty line, small heading, table and text link.
import { requireAdminLevel } from "@/lib/auth"; // Makes sure the person is an admin at the right level.
import { addDays, localToday, shortDate } from "@/lib/scheduling"; // Date helpers.
import { REPORT_KIND_LABELS, money, num, periodLabel, reasonLabel, type SavedReport } from "@/lib/reports"; // Report names, number and money display, and the report type.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { MakeReportForm, ReportSettingsForm } from "./forms"; // The forms on this page.

// The page's sections.
const SECTIONS = [ // Each section's id and its name on screen:
  { id: "reports", label: "All reports" }, // the list of reports,
  { id: "make", label: "Report for your dates" }, // make one for any dates,
  { id: "settings", label: "Settings" }, // super and other costs.
] as const; // End of the list (fixed).

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

// Shows one report in full.
function ReportView({ report }: { report: SavedReport }) {
  const f = report.figures; // The report's figures.
  const m = f.money; // The money figures.
  return ( // Shows:
    <>{/* (a group:) */}
      <Card // a card for the report's heading:
        title={`${REPORT_KIND_LABELS[report.kind]} report: ${periodLabel(report)}`} // the kind and dates,
        description={`Made ${shortDate(report.made_at)}. Figures are saved as they were on that day.`} // when it was made.
      >{/* (end of the card's settings) */}
        <div className="flex flex-wrap gap-3">{/* a row of buttons: */}
          <a href={`/admin/reports/csv?id=${report.id}`} className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white">{/* download as a spreadsheet, */}
            Download spreadsheet (CSV){/* (its words) */}
          </a>{/* (end of the link) */}
          <TextLink href="/admin/reports">Back to all reports</TextLink>{/* and back to the list. */}
        </div>{/* End of the row. */}
      </Card>{/* End of the heading card. */}

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
          <Stat label="Didn't go ahead" value={num(f.enquiries.did_not_go_ahead)} />{/* didn't go ahead. */}
        </Stats>{/* End of the numbers. */}
        <p className="mt-3 text-sm text-zinc-600">Average time from being added to booking: {num(f.enquiries.average_days_to_book, " days")}.</p>{/* Average days to book. */}
      </Card>{/* End of the enquiries card. */}

      <Card title="How full each tutor's week is" description="Compared with the most hours each tutor wants a week (or the hours they're available, if no limit is set). Fullest first.">{/* The tutor weeks card: */}
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
            {m.sessions_not_billed > 0 && <li>{m.sessions_not_billed} sessions aren&apos;t on an invoice yet, so income is missing and profit looks lower than it is.</li>}{/* sessions not billed, */}
            {!m.other_costs_set && <li>Other running costs aren&apos;t set (Reports, Settings), so &ldquo;after all costs&rdquo; only takes off wages.</li>}{/* other costs not set. */}
          </ul> // End of the note.
        )}{/* End of the note. */}
      </Card>{/* End of the money card. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of ReportView.

// Shows the Reports page (owner only).
export default async function ReportsPage({ searchParams }: PageProps<"/admin/reports">) {
  const viewer = await requireAdminLevel(["owner"]); // Must be the owner (reports include pay and profit).
  const params = await searchParams; // Reads the address settings.
  const supabase = await createClient(); // Connects to the database.
  const id = typeof params.id === "string" ? params.id : null; // The report to open, if any.
  const section = id ? "reports" : SECTIONS.find((s) => s.id === params.section)?.id ?? "reports"; // The section asked for (the list by default).

  let report: SavedReport | null = null; // The open report, if any.
  if (id && /^[0-9a-f-]{36}$/.test(id)) { // A report id that looks right:
    const { data } = await supabase.from("reports").select("id, kind, period_start, period_end, figures, made_at, read_at").eq("id", id).maybeSingle(); // reads it,
    report = (data as SavedReport | null) ?? null; // keeps it (or nothing if not found),
    if (report && !report.read_at) await supabase.rpc("report_mark_read", { p_id: report.id }); // and marks it read the first time it's opened.
  } // End of reading the report.

  const [listRes, settingsRes] = await Promise.all([ // Reads two things at once:
    section === "reports" && !report // on the list:
      ? supabase.from("reports").select("id, kind, period_start, period_end, made_at, read_at").order("made_at", { ascending: false }).limit(200) // the newest 200 reports,
      : Promise.resolve({ data: [] }), // otherwise nothing.
    supabase.from("report_settings").select("super_percent, monthly_other_costs_cents").maybeSingle(), // and the settings.
  ]); // End of the reads.
  const list = (listRes.data ?? []) as Omit<SavedReport, "figures">[]; // The reports listed.
  const unread = list.filter((r) => !r.read_at).length; // How many are new.
  const settings = settingsRes.data as { super_percent: number; monthly_other_costs_cents: number } | null; // The settings.
  const today = localToday(); // Today's date.

  return ( // Shows:
    <DashboardFrame // the dashboard frame:
      role="admin" // the admin dashboard,
      roles={viewer.roles} // the person's roles (for the tabs and numbers),
      current="reports" // this page's tab open,
      sub={section} // on the open section,
      items={SECTIONS.map((s) => ({ ...s, href: `/admin/reports?section=${s.id}`, count: s.id === "reports" ? unread || undefined : undefined }))} // with this page's sections under the tab.
    >{/* (end of the frame's settings) */}
      {report ? ( // A report is open:
        <ReportView report={report} /> // shows it.
      ) : id ? ( // An id was given but no report found:
        <Card title="Report not found">{/* a card saying so: */}
          <p className="text-sm">It may have been deleted. <TextLink href="/admin/reports">Back to all reports</TextLink></p>{/* with a link back. */}
        </Card> // End of the card.
      ) : section === "reports" ? ( // The list:
        <Card // a card:
          title="All reports" // titled "All reports",
          description="The app makes a monthly report on the 1st, a quarterly report after each quarter, and a financial year report each July. You'll see a number on Reports when a new one is ready." // explaining when reports are made.
        >{/* (end of the card's settings) */}
          {list.length === 0 ? ( // No reports yet:
            <Empty>No reports yet. The first monthly report (November 2026) arrives on 1 December. You can make one for any dates now under &ldquo;Report for your dates&rdquo;.</Empty> // says when the first arrives.
          ) : ( // Otherwise:
            <Table headings={["Report", "Covers", "Made", ""]}>{/* a table: */}
              {list.map((r) => ( // for each report:
                <tr key={r.id}>{/* a row: */}
                  <td>{/* the kind, with "New" if not opened yet: */}
                    {REPORT_KIND_LABELS[r.kind]}{/* the kind, */}
                    {!r.read_at && <span className="ml-2 rounded-full bg-brand px-2 py-0.5 text-xs text-white">New</span>}{/* and a "New" label if unread. */}
                  </td>{/* (end of the cell) */}
                  <td>{periodLabel(r)}</td>{/* the dates, */}
                  <td>{shortDate(r.made_at)}</td>{/* when it was made, */}
                  <td className="text-right">{/* the actions: */}
                    <div className="flex items-center justify-end gap-3">{/* side by side: */}
                      <TextLink href={`/admin/reports?id=${r.id}`}>Open</TextLink>{/* open it, */}
                      {r.kind === "custom" && ( // reports for chosen dates can be deleted:
                        <form action={deleteReport}>{/* a delete form: */}
                          <input type="hidden" name="id" value={r.id} />{/* the report's id, hidden, */}
                          <button type="submit" className="text-sm text-red-700 hover:underline">Delete</button>{/* and the delete button. */}
                        </form> // End of the form.
                      )}{/* End of delete. */}
                    </div>{/* End of the actions. */}
                  </td>{/* (end of the cell) */}
                </tr> // End of the row.
              ))}{/* End of the reports loop. */}
            </Table> // End of the table.
          )}{/* End of the choice. */}
        </Card> // End of the card.
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
