// Summary: the admin pay section: hours waiting for approval, each pay period's lines, sending to
// Xero Payroll, recording admin hours, pay rates, and the pay period settings.
//
import { approveHours, removePayLine } from "@/app/actions/pay"; // The server actions to approve hours and remove a pay line.
import { Button, Card, Empty, SubHeading, Table, TextLink } from "@/components/ui"; // The button, card, "nothing yet" note, small heading, table and link style.
import { xeroConfig } from "@/lib/billing/config"; // Xero's settings.
import { dollars, plainDate } from "@/lib/billing/money"; // Money as dollars, and dates in words.
import { workCategoryLabel } from "@/lib/billing/work-categories"; // The words for each kind of work outside sessions.
import { listXeroEarningsRates, listXeroEmployees } from "@/lib/billing/payroll"; // Reads Xero Payroll's employees and earnings rates.
import { xeroConnection } from "@/lib/billing/xero"; // Reads the saved Xero connection.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { AdminTimeForm, AwardRatesForm, DeclineHoursForm, LinkXeroByEmailForm, PayPeriodForm, SendTimesheetsForm, StaffPayForm, WorkOutPayForm, XeroTaskDoneForm, type StaffPay } from "./pay-forms"; // The pay forms, and the pay details type.

// A pay line as the database gives it.
type Line = {
  id: string; // its id,
  account_id: string | null; // who (if known),
  staff_name: string; // their name,
  work_date: string; // the day worked,
  kind: "session" | "late_cancel" | "min_topup" | "admin" | "tutoring_work" | "guaranteed" | "summary" | "training" | "term_review"; // what kind of pay,
  work_kind: string; // the kind of work (school, tertiary or admin),
  minutes: number; // minutes,
  rate_cents: number; // the rate in cents,
  amount_cents: number; // the pay in cents,
  under_award: boolean; // whether it's under the award minimum,
  note: string | null; // a note (if any),
  status: "pending" | "sent"; // and whether it's waiting or sent.
}; // End of the shape.

const KIND_LABELS: Record<Line["kind"], string> = { // Words for each kind of pay line:
  session: "Session", // session,
  late_cancel: "Late cancel", // late cancellation,
  min_topup: "2 hr minimum top-up", // 2 hr minimum top-up,
  admin: "Office admin", // office admin,
  tutoring_work: "Tutoring work", // tutoring work,
  guaranteed: "Guaranteed hours top-up", // guaranteed hours top-up.
  summary: "Session summary and planning", // 5 min summary plus 10 min planning the next session.
  training: "Training", // compulsory training, for its set time.
  term_review: "Term review", // writing a term review CLG approved, 1 hour at the tutor rate.
}; // End of the list.

// Adds days to a date (written as YYYY-MM-DD).
function addDays(day: string, n: number) {
  return new Date(Date.parse(`${day}T00:00:00Z`) + n * 86400000).toISOString().slice(0, 10); // Moves the date by n days.
} // End of addDays.

const hours = (m: number) => `${Math.round((m / 60) * 100) / 100} hr`; // Minutes written as hours, e.g. "1.5 hr".

// Tutor and staff pay: rates, each pay period's lines, and sending them to
// Xero Payroll.
// canEdit is false for Operations admins: they see pay but only the owner
// and Finance change it.
export async function PaySection({
  periodParam, // the pay period asked for (any day in it),
  isOwner, // whether this person is the owner,
  canEdit = true, // whether they can change pay (yes by default),
  today, // and today's date.
}: { // (their types:)
  periodParam: string | null; // a date or nothing,
  isOwner: boolean; // true or false,
  canEdit?: boolean; // true or false (optional),
  today: string; // a date.
}) { // (end of the settings)
  const supabase = await createClient(); // Connects to the database.
  const pick = periodParam && /^\d{4}-\d{2}-\d{2}$/.test(periodParam) ? periodParam : addDays(today, -1); // The day to show: the one asked for, or yesterday.
  const { data: period } = await supabase // Finds the pay period:
    .rpc("billing_pay_period", { p_day: pick }) // that holds that day,
    .single<{ period_start: string; period_end: string }>(); // (one row with its first and last day).
  const start = period?.period_start ?? pick; // The first day.
  const end = period?.period_end ?? pick; // The last day.
  const length = Math.round((Date.parse(end) - Date.parse(start)) / 86400000) + 1; // How many days the period has.

  const [roles, pay, lines, problems, settings, emails, waitingHours, recentWork, ratesDue] = await Promise.all([ // Reads nine things at once:
    supabase.from("account_roles").select("account_id, role, account:accounts(full_name)").in("role", ["tutor", "admin"]), // every tutor and admin with their name,
    supabase.from("billing_staff_pay").select("*"), // everyone's pay details,
    supabase.from("billing_pay_lines").select("*").gte("work_date", start).lte("work_date", end).order("work_date"), // the pay lines in this period, by day,
    supabase.from("billing_pay_problems").select("*").gte("work_date", start).lte("work_date", end), // sessions waiting on a pay rate,
    supabase.from("billing_settings").select("pay_period_days, pay_period_anchor, casual_min_enabled").maybeSingle(), // the pay period settings,
    supabase.from("account_private").select("account_id, email"), // everyone's email,
    supabase.from("billing_hour_logs").select("id, account_id, work_date, minutes, note, logged_late, work_type, source, work_category, achieved").eq("status", "submitted").order("work_date"), // hours waiting for approval, by day,
    supabase // work outside sessions from the last 8 weeks, to check what was achieved (Carla, 18 Nov 2026):
      .from("billing_hour_logs") // (from the hour logs table)
      .select("id, account_id, work_date, minutes, note, status, work_category, achieved, review_note") // with what was done and achieved, and how it was reviewed,
      .eq("source", "staff") // logged by staff themselves,
      .gte("work_date", addDays(today, -56)) // in the last 8 weeks,
      .order("work_date", { ascending: false }), // newest first,
    supabase.rpc("award_rates_due"), // and whether new award rates are due (owner and Finance only; Carla, 18 Nov 2026).
  ]); // End of the reads.
  const dueJuly = typeof ratesDue.data === "string" ? ratesDue.data : null; // The 1 July new award rates are needed for (or nothing).
  type WorkRow = { id: string; account_id: string; work_date: string; minutes: number; note: string; status: string; work_category: string | null; achieved: string | null; review_note: string | null }; // One entry of work outside sessions.
  const workByPerson = new Map<string, WorkRow[]>(); // The entries grouped by person.
  for (const w of (recentWork.data ?? []) as WorkRow[]) workByPerson.set(w.account_id, [...(workByPerson.get(w.account_id) ?? []), w]); // Adds each entry to its person's group.

  const staff = new Map<string, string>(); // Each staff member's name, by id.
  const rolesOf = new Map<string, string[]>(); // Each staff member's roles, by id.
  for (const r of (roles.data ?? []) as unknown as { account_id: string; role: string; account: { full_name: string } | null }[]) { // For each role held:
    staff.set(r.account_id, r.account?.full_name ?? "Staff"); // keeps their name,
    rolesOf.set(r.account_id, [...(rolesOf.get(r.account_id) ?? []), r.role]); // and adds the role to their list.
  } // End of the loop.
  // A short summary of each person's rates, one per role they hold.
  const rateText = (cents: number | null | undefined) => (cents != null ? dollars(cents) : "not entered"); // A rate in dollars, or "not entered".
  // A one-line summary of a person's employment and rates.
  function summary(id: string, p: StaffPay | null) {
    const held = rolesOf.get(id) ?? []; // The roles they hold.
    const parts: string[] = []; // The rate parts.
    if (held.includes("tutor")) parts.push(`tutor school ${rateText(p?.school_rate_cents)}, tertiary ${rateText(p?.tertiary_rate_cents)}`); // Tutors: school and tertiary rates.
    if (held.includes("admin")) parts.push(`admin ${rateText(p?.admin_rate_cents)}`); // Admins: the admin rate.
    const roleNames = held.map((r) => (r === "admin" ? "Admin" : "Tutor")).join(" and "); // Their roles in words.
    return `${roleNames}${p ? ` · ${p.employment.replace("_", "-")}` : ""} · ${parts.join(" · ")}`; // e.g. "Tutor · casual · tutor school $40, tertiary $45".
  } // End of summary.
  const staffList = [...staff].map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name)); // The staff list, by name.

  // Award minimum rates (every year kept) and the rates the app raised.
  // The Xero to-do list: changes Xero's employee records still need (owner and Finance only).
  const { data: xeroTaskRows } = await supabase // Reads:
    .from("billing_xero_tasks") // the Xero to-do list,
    .select("id, account_id, kind, details, created_at") // each line's details,
    .is("done_at", null) // only what's still to do,
    .order("created_at"); // oldest first.
  const xeroTasks = (xeroTaskRows ?? []) as { id: string; account_id: string; kind: string; details: string; created_at: string }[]; // The lines still to do.
  const missing = [...new Set(xeroTasks.map((t) => t.account_id).filter((id) => !staff.has(id)))]; // People on the list who are no longer staff (for example they left).
  const { data: formerRows } = missing.length ? await supabase.from("accounts").select("id, full_name").in("id", missing) : { data: [] }; // Reads their names (nothing to read if none).
  const nameOf = new Map<string, string>([...staff, ...((formerRows ?? []) as { id: string; full_name: string }[]).map((a) => [a.id, a.full_name] as [string, string])]); // Everyone's name, by id.

  const [awardRes, changeRes] = await Promise.all([ // Reads two things at once:
    supabase.from("billing_award_rates").select("work_kind, employment, min_rate_cents, award, effective_from").order("effective_from", { ascending: false }), // award rates, newest first,
    supabase.from("billing_staff_rate_changes").select("id, account_id, work_kind, old_cents, new_cents, effective_from").order("created_at", { ascending: false }).limit(20), // and the last 20 automatic raises.
  ]); // End of the reads.
  const awardRows = (awardRes.data ?? []) as { work_kind: string; employment: string; min_rate_cents: number; award: string; effective_from: string }[]; // The award rates.
  const awardDates = [...new Set(awardRows.map((a) => a.effective_from))]; // Each start date, newest first.
  const currentDate = awardDates.find((d) => d <= start) ?? awardDates[awardDates.length - 1]; // The start date in force for this pay period.
  const templateCsv = ["work,employment,hourly_rate,award", ...awardRows.filter((a) => a.effective_from === currentDate).map((a) => `${a.work_kind},${a.employment},${(a.min_rate_cents / 100).toFixed(2)},${a.award}`)].join("\n"); // This year's rates as a file to download and change.
  const yearNow = Number(start.slice(0, 4)); // The pay period's year.
  const nextJuly = `${start.slice(5) >= "07-01" ? yearNow + 1 : yearNow}-07-01`; // The next 1 July.
  const WORK_LABELS: Record<string, string> = { school: "School tutoring", tertiary: "Tertiary tutoring", admin: "Admin" }; // Plain names for the kinds of work.
  const payOf = new Map(((pay.data ?? []) as StaffPay[]).map((p) => [p.account_id, p])); // Each person's pay details, by id.
  const lineRows = (lines.data ?? []) as Line[]; // The pay lines.
  const byPerson = new Map<string, Line[]>(); // The pay lines grouped by person.
  for (const l of lineRows) byPerson.set(l.staff_name, [...(byPerson.get(l.staff_name) ?? []), l]); // Adds each line to its person's group.
  const emailOf = new Map((emails.data ?? []).map((e) => [e.account_id, e.email.toLowerCase()])); // Each person's email in lower case, by id.

  // Xero Payroll lists, when Xero is connected, so admins pick from them.
  let xeroEmployees: { id: string; name: string; email: string }[] | null = null; // Xero employees (none until read).
  let xeroRates: { id: string; name: string }[] | null = null; // Xero earnings rates (none until read).
  let xeroNote: string | null = null; // A note if Xero couldn't be read.
  if (xeroConfig() && (await xeroConnection().catch(() => null))) { // If Xero is set up and connected:
    try { // tries:
      const [emps, rates] = await Promise.all([listXeroEmployees(), listXeroEarningsRates()]); // reads employees and rates at once,
      xeroEmployees = emps.map((e) => ({ id: e.EmployeeID, name: `${e.FirstName} ${e.LastName}`, email: (e.Email ?? "").toLowerCase() })); // keeps each employee's id, name and email,
      xeroRates = rates.map((r) => ({ id: r.EarningsRateID, name: r.Name })); // and each rate's id and name.
    } catch (e) { // If it failed:
      xeroNote = `Could not read Xero Payroll: ${(e as Error).message} You may need to connect Xero again to allow payroll.`; // notes why, and that Xero may need connecting again.
    } // End of the try.
  } // End of the Xero part.

  const pending = lineRows.filter((l) => l.status === "pending"); // Lines not yet sent to Xero.
  const underAward = lineRows.filter((l) => l.under_award); // Lines under the award minimum.

  return ( // Shows:
    <>{/* (a group:) */}
      {dueJuly && ( // If new award rates are due (Carla, 18 Nov 2026):
        <Card title="New award pay rates are due">{/* a reminder card: */}
          <p className="text-sm">{/* what to do: */}
            The award pay rates for the financial year starting {plainDate(dueJuly)} have not been entered yet. The Fair Work
            Commission usually publishes them in early June. Upload them under Award rates below. The app then raises any
            staff rate below the new minimum on the start date and adds a line to the Xero to-do list for each change, so
            Xero can be updated to match.{/* (the reminder's words: which year, where to upload, and what happens next) */}
          </p>{/* End of the text. */}
        </Card> // End of the reminder.
      )}{/* End of that part. */}
      {(waitingHours.data ?? []).length > 0 && ( // if hours are waiting:
        <Card title="Hours waiting for approval" description="Tutoring work and office admin logged by staff on their My pay page, and guaranteed hours top-ups added by the app. Approved hours are paid in the next send to Xero.">{/* a card explaining them: */}
          <div className="space-y-4">{/* a block with space between parts: */}
            {(waitingHours.data ?? []).map((h) => ( // for each log:
              <div key={h.id} className="rounded-xl border border-zinc-200 p-4 text-sm">{/* a bordered box: */}
                <p className="mb-3">{/* a line: */}
                  <strong>{staff.get(h.account_id) ?? "Staff"}</strong>, {plainDate(h.work_date)}:{" "}{/* who and the day, */}
                  {h.source === "guaranteed" ? "Guaranteed hours top-up" : h.source === "training" ? `Training (${h.work_type === "tutoring" ? "tutor rate" : "admin rate"})` : (workCategoryLabel(h.work_category) ?? (h.work_type === "tutoring" ? "Tutoring work" : "Office admin"))},{" "}{/* the kind of hours, */}
                  {hours(h.minutes)}. {h.note}{/* how long, and the description, */}
                  {h.logged_late && <span className="ml-1 text-xs text-amber-800">(logged late)</span>}{/* marked if logged late. */}
                </p>{/* End of the line. */}
                {h.achieved && <p className="mb-3 text-zinc-700">Finished or achieved: {h.achieved}</p>}{/* what they say they achieved (Carla, 18 Nov 2026), */}
                {h.work_category === "no_show_time" && <p className="mb-3 text-xs text-zinc-600">This time is already paid with the session. Approving marks the work checked and adds no pay.</p>}{/* a note that no-show time is not paid again. */}
                {canEdit ? ( // If this person can change pay:
                  <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
                    <form action={approveHours}>{/* a form that approves it: */}
                      <input type="hidden" name="id" value={h.id} />{/* which log (hidden), */}
                      <Button type="submit">Approve</Button>{/* the "Approve" button. */}
                    </form>{/* End of the form. */}
                    <DeclineHoursForm id={h.id} />{/* The decline form. */}
                  </div> // End of the columns.
                ) : ( // Otherwise:
                  <p className="text-zinc-600">The owner or a Finance admin approves these.</p> // who approves these.
                )}{/* End of the choice. */}
              </div> // End of the box.
            ))}{/* End of the loop. */}
          </div>{/* End of the block. */}
        </Card> // End of the card.
      )}{/* End of that part. */}
      <Card title={`Pay period ${plainDate(start)} to ${plainDate(end)}`}>{/* A card for the pay period: */}
        <p className="mb-4 flex gap-4 text-sm">{/* a line of links: */}
          <TextLink href={`/admin/billing?section=pay&period=${addDays(start, -length)}`}>« Earlier</TextLink>{/* the earlier period, */}
          <TextLink href={`/admin/billing?section=pay&period=${addDays(start, length)}`}>Later »</TextLink>{/* the later period. */}
        </p>{/* End of the line. */}
        {settings.data && !settings.data.casual_min_enabled && ( // If the casual minimum is off:
          <p className="mb-4 rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-900">{/* an amber note: */}
            The 2 hr minimum top-up for casual staff is switched off for now, so short days are paid only for the time
            worked. The awards require at least 2 hr pay for each day a casual attends work, so check this with your
            employment adviser. {isOwner ? "You can turn it back on under Pay period below." : ""}{/* what the awards say, and for the owner where to turn it on. */}
          </p> // End of the note.
        )}{/* End of that part. */}
        {underAward.length > 0 && ( // If any lines are under the award:
          <p className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">{/* a red note: */}
            {underAward.length} line(s) pay under the award minimum for that person&apos;s employment type. Check their
            rate before sending.{/* how many, and to check the rate. */}
          </p> // End of the note.
        )}{/* End of that part. */}
        {(problems.data ?? []).length > 0 && ( // If sessions are waiting on a rate:
          <div className="mb-4 rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-900">{/* an amber box: */}
            <p className="font-medium">Waiting on a pay rate:</p>{/* a heading, */}
            <ul className="list-disc pl-5">{/* a bulleted list: */}
              {(problems.data ?? []).map((p) => ( // for each one:
                <li key={p.session_id}>{/* a list item: */}
                  {p.full_name}, {plainDate(p.work_date)}: {p.problem}{/* who, which day, and the problem. */}
                </li> // (end of the item)
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
          </div> // End of the box.
        )}{/* End of that part. */}
        {byPerson.size === 0 ? ( // If there's no pay:
          <Empty>No pay in this period yet.</Empty> // says so.
        ) : ( // Otherwise:
          <div className="space-y-6">{/* a block with space between parts: */}
            {[...byPerson].map(([name, own]) => ( // for each person:
              <div key={name}>{/* a block: */}
                <SubHeading>{/* a small heading: */}
                  {name}: {hours(own.reduce((t, l) => t + l.minutes, 0))}, {dollars(own.reduce((t, l) => t + l.amount_cents, 0))}{/* their name, total hours and total pay. */}
                </SubHeading>{/* End of the heading. */}
                <Table headings={["Day", "What", "Hours", "Rate", "Pay", ""]}>{/* A table with these headings: */}
                  {own.map((l) => ( // for each line:
                    <tr key={l.id} className={l.under_award ? "bg-red-50" : undefined}>{/* a row (red if under the award): */}
                      <td>{plainDate(l.work_date)}</td>{/* the day, */}
                      <td>{/* a cell: */}
                        {KIND_LABELS[l.kind]} ({l.work_kind}){l.note ? `: ${l.note}` : ""}{/* the kind of pay, kind of work, and note. */}
                      </td>{/* End of the cell. */}
                      <td>{hours(l.minutes)}</td>{/* Hours, */}
                      <td>{dollars(l.rate_cents)}/hr</td>{/* rate, */}
                      <td>{dollars(l.amount_cents)}</td>{/* pay, */}
                      <td>{/* a cell: */}
                        {l.status === "sent" ? ( // if sent:
                          "In Xero" // "In Xero",
                        ) : l.kind === "admin" && canEdit ? ( // admin hours this person can change:
                          <form action={removePayLine}>{/* a form that removes it: */}
                            <input type="hidden" name="id" value={l.id} />{/* which line (hidden), */}
                            <Button type="submit">Remove</Button>{/* the "Remove" button. */}
                          </form> // End of the form.
                        ) : ( // Otherwise:
                          "Waiting" // "Waiting".
                        )}{/* End of the choice. */}
                      </td>{/* End of the cell. */}
                    </tr> // End of the row.
                  ))}{/* End of the lines loop. */}
                </Table>{/* End of the table. */}
              </div> // End of the block.
            ))}{/* End of the people loop. */}
          </div> // End of the block.
        )}{/* End of the choice. */}
        {canEdit ? ( // If this person can change pay:
          <div className="mt-6 grid gap-6 sm:grid-cols-2">{/* two columns on wider screens: */}
            <WorkOutPayForm from={start} to={end} />{/* the "work out pay again" form, */}
            {pending.length > 0 && <SendTimesheetsForm periodStart={start} />}{/* and the "send to Xero" form, if anything is waiting. */}
          </div> // End of the columns.
        ) : ( // Otherwise:
          <p className="mt-6 text-sm text-zinc-600">You can see pay here. The owner or a Finance admin works it out and sends it to Xero.</p> // who works out and sends pay.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}

      {canEdit && ( // If this person can change pay:
        <Card title="Record admin hours" collapsible defaultOpen={false}>{/* a closed card: */}
          <AdminTimeForm staff={staffList.filter((s) => payOf.get(s.id)?.admin_rate_cents != null)} />{/* the admin hours form, for staff with an admin rate. */}
        </Card> // End of the card.
      )}{/* End of that part. */}

      {canEdit && ( // For the owner and Finance:
        <Card title={`Xero to-do${xeroTasks.length ? ` (${xeroTasks.length})` : ""}`} description="Changes to make to staff employee records in Xero, so Xero pays the same as the app. A line is added whenever someone's employment type, agreed hours or rates change, or they leave CLG. Tick each one off once Xero matches.">{/* a card listing what Xero still needs: */}
          {xeroTasks.length === 0 ? ( // Nothing to do:
            <Empty>Xero is up to date with the app.</Empty> // says so.
          ) : ( // Otherwise:
            <ul className="space-y-3">{/* a list: */}
              {xeroTasks.map((t) => ( // for each line:
                <li key={t.id} className="rounded-xl border border-amber-200 bg-amber-50 p-3">{/* an amber box: */}
                  <p className="text-sm font-medium text-zinc-900">{/* the first line: */}
                    {nameOf.get(t.account_id) ?? "Former staff member"} · {t.kind === "left" ? "Left CLG" : "Pay details changed"}{/* who, and what kind of change, */}
                  </p>{/* End of the first line. */}
                  <p className="mt-1 text-sm text-zinc-700">{t.details}</p>{/* what to change, */}
                  <p className="mt-1 text-xs text-zinc-500">Changed in the app {t.created_at.slice(0, 10)}</p>{/* when it changed, */}
                  <div className="mt-2"><XeroTaskDoneForm id={t.id} /></div>{/* and the "Done in Xero" button. */}
                </li> // End of the box.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of the choice. */}
        </Card> // End of the card.
      )}{/* End of the Xero to-do part. */}

      <Card title="Pay rates" description="A separate hourly rate for each role a person holds: tutors have a school and a tertiary rate, admins have an admin rate. Someone who is both has all three. Pay is only worked out for a role once its rate is entered.">{/* A card of pay rates, explaining them: */}
        {xeroNote && <p className="mb-4 text-sm text-red-800">{xeroNote}</p>}{/* the Xero note, if any, */}
        {!xeroNote && !xeroEmployees && ( // If Xero isn't connected:
          <p className="mb-4 text-sm text-amber-900">{/* an amber note: */}
            Xero is not connected, so staff cannot be matched to their Xero employee records yet. The owner connects it under Stripe and Xero, above.{/* why matching isn't shown, and how to fix it. */}
          </p> // End of the note.
        )}{/* End of that note. */}
        {canEdit && xeroEmployees && <div className="mb-4"><LinkXeroByEmailForm /></div>}{/* When Xero is connected: the "link by email" button. */}
        {staffList.length === 0 ? ( // if there are no staff:
          <Empty>No tutors or admins yet.</Empty> // says so.
        ) : ( // Otherwise:
          <div className="space-y-6">{/* a block with space between parts: */}
            {staffList.map((s) => { // for each person:
              const p = payOf.get(s.id) ?? null; // their pay details,
              const email = emailOf.get(s.id); // their email,
              const suggested = xeroEmployees?.find((e) => e.email && e.email === email)?.id ?? null; // the Xero employee with the same email.
              return ( // Shows:
                <details key={s.id} className="rounded-xl border border-zinc-200 p-4">{/* a section that opens when clicked: */}
                  <summary className="cursor-pointer text-sm font-medium">{/* its heading: */}
                    {s.name} · {summary(s.id, p)}{/* their name and summary. */}
                  </summary>{/* End of the heading. */}
                  {canEdit && <div className="mt-4">{/* If this person can change pay, a block: */}
                    <StaffPayForm // the pay details form:
                      accountId={s.id} // who,
                      pay={p} // their details,
                      xeroEmployees={xeroEmployees?.map(({ id, name }) => ({ id, name })) ?? null} // Xero employees (id and name only),
                      xeroRates={xeroRates} // Xero rates,
                      suggestedEmployee={suggested} // the matching employee,
                      roles={rolesOf.get(s.id) ?? []} // and their roles.
                    />{/* (end of the form) */}
                  </div>}{/* End of the block. */}
                </details> // End of the section.
              ); // End of what's shown for this person.
            })}{/* End of the loop. */}
          </div> // End of the block.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}

      <Card title="Work outside sessions (last 8 weeks)" collapsible defaultOpen={false} description="What each person logged doing outside sessions, and what they say they finished or achieved, so CLG can check the time was well used. Open someone to see their entries.">{/* A card to check work outside sessions (Carla, 18 Nov 2026): */}
        {workByPerson.size === 0 ? ( // if nobody logged any:
          <Empty>No work outside sessions logged in the last 8 weeks.</Empty> // says so.
        ) : ( // Otherwise:
          <div className="space-y-2">{/* a block: */}
            {[...workByPerson].sort((a, b) => (staff.get(a[0]) ?? "").localeCompare(staff.get(b[0]) ?? "")).map(([id, rows]) => ( // each person, by name:
              <details key={id} className="rounded-xl border border-zinc-200 p-3 text-sm">{/* an open-and-close box: */}
                <summary className="cursor-pointer">{/* its heading: */}
                  <strong>{nameOf.get(id) ?? "Staff"}</strong>: {rows.length} {rows.length === 1 ? "entry" : "entries"}, {hours(rows.reduce((t, r) => t + r.minutes, 0))}{/* who, how many entries and the total hours. */}
                </summary>{/* End of the heading. */}
                <ul className="mt-2 space-y-2">{/* the entries: */}
                  {rows.map((r) => ( // each entry:
                    <li key={r.id} className="border-t border-zinc-100 pt-2">{/* a line: */}
                      <span className="font-medium">{plainDate(r.work_date)}, {hours(r.minutes)}</span>{/* the day and hours, */}
                      <span className="text-zinc-600"> · {workCategoryLabel(r.work_category) ?? "Work outside sessions"} · {r.status === "submitted" ? "waiting" : r.status}</span>{/* the kind of work and where it is up to, */}
                      <span className="block">{r.note}</span>{/* what they did, */}
                      {r.achieved ? <span className="block text-zinc-700">Achieved: {r.achieved}</span> : <span className="block text-zinc-500">No achievement written (logged before this was asked).</span>}{/* what they achieved (or a note for older entries), */}
                      {r.review_note && <span className="block text-xs text-zinc-500">CLG note: {r.review_note}</span>}{/* and any note from the review. */}
                    </li> // End of the line.
                  ))}{/* End of the entries. */}
                </ul>{/* End of the list. */}
              </details> // End of the box.
            ))}{/* End of the people. */}
          </div> // End of the block.
        )}{/* End of the choice. */}
      </Card>{/* End of the work card. */}

      <Card title="Award rates" collapsible defaultOpen={false} description="The award minimum hourly rates, by work and employment type. Upload next year's rates before 1 July; anyone below the new minimum is raised on the start date, and work before that date is still paid at the old rate.">{/* A card for the yearly award rates: */}
        {awardDates.length === 0 ? <Empty>No award rates yet.</Empty> : awardDates.slice(0, 3).map((d) => ( // The three most recent years:
          <div key={d} className="mb-4">{/* one year: */}
            <SubHeading>{d > start ? `Starting ${plainDate(d)} (coming up)` : d === currentDate ? `From ${plainDate(d)} (in force now)` : `From ${plainDate(d)} (earlier)`}</SubHeading>{/* its start date and whether it's current */}
            <Table headings={["Work", "Employment", "Minimum", "Award"]}>{/* a table of its rates: */}
              {awardRows.filter((a) => a.effective_from === d).map((a) => ( // each rate:
                <tr key={`${a.work_kind}-${a.employment}`}>{/* a row: */}
                  <td>{WORK_LABELS[a.work_kind] ?? a.work_kind}</td>{/* the work, */}
                  <td>{a.employment.replace("_", "-")}</td>{/* the employment type, */}
                  <td>{dollars(a.min_rate_cents)}/hr</td>{/* the minimum, */}
                  <td>{a.award}</td>{/* and the award. */}
                </tr> // End of the row.
              ))}
            </Table>{/* end of the table */}
          </div> // End of the year.
        ))}
        {(changeRes.data ?? []).length > 0 && ( // If the app has raised any rates:
          <div className="mb-4">{/* the list of raises: */}
            <SubHeading>Rates raised automatically</SubHeading>{/* its heading */}
            <ul className="space-y-1 text-sm">{/* one line each: */}
              {(changeRes.data ?? []).map((c) => ( // each raise:
                <li key={c.id}>{staff.get(c.account_id) ?? "Staff"}: {WORK_LABELS[c.work_kind] ?? c.work_kind} {dollars(c.old_cents)} to {dollars(c.new_cents)}/hr from {plainDate(c.effective_from)}</li> // who, which rate, old and new, and when.
              ))}
            </ul>{/* end of the list */}
          </div> // End of the raises.
        )}
        {canEdit && <AwardRatesForm nextJuly={nextJuly} templateCsv={templateCsv} />}{/* the upload form, for the owner and Finance */}
      </Card>{/* End of the award rates card. */}

      {isOwner && settings.data && ( // For the owner:
        <Card title="Pay period and casual minimum" collapsible defaultOpen={false}>{/* a closed card: */}
          <PayPeriodForm // the pay period form:
            days={settings.data.pay_period_days} // weekly or fortnightly,
            anchor={settings.data.pay_period_anchor} // a day a period starts,
            casualMin={settings.data.casual_min_enabled} // and the casual minimum.
          />{/* (end of the form) */}
        </Card> // End of the card.
      )}{/* End of that part. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of PaySection.
