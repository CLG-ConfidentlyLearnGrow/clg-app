// Summary: the Student Success Program card in Families (Carla, 22 Nov
// 2026), for owner and Operations admins. Shows how many places are used
// and left, the requests waiting for a decision, places waiting for their
// deposit (with the 72 hour deadline), places secured by the deposit with
// the rest still being paid, and the students in the program. Each name
// links to Change a student's details, where the place is approved,
// declined, changed, withdrawn or ended, or a payment agreement recorded.
// The number of places and the days before a missed payment forfeits the
// place are changed here too.
//
import { Card, Empty, TextLink } from "@/components/ui"; // Shared page parts: card, empty line and text link.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { SspPlacesForm } from "./ssp-form"; // The form for the number of places.

// One student on the program list, as read from the database.
type Row = { // A row:
  student_id: string; // the student,
  status: "requested" | "approved" | "secured" | "enrolled"; // where they are up to,
  requested_at: string | null; // when the family asked,
  request_note: string | null; // the family's message,
  decline_reason: string | null; // why an earlier place was forfeited (if it was),
  decided_at: string | null; // when the place was approved,
  enrolled_at: string | null; // when they joined (everything paid),
  plan: string | null; // the payment plan,
  program_total_cents: number | null; // the program total,
  deposit_deadline: string | null; // when the deposit must be paid by,
  agreement_until: string | null; // a payment agreement's end date (if any),
  sessions_planned: number | null; // sessions planned,
  book_until: string | null; // the book-till date,
  student: { full_name: string } | null; // and the student's name.
}; // End of the row type.

// The places numbers from the database.
type Places = { spaces: number; used: number; places_left: number; waiting: number; deposit_hours: number; reminder_hours: number; forfeit_days: number }; // places, used, left, requests waiting, and the deadlines.

// The payment plan in words.
const PLAN_WORDS: Record<string, string> = { full: "paying in full", monthly: "paying monthly", weekly: "paying weekly" }; // Each plan and its words.

// Cents as "$1,234".
function money(cents: number): string { // Takes an amount in cents.
  return new Intl.NumberFormat("en-AU", { style: "currency", currency: "AUD" }).format(cents / 100); // Formats it as Australian dollars.
} // End of money.

// A date and time as "3:15 pm, 25 Nov" in Adelaide.
function shortTime(iso: string): string { // Takes a time.
  return new Intl.DateTimeFormat("en-AU", { hour: "numeric", minute: "2-digit", day: "numeric", month: "short", timeZone: "Australia/Adelaide" }).format(new Date(iso)); // Formats it.
} // End of shortTime.

// A date as "22 Nov 2026" in Adelaide.
function shortDate(iso: string): string { // Takes a date or time.
  return new Intl.DateTimeFormat("en-AU", { day: "numeric", month: "short", year: "numeric", timeZone: "Australia/Adelaide" }).format(new Date(iso.length === 10 ? `${iso}T12:00:00Z` : iso)); // Formats it (a plain date is read as midday, so it never slips a day).
} // End of shortDate.

// The card itself.
export async function SspSection() { // No inputs.
  const supabase = await createClient(); // Connects to the database.
  const [placesRes, rowsRes] = await Promise.all([ // Reads two things at once:
    supabase.rpc("ssp_places"), // the places numbers,
    supabase // and the students asking, waiting or in the program:
      .from("ssp_enrolments") // from the program list,
      .select("student_id, status, requested_at, request_note, decline_reason, decided_at, enrolled_at, plan, program_total_cents, deposit_deadline, agreement_until, sessions_planned, book_until, student:students(full_name)") // with their name and payment details,
      .in("status", ["requested", "approved", "secured", "enrolled"]) // only these four (uses the index),
      .order("requested_at", { ascending: true }), // longest waiting first.
  ]); // End of the reads.
  const places = ((placesRes.data ?? []) as Places[])[0] ?? null; // The numbers (or nothing if they could not be read).
  const rows = (rowsRes.data ?? []) as unknown as Row[]; // The students.
  const requests = rows.filter((r) => r.status === "requested"); // Requests waiting for a decision.
  const held = rows.filter((r) => r.status === "approved"); // Places waiting for their deposit.
  const secured = rows.filter((r) => r.status === "secured"); // Places secured, with the rest still being paid.
  const enrolled = rows.filter((r) => r.status === "enrolled"); // Students in the program.
  const link = (id: string) => `/admin?section=families&student=${id}#student-success-program`; // The link to the program part of the student's details card.
  const title = places ? `Student Success Program (${places.used} of ${places.spaces} places used, ${places.places_left} left)` : "Student Success Program"; // The card title with the numbers.

  return ( // Shows:
    <Card // a fold-up card:
      collapsible // can fold,
      defaultOpen={requests.length > 0} // open when requests are waiting,
      title={title} // its title,
      description="Families ask about the program from their dashboard. Approving a place makes the program invoices: the $500 deposit (due within 72 hours or the place is forfeited), then the rest in full, monthly or weekly. Payments are taken automatically, the family is reminded the day before each one, and a missed payment forfeits the place after the days set below unless a payment agreement is recorded. For a family paying weekly, sessions credited because the weekly invoice was not paid two weeks in a row also forfeit the place. A forfeited place puts the student back on the waiting list, and you get a notice. The program switches on once everything is paid. A place counts as used from approval, so places are never over-promised." // its help text.
    >{/* (end of the card's settings) */}
      <div className="space-y-5 text-sm">{/* a block: */}
        <section className="space-y-2">{/* the requests: */}
          <h3 className="font-semibold text-zinc-900">Requests waiting ({requests.length})</h3>{/* its heading, */}
          {requests.length === 0 ? <Empty>No requests waiting.</Empty> : ( // none, or the list:
            <ul className="divide-y divide-zinc-100">{/* a list: */}
              {requests.map((r) => ( // for each request:
                <li key={r.student_id} className="py-2">{/* a row: */}
                  <TextLink href={link(r.student_id)}>{r.student?.full_name ?? "Student"}</TextLink>{/* the name (opens their details to approve or decline), */}
                  <span className="text-zinc-600">{r.requested_at ? ` · asked ${shortDate(r.requested_at)}` : ""}</span>{/* when they asked, */}
                  {r.decline_reason?.startsWith("Place forfeited") && <p className="mt-1 text-amber-900">{r.decline_reason}</p>}{/* why an earlier place was forfeited (back on the waiting list), */}
                  {r.request_note && <p className="mt-1 text-zinc-700">{r.request_note}</p>}{/* and their message. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of the requests. */}
        </section>{/* End of the requests section. */}
        <section className="space-y-2">{/* the places waiting for their deposit: */}
          <h3 className="font-semibold text-zinc-900">Waiting for the deposit ({held.length})</h3>{/* its heading, */}
          {held.length === 0 ? <Empty>No places waiting for a deposit.</Empty> : ( // none, or the list:
            <ul className="divide-y divide-zinc-100">{/* a list: */}
              {held.map((r) => ( // for each place:
                <li key={r.student_id} className="py-2">{/* a row: */}
                  <TextLink href={link(r.student_id)}>{r.student?.full_name ?? "Student"}</TextLink>{/* the name, */}
                  <span className="text-zinc-600">{/* in grey: */}
                    {r.deposit_deadline ? ` · forfeited at ${shortTime(r.deposit_deadline)} if not paid` : ""}{/* the deadline, */}
                    {r.agreement_until ? ` · payment agreement until ${shortDate(r.agreement_until)}` : ""}{/* and any agreement. */}
                  </span>{/* End of the grey part. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of the held places. */}
        </section>{/* End of the held section. */}
        <section className="space-y-2">{/* the places secured, still being paid: */}
          <h3 className="font-semibold text-zinc-900">Deposit paid, paying the rest ({secured.length})</h3>{/* its heading, */}
          {secured.length === 0 ? <Empty>No places being paid off.</Empty> : ( // none, or the list:
            <ul className="divide-y divide-zinc-100">{/* a list: */}
              {secured.map((r) => ( // for each place:
                <li key={r.student_id} className="py-2">{/* a row: */}
                  <TextLink href={link(r.student_id)}>{r.student?.full_name ?? "Student"}</TextLink>{/* the name, */}
                  <span className="text-zinc-600">{/* in grey: */}
                    {r.program_total_cents ? ` · ${money(r.program_total_cents)}` : ""}{/* the total, */}
                    {r.plan ? `, ${PLAN_WORDS[r.plan] ?? r.plan}` : ""}{/* the plan, */}
                    {r.agreement_until ? ` · payment agreement until ${shortDate(r.agreement_until)}` : ""}{/* and any agreement. */}
                  </span>{/* End of the grey part. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of the secured places. */}
        </section>{/* End of the secured section. */}
        <section className="space-y-2">{/* the students in the program: */}
          <h3 className="font-semibold text-zinc-900">In the program ({enrolled.length})</h3>{/* its heading, */}
          {enrolled.length === 0 ? <Empty>No students in the program yet.</Empty> : ( // none, or the list:
            <ul className="divide-y divide-zinc-100">{/* a list: */}
              {enrolled.map((r) => ( // for each student:
                <li key={r.student_id} className="py-2">{/* a row: */}
                  <TextLink href={link(r.student_id)}>{r.student?.full_name ?? "Student"}</TextLink>{/* the name, */}
                  <span className="text-zinc-600">{/* in grey: */}
                    {r.enrolled_at ? ` · joined ${shortDate(r.enrolled_at)}` : ""}{/* when they joined, */}
                    {r.sessions_planned ? ` · ${r.sessions_planned} sessions` : ""}{/* sessions planned, */}
                    {r.book_until ? ` · until ${shortDate(r.book_until)}` : ""}{/* and the book-till date. */}
                  </span>{/* End of the grey part. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of the enrolled list. */}
        </section>{/* End of the enrolled section. */}
        {places && ( // Once the numbers are read:
          <section className="space-y-2 border-t border-zinc-200 pt-4">{/* the places form, with a line above: */}
            <h3 className="font-semibold text-zinc-900">Places and missed payments</h3>{/* its heading, */}
            <SspPlacesForm spaces={places.spaces} forfeitDays={places.forfeit_days} />{/* the form. */}
            <p className="text-xs text-zinc-500">The deposit must be paid within {places.deposit_hours} hours, with a reminder at {places.reminder_hours} hours. The deposit and plan fee amounts are the &quot;Student Success Program deposit&quot;, &quot;Monthly payment plan fee&quot; and &quot;Weekly payment plan fee&quot; prices in Billing, Prices and settings (Owner and Finance admins change them).</p>{/* the deadlines and where the amounts are set. */}
          </section> // End of the places section.
        )}{/* End of this part. */}
      </div>{/* End of the block. */}
    </Card> // End of the card.
  ); // End of what is shown.
} // End of SspSection.
