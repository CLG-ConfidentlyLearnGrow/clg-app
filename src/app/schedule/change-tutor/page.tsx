// Summary: the "Change tutor" page under Sessions (scheduling module, Carla
// 15 Nov 2026). A matching admin picks a student's sessions with one tutor in
// one subject, chooses the date to change from and (for one weekly pattern)
// the day and time, filled in with the current ones, sees which tutors could
// take over (and anything in the way), and sends the change for the new
// tutor and the family to confirm. Nothing moves until both say yes. The
// same sessions are kept, so paid sessions stay paid. Waiting changes are
// listed with a way to withdraw them. The database checks every rule; this
// page only shows what it says.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { proposeTutorChange, withdrawTutorChange } from "@/app/actions/change-tutor"; // The server actions that send and withdraw a change.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { BackButton, Button, Card, Empty, Field, Select, Table, TextLink } from "@/components/ui"; // Shared page parts.
import { FRONT_DESK, requireAdminLevel } from "@/lib/auth"; // The matching admin levels, and the guard for them.
import { sessionsHref } from "@/lib/dashboard-menu"; // The address of the admin Sessions tab.
import { WEEKDAY_NAMES, localToday, sessionWhen, shortDate } from "@/lib/scheduling"; // Weekday names and date helpers (today, session times and short dates).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// One student, tutor and subject with upcoming sessions.
type Pair = { student_id: string; student_name: string; tutor_id: string; tutor_name: string; subject: string; upcoming_sessions: number; paid_sessions: number; first_session: string; last_session: string; weekly_bookings: number }; // as the database gives it.
// One tutor who could take over, and what's in the way.
type Candidate = { tutor_id: string; full_name: string; clashes: number; first_clash: string | null; missing_library: string | null; booked_minutes: number; added_minutes: number; max_weekly_hours: number | null; at_max: boolean; teaches_sibling: boolean }; // as the database gives it.
// The current day and time of the sessions that would move.
type Pattern = { weekday: number; start_time: string; minutes: number; same_pattern: boolean }; // as the database gives it.
// One change sent for confirmation.
type Offer = { id: string; status: string; student_name: string; subject: string; from_tutor_name: string | null; to_tutor_name: string | null; from_date: string; sessions: number; old_time: string; new_time: string; tutor_ok: boolean; family_ok: boolean; declined_by_role: string | null; answer_note: string | null; closed_note: string | null; reason: string; created_at: string }; // as the database gives it.
// The words for each state of a sent change.
const OFFER_STATUS: Record<string, string> = { waiting: "Waiting", confirmed: "Confirmed and made", declined: "Declined", withdrawn: "Withdrawn", failed: "Could not be made" }; // waiting, confirmed, declined, withdrawn, failed.
// Start times every 15 minutes from 7am to 9pm, as "HH:MM".
const START_TIMES = Array.from({ length: 57 }, (_, i) => { const m = 7 * 60 + i * 15; return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`; }); // 7:00, 7:15 ... 21:00.
// A "HH:MM" time in words, e.g. "4:15pm".
function timeWords(t: string): string { // Takes the time.
  const [h, m] = t.split(":").map(Number); // The hour and minutes.
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, "0")}${h < 12 ? "am" : "pm"}`; // e.g. 4:15pm.
} // End of timeWords.

// One past change.
type Change = { id: string; student_name: string | null; from_tutor_name: string | null; to_tutor_name: string | null; subject: string; from_date: string; sessions_moved: number; reason: string; changed_by_name: string | null; changed_at: string }; // as the database gives it.

// Reads one value from the address (the first, if there are several).
function one(v: string | string[] | undefined): string { // Takes the value.
  return (Array.isArray(v) ? v[0] : v) ?? ""; // The first value, or empty.
} // End of one.

// Whether a value looks like a database id.
const isId = (v: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v); // true for an id.

// What stands in the way of one candidate, in plain words (empty when nothing does).
function blockers(c: Candidate): string[] { // Takes the candidate.
  const out: string[] = []; // The list of problems.
  if (c.clashes > 0) out.push(`${c.clashes} clash${c.clashes === 1 ? "" : "es"}${c.first_clash ? `, first ${sessionWhen(c.first_clash)}` : ""}`); // clashing sessions,
  if (c.missing_library) out.push(`does not teach at ${c.missing_library}`); // a library they don't teach at,
  if (c.at_max) out.push(`past their ${c.max_weekly_hours} hr a week`); // going past their hours.
  return out; // The problems.
} // End of blockers.

// Shows the page.
export default async function ChangeTutorPage({ searchParams }: PageProps<"/schedule/change-tutor">) { // The page itself (reads the address's settings).
  const viewer = await requireAdminLevel(FRONT_DESK); // Only matching admins with two-step sign-in (others are sent away).
  const params = await searchParams; // The address's settings.
  const studentId = isId(one(params.student)) ? one(params.student) : ""; // The student chosen (only a real id).
  const tutorId = isId(one(params.tutor)) ? one(params.tutor) : ""; // The current tutor chosen (only a real id).
  const subject = one(params.subject).slice(0, 100); // The subject chosen (up to 100 letters).
  const search = one(params.q).slice(0, 100); // The search words (up to 100 letters).
  const today = localToday(); // Today's date.
  const from = /^\d{4}-\d{2}-\d{2}$/.test(one(params.from)) && one(params.from) >= today ? one(params.from) : today; // The change date (today or later; today if not given).
  const chosen = Boolean(studentId && tutorId && subject); // Whether a student, tutor and subject are chosen.

  const supabase = await createClient(); // Connects to the database.
  const patternRes = chosen ? await supabase.rpc("tutor_change_pattern", { p_student: studentId, p_from_tutor: tutorId, p_subject: subject, p_from: from }) : { data: [] }; // the current day and time (once chosen),
  const pattern = ((patternRes.data ?? []) as Pattern[])[0] ?? null; // (one row, or none)
  const canRetime = Boolean(pattern?.same_pattern); // Whether the day and time can be changed (one weekly pattern).
  const askedDay = Number(one(params.weekday)); // The day in the address, if any.
  const weekday = canRetime ? (askedDay >= 1 && askedDay <= 7 ? askedDay : pattern!.weekday) : null; // The day to use: asked, or the current one (only for one pattern).
  const askedStart = one(params.start); // The time in the address, if any.
  const start = canRetime ? (START_TIMES.includes(askedStart) ? askedStart : pattern!.start_time.slice(0, 5)) : null; // The time to use: asked, or the current one.
  const [pairsRes, candRes, changesRes, offersRes] = await Promise.all([ // Reads four things at once:
    supabase.rpc("tutor_change_pairs", { p_student: studentId || null, p_search: search || null }), // the students with sessions booked,
    chosen ? supabase.rpc("tutor_change_candidates", { p_student: studentId, p_from_tutor: tutorId, p_subject: subject, p_from: from, p_weekday: weekday, p_start: start }) : Promise.resolve({ data: [] }), // the tutors who could take over, checked at the chosen time (once chosen),
    supabase.rpc("recent_tutor_changes", { p_student: studentId || null }), // the last changes made,
    supabase.rpc("tutor_change_offers_list", { p_student: studentId || null }), // and the changes sent for confirmation.
  ]); // End of the reads.
  const offers = (offersRes.data ?? []) as Offer[]; // The changes sent for confirmation.
  const waiting = offers.filter((o) => o.status === "waiting"); // Those still waiting.
  if (pairsRes.error) redirect(sessionsHref("admin")); // Not allowed (or a problem): back to Sessions.
  const pairs = (pairsRes.data ?? []) as Pair[]; // The students with sessions booked.
  const candidates = (candRes.data ?? []) as Candidate[]; // The tutors who could take over.
  const free = candidates.filter((c) => blockers(c).length === 0); // Those with nothing in the way.
  const changes = (changesRes.data ?? []) as Change[]; // The last changes.
  const pair = pairs.find((p) => p.student_id === studentId && p.tutor_id === tutorId && p.subject.toLowerCase() === subject.toLowerCase()); // The chosen one, if it still has sessions.
  const pick = (p: Pair) => `/schedule/change-tutor?student=${p.student_id}&tutor=${p.tutor_id}&subject=${encodeURIComponent(p.subject)}&from=${from}`; // The address that chooses a row (with the current day and time to start).
  const retimed = canRetime && (weekday !== pattern!.weekday || start !== pattern!.start_time.slice(0, 5)); // Whether a different day or time is chosen.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="sessions">{/* the admin dashboard, on Sessions: */}
      <div className="space-y-6">{/* the page's cards, spaced out: */}
        <p><BackButton href={sessionsHref("admin", "bookings")}>Back to bookings</BackButton></p>{/* a button back to bookings, */}

        {waiting.length > 0 && ( // Changes waiting for confirmation:
          <Card title={`Waiting for confirmation (${waiting.length})`} description="Sent to the new tutor and the family. Nothing moves until both have confirmed.">{/* a card: */}
            <ul className="space-y-4 text-sm">{/* the list: */}
              {waiting.map((o) => ( // for each waiting change:
                <li key={o.id} className="rounded-xl border border-zinc-200 p-4">{/* a box: */}
                  <p className="font-semibold">{o.student_name}, {o.subject}: {o.from_tutor_name ?? "former tutor"} to {o.to_tutor_name ?? "former tutor"} from {shortDate(o.from_date)}</p>{/* who, what and from when, */}
                  <p className="mt-1">{o.new_time ? `New time: ${o.new_time}${o.old_time ? ` (was ${o.old_time})` : ""}. ` : "Same days and times. "}New tutor: {o.tutor_ok ? "confirmed" : "waiting"}. Family: {o.family_ok ? "confirmed" : "waiting"}. Sent {shortDate(o.created_at)}.</p>{/* the time, who has confirmed, and when sent, */}
                  <div className="mt-3 max-w-md">{/* the withdraw form: */}
                    <ActionForm action={withdrawTutorChange} submitLabel="Withdraw">{/* withdrawing it: */}
                      <input type="hidden" name="id" value={o.id} />{/* (which change) */}
                      <Field label="Note (optional)" name="note" maxLength={1000} placeholder="e.g. Sorted another way" />{/* an optional note. */}
                    </ActionForm>{/* End of the form. */}
                  </div>{/* End of the form area. */}
                </li> // End of the box.
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
          </Card> // End of the waiting card.
        )}{/* End of the waiting part. */}

        <Card title="Change tutor on booked sessions" description="Moves a student's upcoming sessions in one subject to another tutor, from a date you choose, and can change the day and time too. The new tutor and the family confirm first. Places and Teams links stay the same, and sessions already paid for stay paid.">{/* the first step: */}
          <form method="get" className="mb-4 flex flex-wrap items-end gap-3">{/* a search form: */}
            <div className="min-w-56 flex-1"><Field label="Search by student or tutor" name="q" defaultValue={search} maxLength={100} /></div>{/* the search box, */}
            <Button type="submit">Search</Button>{/* the search button. */}
          </form>{/* End of the search form. */}
          {studentId && <p className="mb-3 text-sm">Showing one student. <TextLink href="/schedule/change-tutor">Show everyone</TextLink></p>}{/* a way back to everyone, when filtered, */}
          {pairs.length === 0 ? ( // nothing booked:
            <Empty>No upcoming sessions found.</Empty> // says so,
          ) : ( // otherwise a table:
            <Table headings={["Student", "Tutor now", "Subject", "Booked", "Paid", "First to last", ""]}>{/* with these headings: */}
              {pairs.map((p) => ( // for each row:
                <tr key={`${p.student_id}-${p.tutor_id}-${p.subject}`} className={p === pair ? "bg-amber-50" : undefined}>{/* a row (highlighted when chosen): */}
                  <td>{p.student_name}</td>{/* the student, */}
                  <td>{p.tutor_name}</td>{/* the tutor, */}
                  <td>{p.subject}</td>{/* the subject, */}
                  <td>{p.upcoming_sessions}</td>{/* how many booked, */}
                  <td>{p.paid_sessions}</td>{/* how many paid, */}
                  <td>{shortDate(p.first_session)} to {shortDate(p.last_session)}</td>{/* the first and last dates, */}
                  <td><TextLink href={pick(p)}>Choose</TextLink></td>{/* and a link to choose it. */}
                </tr> // End of the row.
              ))}{/* End of the loop. */}
            </Table> // End of the table.
          )}{/* End of the list. */}
        </Card>{/* End of the first step. */}

        {chosen && ( // Once a row is chosen:
          <Card title="Choose the new tutor" description={pair ? `${pair.student_name}, ${pair.subject}: ${pair.upcoming_sessions} session(s) booked with ${pair.tutor_name}, ${pair.paid_sessions} already paid for.` : "There are no upcoming sessions left for this choice."}>{/* the second step: */}
            <form method="get" className="mb-5 flex flex-wrap items-end gap-3">{/* the change date form: */}
              <input type="hidden" name="student" value={studentId} />{/* (the student) */}
              <input type="hidden" name="tutor" value={tutorId} />{/* (the current tutor) */}
              <input type="hidden" name="subject" value={subject} />{/* (the subject) */}
              <div className="w-48"><Field label="Change from" name="from" type="date" min={today} defaultValue={from} required /></div>{/* the date box, */}
              {canRetime && ( // one weekly pattern: the day and time boxes, filled in with the current ones:
                <>{/* (a group) */}
                  <div className="w-44"><Select label="Day" name="weekday" defaultValue={String(weekday)}>{WEEKDAY_NAMES.map((n, i) => <option key={n} value={i + 1}>{n}{i + 1 === pattern!.weekday ? " (now)" : ""}</option>)}</Select></div>{/* the day (marking the current one), */}
                  <div className="w-36"><Select label="Start time" name="start" defaultValue={start ?? ""}>{START_TIMES.map((t) => <option key={t} value={t}>{timeWords(t)}{t === pattern!.start_time.slice(0, 5) ? " (now)" : ""}</option>)}</Select></div>{/* and the start time (marking the current one), */}
                </>/* End of the group. */
              )}{/* End of the day and time boxes. */}
              <Button type="submit">Update the list</Button>{/* and the button to update the tutors below. */}
            </form>{/* End of the date form. */}
            {pattern && !canRetime && <p className="mb-4 text-sm text-zinc-600">These sessions are on different days or times, so they keep their booked days and times. To change the day and time too, choose a change date after any one-off sessions.</p>}{/* why the day and time can't change here, */}
            {retimed && <p className="mb-4 text-sm text-zinc-700">New time: {WEEKDAY_NAMES[weekday! - 1]}s at {timeWords(start!)} (each session moves within its own week). The tutors below are checked at that time.</p>}{/* the new time chosen. */}
            {candidates.length === 0 ? ( // no tutor fits:
              <Empty>No other tutor holds the checks and teaches this subject at this student&apos;s level. Check the Matching page&apos;s gaps, or add what a tutor teaches first.</Empty> // says so and what to do,
            ) : ( // otherwise a table of tutors:
              <Table headings={["Tutor", "Free at these times?", "Hours a week (now + moving)", "Teaches a sibling"]}>{/* with these headings: */}
                {candidates.map((c) => { // for each tutor:
                  const problems = blockers(c); // what's in the way.
                  return ( // shows:
                    <tr key={c.tutor_id}>{/* a row: */}
                      <td>{c.full_name}</td>{/* the tutor, */}
                      <td className={problems.length ? "text-red-800" : "text-teal-800"}>{problems.length ? problems.join("; ") : "Yes"}</td>{/* free, or what's in the way, */}
                      <td>{(c.booked_minutes / 60).toFixed(1)} + {(c.added_minutes / 60).toFixed(1)} hr{c.max_weekly_hours !== null ? ` (most ${c.max_weekly_hours})` : ""}</td>{/* their hours now and what would move, with their limit, */}
                      <td>{c.teaches_sibling ? "Yes" : ""}</td>{/* and whether they teach a brother or sister. */}
                    </tr> // End of the row.
                  ); // End of what's shown.
                })}{/* End of the loop. */}
              </Table> // End of the table.
            )}{/* End of the tutors. */}
            {pair && free.length > 0 && ( // Sessions left and someone free: the move form.
              <div className="mt-6 max-w-xl">{/* the form area: */}
                <ActionForm action={proposeTutorChange} submitLabel="Send for confirmation">{/* the form: */}
                  <input type="hidden" name="student" value={studentId} />{/* (the student) */}
                  <input type="hidden" name="from_tutor" value={tutorId} />{/* (the current tutor) */}
                  <input type="hidden" name="subject" value={pair.subject} />{/* (the subject) */}
                  <input type="hidden" name="from" value={from} />{/* (the change date) */}
                  <input type="hidden" name="weekday" value={retimed ? String(weekday) : ""} />{/* (the new day, if changing) */}
                  <input type="hidden" name="start" value={retimed ? (start ?? "") : ""} />{/* (the new time, if changing) */}
                  <Select label="New tutor" name="to_tutor" required defaultValue="">{/* the new tutor list: */}
                    <option value="" disabled>Choose a tutor</option>{/* a prompt, */}
                    {free.map((c) => <option key={c.tutor_id} value={c.tutor_id}>{c.full_name}{c.teaches_sibling ? " (teaches a sibling)" : ""}</option>)}{/* and each free tutor. */}
                  </Select>{/* End of the list. */}
                  <Field label="Reason (only matching admins see this)" name="reason" required minLength={2} maxLength={500} placeholder="e.g. Tutor leaving CLG" hint="If this is about a child safety concern, just write 'Safety re-match'. Do not write the details here." />{/* the reason box, */}
                  <label className="flex items-start gap-2 text-sm">{/* the tick box: */}
                    <input type="checkbox" name="tell_old_tutor" defaultChecked className="mt-1" />{/* ticked to start, */}
                    <span>Once it is confirmed, tell {pair.tutor_name} that the sessions have moved to another tutor (no reason is given). Untick while a concern is being looked into.</span>{/* what it does. */}
                  </label>{/* End of the tick box. */}
                  <p className="text-sm text-zinc-600">The new tutor and the family are asked to confirm (outside quiet hours). Once both say yes, every session from {shortDate(from)} moves{retimed ? " to the new time" : ""}, and the new tutor can read the student&apos;s notes. If either says no, nothing changes and you are told why.</p>{/* what will happen. */}
                </ActionForm>{/* End of the form. */}
              </div> // End of the form area.
            )}{/* End of the move form. */}
            {pair && candidates.length > 0 && free.length === 0 && <p className="mt-4 text-sm text-red-800">No tutor is free for every session from {shortDate(from)}. Try a later date, move a clashing session, or change a tutor&apos;s hours or libraries first.</p>}{/* nobody free: what to try. */}
          </Card> // End of the second step.
        )}{/* End of the chosen part. */}

        {offers.some((o) => o.status !== "waiting") && ( // Answered changes in the last 30 days:
          <Card title="Answered in the last 30 days" collapsible defaultOpen={offers.some((o) => o.status === "declined" || o.status === "failed")}>{/* a card (open when something needs a look): */}
            <ul className="space-y-2 text-sm">{/* the list: */}
              {offers.filter((o) => o.status !== "waiting").map((o) => ( // for each answered change:
                <li key={o.id}>{/* a line: */}
                  <span className={o.status === "declined" || o.status === "failed" ? "font-semibold text-red-800" : "font-semibold"}>{OFFER_STATUS[o.status] ?? o.status}</span>{/* where it ended up (red when it needs a look), */}
                  : {o.student_name}, {o.subject}, to {o.to_tutor_name ?? "former tutor"} from {shortDate(o.from_date)}{/* who and what, */}
                  {o.declined_by_role ? `. The ${o.declined_by_role} said: "${o.answer_note ?? ""}"` : ""}{o.closed_note ? `. ${o.closed_note}` : ""}.{/* and why, if declined, withdrawn or failed. */}
                </li> // End of the line.
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
          </Card> // End of the answered card.
        )}{/* End of the answered part. */}

        <Card title="Recent tutor changes" collapsible defaultOpen={false}>{/* the record, closed to start: */}
          {changes.length === 0 ? <Empty>No tutor changes yet.</Empty> : ( // none yet, or a list:
            <ul className="space-y-2 text-sm">{/* the list: */}
              {changes.map((c) => ( // for each change:
                <li key={c.id}>{shortDate(c.changed_at)}: {c.student_name ?? "A student"}, {c.subject}, {c.from_tutor_name ?? "former tutor"} to {c.to_tutor_name ?? "former tutor"} from {shortDate(c.from_date)} ({c.sessions_moved} session(s)). {c.reason}{c.changed_by_name ? `, by ${c.changed_by_name}` : ""}.</li> // when, who, what, why and by whom.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of the record. */}
        </Card>{/* End of the record card. */}
        <p><BackButton href={sessionsHref("admin", "bookings")}>Back to bookings</BackButton></p>{/* The same back button at the bottom, so it's there after scrolling down. */}
      </div>{/* End of the page's cards. */}
    </DashboardFrame> // End of the dashboard frame.
  ); // End of what's shown.
} // End of ChangeTutorPage.
