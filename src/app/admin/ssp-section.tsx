// Summary: the Student Success Program card in Families (Carla, 22 Nov
// 2026), for owner and Operations admins. Shows how many places are used
// and left, the requests waiting for a decision, places waiting for their
// deposit (with the due date, in amber when overdue), and the students in
// the program. Each name links to Change a student's details, where the
// place is approved, declined, changed, withdrawn or ended. The number of
// places and the days to pay are changed here too.
//
import { Card, Empty, TextLink } from "@/components/ui"; // Shared page parts: card, empty line and text link.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { SspPlacesForm } from "./ssp-form"; // The form for the number of places.

// One student on the program list, as read from the database.
type Row = { // A row:
  student_id: string; // the student,
  status: "requested" | "approved" | "enrolled"; // where they are up to,
  requested_at: string | null; // when the family asked,
  request_note: string | null; // the family's message,
  decided_at: string | null; // when the place was approved,
  enrolled_at: string | null; // when they joined (deposit paid),
  sessions_planned: number | null; // sessions planned,
  book_until: string | null; // the book-till date,
  student: { full_name: string } | null; // the student's name,
  invoice: { number: string; due_on: string; status: string } | null; // and the deposit invoice (if any).
}; // End of the row type.

// The places numbers from the database.
type Places = { spaces: number; used: number; places_left: number; waiting: number; deposit_due_days: number }; // places, used, left, requests waiting, days to pay.

// A date as "22 Nov 2026" in Adelaide.
function shortDate(iso: string): string { // Takes a date or time.
  return new Intl.DateTimeFormat("en-AU", { day: "numeric", month: "short", year: "numeric", timeZone: "Australia/Adelaide" }).format(new Date(iso.length === 10 ? `${iso}T12:00:00Z` : iso)); // Formats it (a plain date is read as midday, so it never slips a day).
} // End of shortDate.

// Today's date in Adelaide, as YYYY-MM-DD.
function adelaideToday(): string { // No inputs.
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Australia/Adelaide" }).format(new Date()); // The Canadian format happens to be YYYY-MM-DD.
} // End of adelaideToday.

// The card itself.
export async function SspSection() { // No inputs.
  const supabase = await createClient(); // Connects to the database.
  const [placesRes, rowsRes] = await Promise.all([ // Reads two things at once:
    supabase.rpc("ssp_places"), // the places numbers,
    supabase // and the students asking, waiting or in the program:
      .from("ssp_enrolments") // from the program list,
      .select("student_id, status, requested_at, request_note, decided_at, enrolled_at, sessions_planned, book_until, student:students(full_name), invoice:billing_invoices(number, due_on, status)") // with their name and deposit invoice,
      .in("status", ["requested", "approved", "enrolled"]) // only these three (uses the index),
      .order("requested_at", { ascending: true }), // longest waiting first.
  ]); // End of the reads.
  const places = ((placesRes.data ?? []) as Places[])[0] ?? null; // The numbers (or nothing if they could not be read).
  const rows = (rowsRes.data ?? []) as unknown as Row[]; // The students.
  const today = adelaideToday(); // Today, for overdue deposits.
  const requests = rows.filter((r) => r.status === "requested"); // Requests waiting for a decision.
  const held = rows.filter((r) => r.status === "approved"); // Places waiting for their deposit.
  const enrolled = rows.filter((r) => r.status === "enrolled"); // Students in the program.
  const link = (id: string) => `/admin?section=families&student=${id}#student-success-program`; // The link to the program part of the student's details card.
  const title = places ? `Student Success Program (${places.used} of ${places.spaces} places used, ${places.places_left} left)` : "Student Success Program"; // The card title with the numbers.

  return ( // Shows:
    <Card // a fold-up card:
      collapsible // can fold,
      defaultOpen={requests.length > 0} // open when requests are waiting,
      title={title} // its title,
      description="Families ask about the program from their dashboard. Approve a place to send the $500 deposit invoice; the student is in the program once it is paid. A place counts as used from approval, so places are never over-promised." // its help text.
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
              {held.map((r) => { // for each place:
                const overdue = !!r.invoice && r.invoice.due_on < today; // whether the deposit is overdue,
                return ( // shows:
                  <li key={r.student_id} className="py-2">{/* a row: */}
                    <TextLink href={link(r.student_id)}>{r.student?.full_name ?? "Student"}</TextLink>{/* the name, */}
                    {r.invoice && ( // and the invoice, if there is one:
                      <span className={overdue ? "text-amber-900" : "text-zinc-600"}>{/* amber when overdue: */}
                        {` · invoice ${r.invoice.number}, due ${shortDate(r.invoice.due_on)}${overdue ? " (overdue: contact the family, or withdraw the place)" : ""}`}{/* its number and due date. */}
                      </span> // End of the invoice words.
                    )}{/* End of this part. */}
                  </li> // End of the row.
                ); // End of the row.
              })}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of the held places. */}
        </section>{/* End of the held section. */}
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
            <h3 className="font-semibold text-zinc-900">Places and payment time</h3>{/* its heading, */}
            <SspPlacesForm spaces={places.spaces} dueDays={places.deposit_due_days} />{/* the form. */}
            <p className="text-xs text-zinc-500">The deposit amount is the &quot;Student Success Program deposit&quot; price in Billing, Prices and settings (Owner and Finance admins change it).</p>{/* where the amount is set. */}
          </section> // End of the places section.
        )}{/* End of this part. */}
      </div>{/* End of the block. */}
    </Card> // End of the card.
  ); // End of what is shown.
} // End of SspSection.
