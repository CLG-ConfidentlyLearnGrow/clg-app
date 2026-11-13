// Summary: the admin progress section: tracking measures, term reviews to check, family replies,
// overdue notes, students to check, and recent notes to spot-check.
//
import { Button, Card, Empty, Field, SubHeading, Table, TextLink } from "@/components/ui"; // The button, card, "nothing yet" note, input box, small heading, table and link style.
import { NOTE_OVERDUE_HOURS, STALLED_AFTER_SESSIONS, hoursAgo, minutesAndSeconds } from "@/lib/progress"; // Progress settings and helpers: overdue hours, stalled sessions, "hours ago" and minutes in words.
import { addDays, localToday, sessionWhen, shortDate } from "@/lib/scheduling"; // Date helpers.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { CheckTermReviewForm, TermReviewOfferForm } from "@/app/students/[id]/progress/forms"; // The forms for checking a term review and answering an offer.
import { dollars } from "@/lib/billing/money"; // Shows cents as dollars.
import { REVIEW_FIELDS, ReviewGoals, ReviewText, type Review } from "@/app/students/[id]/progress/term-review"; // The review fields, the review's goals table and words, and the review type.

// An offer of a paid term review, with the student's name and invoice number, for admins.
type AdminOffer = {
  id: string; // its id,
  student_id: string; // the student,
  period_label: string; // what it's the end of,
  period_ends_on: string; // the last day (and last day to answer),
  price_cents: number; // the price offered,
  answer: "waiting" | "yes" | "no"; // the answer so far,
  no_charge: boolean; // whether CLG gave it free,
  student: { full_name: string } | null; // the student's name,
  invoice: { number: string } | null; // and the invoice (if any, and if this admin may see invoices).
}; // End of the shape.

type AdminReview = Review & { student_id: string; student: { full_name: string } | null; tutor: { account: { full_name: string } | null } | null }; // A term review with the student's and tutor's names, for admins.

// One tutor's progress measures.
type Measure = {
  tutor_id: string; // the tutor,
  tutor_name: string | null; // their name (if still with CLG),
  sessions_held: number; // sessions held,
  sessions_noted: number; // sessions with a note,
  noted_within_24_hr: number; // notes written within 24 hr,
  notes: number; // notes in all,
  notes_with_reflection: number; // notes with a student reflection,
  median_writing_seconds: number | null; // the middle writing time (if timed),
  skills_moved_up: number; // and skills that moved up.
}; // End of the shape.
// A session still needing its note.
type DueNote = {
  session_id: string; // the session,
  student_id: string; // the student,
  student_name: string; // their name,
  tutor_name: string | null; // the tutor's name (if known),
  starts_at: string; // when it started,
  hours_since_end: number; // and hours since it ended.
}; // End of the shape.
// A student who may need a change of plan.
type ToCheck = {
  student_id: string; // the student,
  student_name: string; // their name,
  tutor_names: string | null; // their tutors' names,
  active_goals: number; // how many goals are active,
  last_note_on: string | null; // when the last note was,
  notes_since_movement: number; // notes since a skill last moved,
  notes_due: number; // and notes still due.
}; // End of the shape.
// A recent session note.
type RecentNote = {
  id: string; // its id,
  student_id: string; // the student,
  session_date: string; // the session date,
  went_well: string | null; // what went well,
  next_step: string | null; // the next step,
  home_tip: string | null; // the tip for home,
  student: { full_name: string } | null; // the student's name,
  tutor: { account: { full_name: string } | null } | null; // and the tutor's name.
}; // End of the shape.

const isDate = (v: unknown): v is string => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v); // True if a value is a date like 2026-11-11.
const share = (part: number, whole: number) => (whole > 0 ? `${Math.round((part / whole) * 100)}%` : "-"); // A part of a whole as a percentage (or "-" if there's no whole).

// Admin oversight for progress tracking: the measures the research brief
// names, overdue notes, students who may need a change of plan, and recent
// notes to spot-check. Reviewed weekly.
export async function ProgressSection({ from: fromParam, to: toParam }: { from: unknown; to: unknown }) {
  const today = localToday(); // Today's date.
  const to = isDate(toParam) ? toParam : today; // The last day: the one asked for, or today.
  const from = isDate(fromParam) ? fromParam : addDays(to, -27); // The first day: the one asked for, or 4 weeks before.

  const supabase = await createClient(); // Connects to the database.
  const [measuresRes, dueRes, checkRes, recentRes, reviewsRes, offersRes] = await Promise.all([ // Reads six things at once:
    supabase.rpc("progress_measures", { p_from: from, p_to: to }), // each tutor's measures for these dates,
    supabase.rpc("list_notes_due"), // notes still due,
    supabase.rpc("progress_students_to_check"), // students to check,
    supabase // the latest notes:
      .from("session_notes") // (from the session notes table)
      .select( // (with these fields:)
        "id, student_id, session_date, went_well, next_step, home_tip, student:students(full_name), tutor:tutor_profiles(account:accounts(full_name))", // the note's words and names,
      ) // (end of the fields)
      .neq("attendance", "absent") // only sessions the student came to,
      .order("created_at", { ascending: false }) // newest first,
      .limit(10), // at most 10;
    supabase // and term reviews:
      .from("term_reviews") // (from the term reviews table)
      .select(`${REVIEW_FIELDS}, student_id, student:students(full_name), tutor:tutor_profiles(account:accounts(full_name))`) // with names,
      .or("status.eq.submitted,family_replied_at.not.is.null") // waiting to be checked, or replied to,
      .order("term_ends_on", { ascending: false }) // latest term first,
      .limit(50), // at most 50;
    supabase // and offers of paid term reviews:
      .from("term_review_offers") // (from the offers table)
      .select("id, student_id, period_label, period_ends_on, price_cents, answer, no_charge, student:students(full_name), invoice:billing_invoices(number)") // with names and invoice numbers,
      .gte("period_ends_on", addDays(today, -28)) // still open, or ended in the last 4 weeks,
      .order("period_ends_on") // soonest first,
      .limit(100), // at most 100.
  ]); // End of the reads.
  const offers = (offersRes.data ?? []) as unknown as AdminOffer[]; // The offers.
  const reviews = (reviewsRes.data ?? []) as unknown as AdminReview[]; // The reviews.
  const toCheckReviews = reviews.filter((r) => r.status === "submitted"); // Reviews waiting to be checked.
  const replies = reviews.filter((r) => r.family_replied_at); // Reviews the family replied to.
  const measures = (measuresRes.data ?? []) as Measure[]; // The measures.
  const overdue = ((dueRes.data ?? []) as DueNote[]).filter((d) => d.hours_since_end >= NOTE_OVERDUE_HOURS); // Notes overdue.
  const toCheck = ((checkRes.data ?? []) as ToCheck[]).filter( // Students to check:
    (s) => s.active_goals === 0 || s.notes_since_movement >= STALLED_AFTER_SESSIONS, // no goals, or no skill moved for a while.
  ); // (end of the filter)
  const recent = (recentRes.data ?? []) as unknown as RecentNote[]; // The recent notes.

  const total = measures.reduce( // The totals across tutors:
    (t, m) => ({ // adding up each tutor's:
      held: t.held + m.sessions_held, // sessions held,
      noted: t.noted + m.sessions_noted, // sessions noted,
      onTime: t.onTime + m.noted_within_24_hr, // notes on time,
      notes: t.notes + m.notes, // notes,
      reflected: t.reflected + m.notes_with_reflection, // reflections,
      movedUp: t.movedUp + m.skills_moved_up, // and skills moved up.
    }), // (end of each tutor)
    { held: 0, noted: 0, onTime: 0, notes: 0, reflected: 0, movedUp: 0 }, // starting from zero.
  ); // (end of the totals)

  return ( // Shows:
    <>{/* (a group:) */}
      <Card // a card:
        title="How progress tracking is going" // titled "How progress tracking is going",
        description="The measures from the research brief. The pilot aims for every session to have a note within 24 hr, written in under 3 minutes." // with the pilot's aims.
      >{/* (end of the card's settings) */}
        <form method="get" className="mb-5 flex flex-wrap items-end gap-3">{/* A date form (sends the dates in the address): */}
          <input type="hidden" name="section" value="progress" />{/* stays on the progress section, */}
          <div className="w-40">{/* a narrow block: */}
            <Field label="From" name="from" type="date" defaultValue={from} max={today} />{/* the first day. */}
          </div>{/* End of the block. */}
          <div className="w-40">{/* A narrow block: */}
            <Field label="To" name="to" type="date" defaultValue={to} max={today} />{/* the last day. */}
          </div>{/* End of the block. */}
          <Button type="submit">Show</Button>{/* The "Show" button. */}
        </form>{/* End of the form. */}
        {measures.length === 0 ? ( // If there's nothing in these dates:
          <Empty>No sessions or notes between {shortDate(from)} and {shortDate(to)}.</Empty> // says so.
        ) : ( // Otherwise:
          <>{/* (a group:) */}
            <ul className="mb-5 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">{/* a grid of figures: */}
              <Stat label="Sessions with a note" value={share(total.noted, total.held)} />{/* sessions with a note, */}
              <Stat label="Noted within 24 hr" value={share(total.onTime, total.held)} />{/* noted within 24 hr, */}
              <Stat label="Notes with a reflection" value={share(total.reflected, total.notes)} />{/* notes with a reflection, */}
              <Stat label="Skills moved up" value={String(total.movedUp)} />{/* skills moved up. */}
            </ul>{/* End of the grid. */}
            <Table headings={["Tutor", "Sessions", "With note", "Within 24 hr", "Reflections", "Time to write", "Skills up"]}>{/* A table with these headings: */}
              {measures.map((m) => ( // for each tutor:
                <tr key={m.tutor_id}>{/* a row: */}
                  <td className="font-medium">{m.tutor_name ?? "Former tutor"}</td>{/* their name, */}
                  <td>{m.sessions_held}</td>{/* sessions, */}
                  <td>{share(m.sessions_noted, m.sessions_held)}</td>{/* with a note, */}
                  <td>{share(m.noted_within_24_hr, m.sessions_held)}</td>{/* within 24 hr, */}
                  <td>{share(m.notes_with_reflection, m.notes)}</td>{/* reflections, */}
                  <td>{minutesAndSeconds(m.median_writing_seconds)}</td>{/* time to write, */}
                  <td>{m.skills_moved_up}</td>{/* skills up. */}
                </tr> // End of the row.
              ))}{/* End of the loop. */}
            </Table>{/* End of the table. */}
            <p className="mt-3 text-xs text-zinc-500">{/* A small grey note: */}
              Sessions counts sessions marked done in the app. Time to write is the middle value of notes written with
              the timer. Families and tutors never see these figures.{/* what the figures mean, and who sees them. */}
            </p>{/* End of the note. */}
          </> // (end of the group)
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}

      <Card // A card:
        collapsible // that can be opened and closed,
        title="Paid term review offers" // titled "Paid term review offers",
        description="Families are offered a review 4 weeks before a term, semester or booking ends, at the price under Billing > Prices. Record an answer here if a family tells you directly." // with how offers work.
      >{/* (end of the card's settings) */}
        {offers.length === 0 ? ( // If there are none:
          <Empty>No offers right now. Offers start once the term review price is set and in use.</Empty> // says so.
        ) : ( // Otherwise:
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {offers.map((o) => ( // for each offer:
              <li key={o.id} className="py-3 first:pt-0">{/* a list item: */}
                <p className="font-medium">{/* a line: */}
                  <TextLink href={`/students/${o.student_id}/progress`}>{o.student?.full_name ?? "Student"}</TextLink>{/* a link to the student's progress, */}
                  <span className="font-normal text-zinc-600">{/* grey details: */}
                    {" "}· {o.period_label} · ends {shortDate(o.period_ends_on)} · {dollars(o.price_cents)}{/* the period, end date and price, */}
                  </span>{/* End of the details. */}
                </p>{/* End of the line. */}
                <p className="mt-1 text-zinc-700">{/* a line with the answer: */}
                  {o.answer === "waiting" && "Waiting for the family."}{/* waiting, */}
                  {o.answer === "no" && "The family said no thanks."}{/* no, */}
                  {o.answer === "yes" && (o.no_charge ? "Booked at no charge." : o.invoice ? `Booked, on invoice ${o.invoice.number}.` : "Booked. No invoice yet: bill it by hand if the family has no billing account.")}{/* or yes, and how it's paid. */}
                </p>{/* End of the line. */}
                {o.answer !== "yes" && o.period_ends_on >= today && ( // still open and not booked:
                  <div className="mt-3 max-w-sm">{/* a narrow block: */}
                    <TermReviewOfferForm studentId={o.student_id} offerId={o.id} staff />{/* the answer form, with "no charge". */}
                  </div> // End of the block.
                )}{/* End of the form. */}
              </li> // End of the list item.
            ))}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}

      <Card // A card:
        title="Term reviews to check" // titled "Term reviews to check",
        description="Check each review before the family sees it: is it written to the family, honest about progress, and clear about next term?" // with what to check for.
      >{/* (end of the card's settings) */}
        {toCheckReviews.length === 0 ? ( // If none are waiting:
          <Empty>None waiting.</Empty> // says so.
        ) : ( // Otherwise:
          <ul className="space-y-8">{/* a list: */}
            {toCheckReviews.map((r) => ( // for each review:
              <li key={r.id}>{/* a list item: */}
                <p className="mb-3 font-medium">{/* a line: */}
                  <TextLink href={`/students/${r.student_id}/progress`}>{r.student?.full_name ?? "Student"}</TextLink>{/* a link to the student's progress, */}
                  <span className="font-normal text-zinc-600">{/* grey details: */}
                    {" "}{/* (a space) */}
                    · {r.term_label}{/* the term, */}
                    {r.tutor?.account?.full_name && ` · ${r.tutor.account.full_name}`}{/* and the tutor. */}
                  </span>{/* End of the details. */}
                </p>{/* End of the line. */}
                <ReviewGoals reviewId={r.id} />{/* The goals table, */}
                <div className="my-4">{/* a block: */}
                  <ReviewText review={r} />{/* the review's words. */}
                </div>{/* End of the block. */}
                <CheckTermReviewForm reviewId={r.id} />{/* The approve or return form. */}
              </li> // End of the list item.
            ))}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}

      {replies.length > 0 && ( // If families have replied:
        <Card collapsible title="Replies to term reviews">{/* a card that can be opened and closed: */}
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {replies.map((r) => ( // for each reply:
              <li key={r.id} className="py-3 first:pt-0">{/* a list item: */}
                <p className="font-medium">{/* a line: */}
                  <TextLink href={`/students/${r.student_id}/progress`}>{r.student?.full_name ?? "Student"}</TextLink>{/* a link to the student's progress, */}
                  <span className="font-normal text-zinc-600"> · {r.term_label}</span>{/* the term, */}
                  {r.wants_call && <span className="ml-2 text-xs font-semibold text-red-700">Wants a call</span>}{/* and a red mark if they want a call. */}
                </p>{/* End of the line. */}
                {r.family_reply && <p className="mt-1 whitespace-pre-line">{r.family_reply}</p>}{/* Their reply, keeping line breaks. */}
              </li> // End of the list item.
            ))}{/* End of the loop. */}
          </ul>{/* End of the list. */}
        </Card> // End of the card.
      )}{/* End of that part. */}

      <Card title={`Notes overdue (${NOTE_OVERDUE_HOURS} hr or more)`}>{/* A card of overdue notes: */}
        {overdue.length === 0 ? ( // if none:
          <Empty>None. Every recent session has its note.</Empty> // says so.
        ) : ( // Otherwise:
          <Table headings={["Student", "Tutor", "Session", "Ended"]}>{/* a table with these headings: */}
            {overdue.map((d) => ( // for each session:
              <tr key={d.session_id}>{/* a row: */}
                <td className="font-medium">{/* a cell: */}
                  <TextLink href={`/students/${d.student_id}/progress?session=${d.session_id}`}>{d.student_name}</TextLink>{/* a link to write the note. */}
                </td>{/* End of the cell. */}
                <td>{d.tutor_name ?? "-"}</td>{/* The tutor, */}
                <td>{sessionWhen(d.starts_at)}</td>{/* when the session was, */}
                <td>{hoursAgo(d.hours_since_end)}</td>{/* and how long ago it ended. */}
              </tr> // End of the row.
            ))}{/* End of the loop. */}
          </Table> // End of the table.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}

      <Card // A card:
        title="Students to check" // titled "Students to check",
        description={`Students with no goals yet, or whose skills haven't moved in ${STALLED_AFTER_SESSIONS} or more sessions. They may need a change of goals, approach or tutor.`} // with what puts a student here.
      >{/* (end of the card's settings) */}
        {toCheck.length === 0 ? ( // If none:
          <Empty>Nobody right now.</Empty> // says so.
        ) : ( // Otherwise:
          <Table headings={["Student", "Tutor", "Why", "Last note"]}>{/* a table with these headings: */}
            {toCheck.map((s) => ( // for each student:
              <tr key={s.student_id}>{/* a row: */}
                <td className="font-medium">{/* a cell: */}
                  <TextLink href={`/students/${s.student_id}/progress`}>{s.student_name}</TextLink>{/* a link to their progress. */}
                </td>{/* End of the cell. */}
                <td>{s.tutor_names ?? "-"}</td>{/* Their tutors, */}
                <td>{/* a cell: */}
                  {s.active_goals === 0 // if no goals:
                    ? "No goals set" // "No goals set",
                    : `No skill moved in ${s.notes_since_movement} sessions`}{/* otherwise how many sessions without movement. */}
                </td>{/* End of the cell. */}
                <td>{s.last_note_on ? shortDate(s.last_note_on) : "None yet"}</td>{/* When the last note was. */}
              </tr> // End of the row.
            ))}{/* End of the loop. */}
          </Table> // End of the table.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}

      <Card // A card:
        collapsible // that can be opened and closed,
        defaultOpen={false} // closed to start,
        title="Recent notes to spot-check" // titled "Recent notes to spot-check",
        description="Is the next step specific, and written to the student? Is the tip for home a small habit?" // with what to look for.
      >{/* (end of the card's settings) */}
        {recent.length === 0 ? ( // If no notes:
          <Empty>No notes yet.</Empty> // says so.
        ) : ( // Otherwise:
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {recent.map((n) => ( // for each note:
              <li key={n.id} className="py-3 first:pt-0">{/* a list item: */}
                <p className="font-medium">{/* a line: */}
                  <TextLink href={`/students/${n.student_id}/progress`}>{n.student?.full_name ?? "Student"}</TextLink>{/* a link to the student's progress, */}
                  <span className="font-normal text-zinc-600">{/* grey details: */}
                    {" "}{/* (a space) */}
                    · {shortDate(n.session_date)}{/* the session date, */}
                    {n.tutor?.account?.full_name && ` · ${n.tutor.account.full_name}`}{/* and the tutor. */}
                  </span>{/* End of the details. */}
                </p>{/* End of the line. */}
                {n.went_well && <p>Went well: {n.went_well}</p>}{/* What went well, */}
                {n.next_step && <p>Next step: {n.next_step}</p>}{/* the next step, */}
                {n.home_tip && <p>Try at home: {n.home_tip}</p>}{/* and the tip for home. */}
              </li> // End of the list item.
            ))}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of the choice. */}
        <SubHeading>What good looks like</SubHeading>{/* A small heading, */}
        <p className="text-sm text-zinc-600">{/* a grey note: */}
          Feedback works when it says where the student is going, how they are going, and what to do next (EEF,
          Feedback). Parents help most with habits like planning and practice, not re-teaching (EEF, Parental
          engagement).{/* what good feedback looks like, from the EEF. */}
        </p>{/* End of the note. */}
      </Card>{/* End of the card. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of ProgressSection.

// One figure in the grid: a big number with a label.
function Stat({ label, value }: { label: string; value: string }) {
  return ( // Shows:
    <li className="rounded-xl bg-zinc-50 px-4 py-3">{/* a soft grey box: */}
      <span className="block text-xl font-semibold">{value}</span>{/* the number, */}
      <span className="text-xs text-zinc-600">{label}</span>{/* and its label. */}
    </li> // End of the box.
  ); // End of what's shown.
} // End of Stat.
