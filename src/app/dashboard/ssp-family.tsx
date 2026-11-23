// Summary: the Student Success Program box for a family (Carla, 22 Nov
// 2026), shown under each child on the family dashboard, and on an adult
// learner's own dashboard. It explains the program and shows where the
// student is up to: ask about it (a tick box), request waiting (cancel it),
// place offered (the $500 deposit secures it within 72 hours), deposit paid
// and the rest being paid, in the program, or a place forfeited. Only the
// person who pays sees the amounts, dates and the Billing link. The database
// decides what this person may see and do.
//
import { Card, TextLink } from "@/components/ui"; // A card and a text link.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { SspAskForm, SspCancelForm } from "./ssp-family-forms"; // The family's forms.

// What the database gives back about the student's place.
type Status = { // The row:
  status: string | null; // where they are up to (nothing if never asked),
  can_ask: boolean; // whether this person can ask or cancel,
  requested_at: string | null; // when they asked,
  decline_reason: string | null; // any reason CLG gave,
  enrolled_at: string | null; // when they joined,
  is_payer: boolean; // whether this person pays for the family,
  plan: string | null; // the payment plan (payers only),
  total_cents: number | null; // the program total with any plan fees (payers only),
  paid_cents: number | null; // how much is paid (payers only),
  deposit_deadline: string | null; // when the deposit must be paid by (payers only),
  next_due_on: string | null; // the next payment's due date (payers only),
  next_amount_cents: number | null; // and its amount (payers only).
}; // End of the type.

// A date as "22 November 2026" in Adelaide.
function longDate(iso: string): string { // Takes a date or time.
  return new Intl.DateTimeFormat("en-AU", { day: "numeric", month: "long", year: "numeric", timeZone: "Australia/Adelaide" }).format(new Date(iso.length === 10 ? `${iso}T12:00:00Z` : iso)); // Formats it (a plain date is read as midday, so it never slips a day).
} // End of longDate.

// A time as "3:15 pm on 25 November" in Adelaide.
function longTime(iso: string): string { // Takes a time.
  const f = (o: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat("en-AU", { ...o, timeZone: "Australia/Adelaide" }).format(new Date(iso)); // Formats one part in Adelaide time.
  return `${f({ hour: "numeric", minute: "2-digit" })} on ${f({ day: "numeric", month: "long" })}`; // The time, then the day.
} // End of longTime.

// Cents as "$1,234.00".
function money(cents: number): string { // Takes an amount in cents.
  return new Intl.NumberFormat("en-AU", { style: "currency", currency: "AUD" }).format(cents / 100); // Formats it as Australian dollars.
} // End of money.

// The payment plan in words.
const PLAN_WORDS: Record<string, string> = { full: "paid in full", monthly: "paid monthly", weekly: "paid weekly" }; // Each plan and its words.

// The box for one student.
export async function SspFamilyBox({ studentId, name, self = false, inCard = false }: { studentId: string; name: string; self?: boolean; inCard?: boolean }) { // Takes the student, their first name, whether the reader is the student, and whether to wrap it in its own card.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("ssp_family_status", { p_student: studentId }); // Reads where they are up to (nothing if this person may not see it).
  const s = ((data ?? []) as Status[])[0]; // The one row.
  if (!s) return null; // Not theirs to see: shows nothing.
  if (!s.status && !s.can_ask) return null; // Never asked, and this person cannot ask: shows nothing.
  const who = self ? "you" : name; // "you" for an adult learner, otherwise the student's name.
  const payLink = s.is_payer ? <TextLink href="/billing">See the payments in Billing</TextLink> : "The person who pays for your family's sessions can see the payments in Billing."; // Where to see the payments.
  const progress = s.is_payer && s.total_cents ? ( // For payers, how the payments are going:
    <> {money(s.paid_cents ?? 0)} of {money(s.total_cents)} paid{s.plan ? `, ${PLAN_WORDS[s.plan] ?? s.plan}` : ""}.{s.next_due_on && s.next_amount_cents ? ` Next payment ${money(s.next_amount_cents)} on ${longDate(s.next_due_on)}.` : ""}</> // how much is paid of the total, the plan, and the next payment
  ) : null; // (nothing for others)
  const about = ( // The plain explanation of the program:
    <p className="text-zinc-600">{/* grey words: */}
      The Student Success Program is a planned run of sessions with a study plan, each term review included, and priority when CLG finds a tutor. Places are limited. CLG looks at each request. If a place is offered, a $500 deposit secures it, and the rest is paid in full, monthly or weekly.{/* what it is. */}
    </p> // End of the words.
  ); // End of the explanation.
  const box = ( // The box:
    <div className="space-y-3 text-sm">{/* a block: */}
      {s.status === "enrolled" && ( // In the program:
        <p className="rounded-lg bg-violet-50 p-3 text-violet-900">{/* a violet box: */}
          {self ? "You are" : `${name} is`} in the Student Success Program{s.enrolled_at ? ` (since ${longDate(s.enrolled_at)})` : ""}.{/* that they are in it, and since when. */}
        </p> // End of the box.
      )}{/* End of this part. */}
      {s.status === "approved" && ( // A place offered, waiting for the deposit:
        <p className="rounded-lg bg-amber-50 p-3 text-amber-900">{/* an amber box: */}
          CLG has offered {who} a place in the Student Success Program. The $500 deposit secures the place and needs to be paid{s.deposit_deadline ? ` by ${longTime(s.deposit_deadline)}` : " within 72 hours"}, or the place will be forfeited. It is taken from your saved card or bank account.{progress}{" "}{/* the offer, deadline (payers only) and progress, */}
          {payLink}{/* where to see it. */}
        </p> // End of the box.
      )}{/* End of this part. */}
      {s.status === "secured" && ( // Deposit paid, the rest being paid:
        <p className="rounded-lg bg-sky-50 p-3 text-sky-900">{/* a blue box: */}
          {self ? "Your" : `${name}'s`} place in the Student Success Program is secured. The program switches on once everything is paid. Each payment is taken from your saved card or bank account on its due date, with a reminder the day before.{progress}{" "}{/* that the place is secured, and progress (payers only), */}
          {payLink}{/* where to see it. */}
        </p> // End of the box.
      )}{/* End of this part. */}
      {s.status === "requested" && ( // A request waiting:
        <>{/* (a group) */}
          {s.decline_reason?.startsWith("Place forfeited") && <p>The last place was forfeited: {s.decline_reason.replace(/^Place forfeited because /, "")}</p>}{/* why the last place was lost (if it was), */}
          <p>{s.decline_reason?.startsWith("Place forfeited") ? `${self ? "You are" : `${name} is`} back on the waiting list` : `You asked about the Student Success Program${s.requested_at ? ` on ${longDate(s.requested_at)}` : ""}`}. CLG will look at your request and let you know.</p>{/* where they are and what happens next, */}
          {s.can_ask && <SspCancelForm studentId={studentId} />}{/* and the cancel button. */}
        </>  // End of the group.
      )}{/* End of this part. */}
      {(!s.status || ["declined", "withdrawn", "forfeited", "left"].includes(s.status)) && s.can_ask && ( // No request or place now:
        <>{/* (a group) */}
          {s.status === "declined" && <p>CLG was not able to offer a place last time{s.decline_reason ? `: ${s.decline_reason}` : "."} You are welcome to ask again.</p>}{/* the last answer, */}
          {s.status === "forfeited" && <p>The last place offered was forfeited because a payment was not made in time. You are welcome to ask again, or to contact CLG.</p>}{/* that the place was forfeited (older records only), */}
          {s.status === "left" && <p>{self ? "You have" : `${name} has`} left the Student Success Program. You are welcome to ask again.</p>}{/* that they left, */}
          {about}{/* what the program is, */}
          <SspAskForm studentId={studentId} name={self ? "myself" : name} />{/* and the tick box. */}
        </>  // End of the group.
      )}{/* End of this part. */}
    </div> // End of the block.
  ); // End of the box.
  return inCard ? ( // Wrapped in its own fold-up card when asked (so nothing at all shows when there is nothing to show):
    <Card title="Student Success Program" collapsible defaultOpen={s.status === "approved" || s.status === "secured"}>{/* open while payments are being made, */}
      {box}{/* with the box inside. */}
    </Card> // End of the card.
  ) : box; // Otherwise just the box.
} // End of SspFamilyBox.
