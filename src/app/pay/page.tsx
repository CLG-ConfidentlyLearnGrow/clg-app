// Summary: the "My pay" page for tutors and staff: rates, logged hours and recent pay lines.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { withdrawMyHours } from "@/app/actions/pay"; // The server action that takes back logged hours.
import { LogHoursForm } from "@/app/admin/billing/pay-forms"; // The form for logging hours.
import { Button, Card, Empty, Page, Table } from "@/components/ui"; // The button, card, "nothing yet" note, page frame and table.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Checks two-step login, and makes sure someone is signed in.
import { dollars, plainDate } from "@/lib/billing/money"; // Money as dollars, and dates in words.
import { adelaideToday } from "@/lib/billing/run"; // Today's date in Adelaide.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

const KIND_LABELS: Record<string, string> = { // Each kind of pay line's words:
  session: "Session", // a session,
  late_cancel: "Late cancel", // a late cancellation,
  min_topup: "2 hr minimum top-up", // the 2 hr minimum top-up,
  admin: "Office admin", // office admin,
  tutoring_work: "Tutoring work", // tutoring work outside sessions,
  guaranteed: "Guaranteed hours top-up", // the guaranteed hours top-up.
  summary: "Session summary", // time to write the summary after a session.
}; // End of the list.

const hours = (m: number) => `${Math.round((m / 60) * 100) / 100} hr`; // Minutes written as hours, e.g. "1.5 hr".

// A tutor's or staff member's own pay: rates and the last 8 weeks of pay
// lines, as worked out from their sign on and sign off times.
export default async function MyPayPage() {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard"); // Not a tutor or admin: goes to the dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login not set up: sends them to set it up.
  const supabase = await createClient(); // Connects to the database.
  const today = adelaideToday(); // Today's date.
  const since = new Date(Date.parse(`${today}T00:00:00Z`) - 56 * 86400000).toISOString().slice(0, 10); // The date 8 weeks ago.
  const [pay, lines, settings, logs, due] = await Promise.all([ // Reads five things at once:
    supabase.from("billing_staff_pay").select("employment, school_rate_cents, tertiary_rate_cents, admin_rate_cents, guaranteed_weekly_minutes").eq("account_id", viewer.id).maybeSingle(), // their pay settings and rates,
    supabase // their pay lines:
      .from("billing_pay_lines") // (from the pay lines table)
      .select("id, work_date, kind, work_kind, minutes, rate_cents, amount_cents, note, status") // with their details,
      .eq("account_id", viewer.id) // for this person,
      .gte("work_date", since) // from the last 8 weeks,
      .order("work_date", { ascending: false }), // newest first;
    supabase.rpc("billing_casual_min_on"), // whether the casual 2 hr minimum applies;
    supabase // their logged hours:
      .from("billing_hour_logs") // (from the hour logs table)
      .select("id, work_date, minutes, note, status, review_note, work_type, source") // with their details,
      .eq("account_id", viewer.id) // for this person,
      .gte("work_date", since) // from the last 8 weeks,
      .order("work_date", { ascending: false }), // newest first;
    supabase.rpc("billing_hours_due_by", { p_day: today }), // and when this week's hours are due.
  ]); // End of the reads.
  const dueBy = (due.data as string | null) ?? null; // When this week's hours are due (if known).
  const logRows = logs.data ?? []; // The logged hours.
  const rows = lines.data ?? []; // The pay lines.
  const p = pay.data; // The pay settings.
  // Tutors log tutoring work; only admin staff can log office admin.
  const canTutor = viewer.roles.includes("tutor") && (p?.school_rate_cents != null || p?.tertiary_rate_cents != null); // True if they can log tutoring work (a tutor with a tutoring rate).
  const canAdmin = viewer.roles.includes("admin") && p?.admin_rate_cents != null; // True if they can log office admin (an admin with an admin rate).

  return ( // Shows:
    <Page title="My pay" intro="Your pay from sessions and admin hours. CLG checks it in Xero before each pay run.">{/* a page titled "My pay", with a short explanation: */}
      <Card title="Your rates">{/* a card titled "Your rates": */}
        {p ? ( // if rates are set:
          <ul className="space-y-1 text-sm">{/* a list: */}
            <li>Employment: {p.employment.replace("_", "-")}</li>{/* employment type, */}
            {p.school_rate_cents != null && <li>School tutoring: {dollars(p.school_rate_cents)}/hr</li>}{/* the school tutoring rate, if set, */}
            {p.tertiary_rate_cents != null && <li>Tertiary and other tutoring: {dollars(p.tertiary_rate_cents)}/hr</li>}{/* the tertiary rate, if set, */}
            {p.admin_rate_cents != null && <li>Admin: {dollars(p.admin_rate_cents)}/hr</li>}{/* the admin rate, if set, */}
            {p.guaranteed_weekly_minutes != null && p.employment !== "casual" && ( // agreed weekly hours, for non-casual staff:
              <li>Agreed hours: {hours(p.guaranteed_weekly_minutes)} a week. If you work less in a pay period, CLG tops it up.</li> // with the top-up note.
            )}{/* End of agreed hours. */}
            {p.employment === "casual" && settings.data === true && <li>As a casual, you&apos;re paid at least 2 hr for each day you work.</li>}{/* The casual 2 hr minimum, if it applies. */}
          </ul> // End of the list.
        ) : ( // Otherwise:
          <Empty>CLG hasn&apos;t entered your pay rates yet.</Empty> // says rates aren't entered yet.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}
      {(canTutor || canAdmin) && ( // If they can log hours:
        <Card title="Log hours" description={`Work outside sessions, with a short description of what you did. Please log each pay week's hours by the day after the pay week ends${dueBy ? ` (this week's are due by ${plainDate(dueBy)})` : ""}. CLG approves them, then they're paid with your tutoring in the next pay run.`}>{/* a card titled "Log hours", with when they're due: */}
          <LogHoursForm today={today} canTutor={canTutor} canAdmin={canAdmin} />{/* the form for logging hours, */}
          {logRows.length > 0 && ( // if they've logged any:
            <div className="mt-6">{/* a block: */}
              <Table headings={["Day", "What", "Hours", ""]}>{/* a table with these headings: */}
                {logRows.map((h) => ( // for each log:
                  <tr key={h.id}>{/* a row: */}
                    <td>{plainDate(h.work_date)}</td>{/* the day, */}
                    <td>{/* a cell: */}
                      {h.source === "guaranteed" ? "Guaranteed hours top-up" : h.work_type === "tutoring" ? "Tutoring work" : "Office admin"}: {h.note}{/* the kind of work and the description, */}
                      {h.status === "declined" && h.review_note ? ` (declined: ${h.review_note})` : ""}{/* and the reason if declined. */}
                    </td>{/* End of the cell. */}
                    <td>{hours(h.minutes)}</td>{/* The hours, */}
                    <td>{/* a cell: */}
                      {h.status === "submitted" && h.source === "guaranteed" ? ( // a guaranteed top-up waiting:
                        "Waiting for approval" // "Waiting for approval",
                      ) : h.status === "submitted" ? ( // other hours waiting:
                        <form action={withdrawMyHours} className="flex items-center gap-2">{/* a form that takes them back: */}
                          <input type="hidden" name="id" value={h.id} />{/* which log (hidden), */}
                          <span>Waiting for approval</span>{/* "Waiting for approval", */}
                          <Button type="submit">Take back</Button>{/* and a "Take back" button. */}
                        </form> // End of the form.
                      ) : h.status === "approved" ? ( // Approved:
                        "Approved" // "Approved",
                      ) : ( // otherwise:
                        "Declined" // "Declined".
                      )}{/* End of the choice. */}
                    </td>{/* End of the cell. */}
                  </tr> // End of the row.
                ))}{/* End of the logs loop. */}
              </Table>{/* End of the table. */}
            </div> // End of the block.
          )}{/* End of the logs. */}
        </Card> // End of the card.
      )}{/* End of the hours part. */}
      <Card title="Last 8 weeks" description="If a time looks wrong, record the right end time on the session, or contact CLG.">{/* A card of the last 8 weeks' pay: */}
        {rows.length === 0 ? ( // if there's nothing:
          <Empty>No pay yet.</Empty> // says so.
        ) : ( // Otherwise:
          <Table headings={["Day", "What", "Hours", "Pay", ""]}>{/* a table with these headings: */}
            {rows.map((l) => ( // for each pay line:
              <tr key={l.id}>{/* a row: */}
                <td>{plainDate(l.work_date)}</td>{/* the day, */}
                <td>{/* a cell: */}
                  {KIND_LABELS[l.kind] ?? l.kind}{/* the kind of pay, */}
                  {l.note ? `: ${l.note}` : ""}{/* and the note, if any. */}
                </td>{/* End of the cell. */}
                <td>{hours(l.minutes)}</td>{/* The hours, */}
                <td>{dollars(l.amount_cents)}</td>{/* the pay, */}
                <td>{l.status === "sent" ? "Sent to payroll" : "Waiting"}</td>{/* and whether it's gone to payroll. */}
              </tr> // End of the row.
            ))}{/* End of the loop. */}
          </Table> // End of the table.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of MyPayPage.
