// Sections of the Schedule page for the 2 Nov 2026 changes: study periods,
// requests and public holidays, blocks, and libraries with opening hours.
// The database decides what each person can see.

import { markHoursChecked, removeLibraryHours, removeOwnTerm, liftBlock } from "@/app/actions/scheduling-extra"; // Scheduling actions: hours still right, clear hours, remove own dates, lift a block.
import { setLibraryActive } from "@/app/actions/scheduling"; // The action to hide or show a library.
import { Card, Empty, SubHeading } from "@/components/ui"; // Shared page parts: card, empty line and small heading.
import { WEEKDAY_NAMES, clockTime, localToday, shortDate } from "@/lib/scheduling"; // Weekday names, time and date wording, and today's date.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { LibraryForm } from "./forms"; // The "add a library" form.
import { // The scheduling forms used here:
  BlockFollowUpForm, // block follow-up,
  BlockForm, // block,
  CloseRequestForm, // close a request,
  ConfirmLibraryForm, // confirm a library,
  LibraryHoursForm, // library opening hours,
  LoadLibrariesForm, // load SA libraries,
  FillHoursForm, // fill hours from OpenStreetMap,
  OfferOneOffForm, // offer a one-off,
  OwnTermForm, // own study dates,
  SessionRequestForm, // ask for a session,
  SkipPublicHolidaysForm, // skip public holidays,
  StudyPeriodForm, // study period,
  Term4LastDayForm, // last day of Term 4.
} from "./extra-forms"; // End of the forms.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while sending.

const STUDY_PERIOD_NAMES: Record<string, string> = { // The words for each study period:
  public: "SA government school terms", // government terms,
  private: "SA private school terms", // private terms,
  own: "Own study dates", // own dates.
}; // End of the words.

// ---------------------------------------------------------------------------
// Study period for one child (inside Session places)
// ---------------------------------------------------------------------------
export async function StudyPeriodBlock({ studentId, yearLevel }: { studentId: string; yearLevel: string | null }) { // The study period box for one child (given their year level).
  const supabase = await createClient(); // Connects to the database.
  const thisYear = Number(localToday().slice(0, 4)); // This year.
  const [periodRes, ownRes, endRes] = await Promise.all([ // Reads three things at once:
    supabase.from("student_study_periods").select("calendar").eq("student_id", studentId).maybeSingle(), // their study period,
    supabase.from("student_own_terms").select("id, label, starts_on, ends_on").eq("student_id", studentId).order("starts_on"), // their own study dates, earliest first,
    supabase.from("student_term_ends").select("last_day").eq("student_id", studentId).eq("year", thisYear).maybeSingle(), // and this year's last day of Term 4.
  ]); // End of the reads.
  const tertiary = yearLevel === "University or TAFE" || yearLevel === "Adult learner"; // Whether they study at university, TAFE or as an adult.
  const calendar = (periodRes.data?.calendar as string | undefined) ?? (tertiary ? "own" : "public"); // Their study period (own dates for tertiary, government terms otherwise, if not chosen).
  const own = (ownRes.data ?? []) as { id: string; label: string | null; starts_on: string; ends_on: string }[]; // Their own study dates.
  return ( // Shows:
    <div className="space-y-3 rounded-lg border border-zinc-200 p-3">{/* a bordered box: */}
      <StudyPeriodForm studentId={studentId} calendar={calendar} />{/* the study period form. */}
      {calendar === "own" ? ( // If they use their own dates:
        <>{/* (a group) */}
          {own.length === 0 ? ( // if none yet:
            <p className="text-sm text-amber-800">No study dates yet. Please add each semester, trimester or term.</p> // asks for them.
          ) : ( // otherwise:
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {own.map((o) => ( // for each date range:
                <li key={o.id} className="flex items-center justify-between gap-3 py-2">{/* a row: */}
                  <span>{/* (a group) */}
                    <span className="font-medium">{o.label ?? "Study period"}</span> · {shortDate(o.starts_on)} to{" "}{/* its name, first day and, */}
                    {shortDate(o.ends_on)}{/* last day. */}
                  </span>{/* End of the group. */}
                  <form action={removeOwnTerm}>{/* a remove form: */}
                    <input type="hidden" name="id" value={o.id} />{/* the range (hidden), */}
                    <BusyButton type="submit" className="text-xs text-teal-800 underline">{/* the remove button: */}
                      Remove{/* its words, */}
                    </BusyButton>{/* end of the button. */}
                  </form>{/* End of the form. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of this part. */}
          <OwnTermForm studentId={studentId} />{/* the add-dates form. */}
        </> // End of the group.
      ) : ( // otherwise:
        <Term4LastDayForm studentId={studentId} current={(endRes.data?.last_day as string | undefined) ?? ""} /> // the last day of Term 4 form.
      )}{/* End of this part. */}
    </div> // End of the box.
  ); // End of what's shown.
} // End of StudyPeriodBlock.

// ---------------------------------------------------------------------------
// Admins: study dates still to check (inside Next term)
// ---------------------------------------------------------------------------
export async function StudyDatesToCheck() { // The admin list of study dates still to check.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("list_study_dates_to_check"); // Reads the list (admins only).
  const rows = (data ?? []) as { student_id: string; student_name: string; calendar: string; problem: string }[]; // The rows.
  return ( // Shows:
    <Card // a card:
      title="Study dates to check" // its title,
      description="Students with a booking whose dates aren't loaded yet: tertiary students with no study dates, and school students whose last day of Term 4 isn't confirmed. Ask the family, or add it under Session places." // its help text.
    >{/* (end of the card's settings) */}
      {rows.length === 0 ? ( // if none:
        <Empty>Nothing to check.</Empty> // says so.
      ) : ( // otherwise:
        <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
          {rows.map((r) => ( // for each student:
            <li key={r.student_id} className="py-2">{/* a row: */}
              <span className="font-medium">{r.student_name}</span>{/* their name, */}
              <span className="text-zinc-600">{/* in grey: */}
                {" "}{/* a space, */}
                · {STUDY_PERIOD_NAMES[r.calendar] ?? r.calendar} · {r.problem}{/* their study period and what's missing. */}
              </span>{" "}{/* End of the grey part, then a space. */}
              <a className="text-xs text-teal-800 underline" href={`/schedule?as=admin&section=child-places&student=${r.student_id}`}>{/* a link to their study dates: */}
                Open{/* its words, */}
              </a>{/* end of the link. */}
            </li> // End of the row.
          ))}{/* End of the loop. */}
        </ul> // End of the list.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of StudyDatesToCheck.

// ---------------------------------------------------------------------------
// Requests and public holidays
// ---------------------------------------------------------------------------
type SessionRequest = { // A request as listed:
  id: string; // its id,
  student_id: string; // the student,
  student_name: string; // the student's name,
  kind: string; // the kind of request,
  subject: string; // the subject,
  tutor_id: string | null; // the usual tutor (if any),
  tutor_name: string | null; // their name,
  event_on: string | null; // the event's date (if any),
  event_label: string | null; // what the event is (if any),
  wants: string | null; // what they'd like for cover (if any),
  note: string | null; // the family's note (if any),
  status: string; // its status,
  staff_note: string | null; // CLG's note (if any),
  created_at: string; // when it was made,
  offered_booking_id: string | null; // the session offered (if any),
  offered_status: string | null; // and that session's status.
}; // End of SessionRequest.

const KIND_NAMES: Record<string, string> = { // The words for each kind of request:
  extra: "Extra session", // extra,
  public_holiday: "Public holiday one-off", // public holiday,
  away_cover: "Cover while the tutor is away", // cover.
}; // End of the words.
const WANTS_NAMES: Record<string, string> = { time: "another time", tutor: "a different tutor", either: "another time or tutor" }; // The words for what they'd like for cover.
const REQUEST_STATUS: Record<string, string> = { // The words for each request status:
  open: "Waiting for a time", // open,
  offered: "Time offered, waiting for approval", // offered,
  done: "Booked", // done,
  declined: "Couldn't be arranged", // declined,
  withdrawn: "Withdrawn", // withdrawn.
}; // End of the words.

export async function RequestsSection({ // The requests and public holidays section, given:
  viewerId, // the signed-in person,
  isAdmin, // whether they're an admin,
  isTutor, // whether they're a tutor,
  canAsk, // and whether they can ask for sessions.
}: { // The types of those:
  viewerId: string; // an id,
  isAdmin: boolean; // yes or no,
  isTutor: boolean; // yes or no,
  canAsk: boolean; // yes or no.
}) { // End of the types.
  const supabase = await createClient(); // Connects to the database.
  const today = localToday(); // Today's date.
  const [reqRes, phRes, studentsRes, linksRes, tutorsRes, libsRes] = await Promise.all([ // Reads everything at once:
    supabase.rpc("list_session_requests"), // the requests they can see,
    canAsk ? supabase.rpc("list_public_holiday_weeks") : Promise.resolve({ data: [] }), // public holiday sessions (if they can ask),
    canAsk ? supabase.from("students").select("id, full_name, account_id, student_subjects(subject)").order("full_name") : Promise.resolve({ data: [] }), // the students and their subjects (if they can ask),
    canAsk ? supabase.from("parent_student_links").select("student_id").eq("parent_id", viewerId) : Promise.resolve({ data: [] }), // their own children (if they can ask),
    isAdmin ? supabase.from("tutor_profiles").select("account_id, active, account:accounts(full_name)").eq("active", true) : Promise.resolve({ data: [] }), // the active tutors (admins only),
    supabase.from("libraries").select("id, name").eq("active", true).not("confirmed_at", "is", null).order("name"), // the confirmed libraries in use.
  ]); // End of the reads.
  const requests = (reqRes.data ?? []) as SessionRequest[]; // The requests.
  const open = requests.filter((r) => r.status === "open" || r.status === "offered"); // The open ones.
  const closed = requests.filter((r) => !(r.status === "open" || r.status === "offered")); // The closed ones.
  const holidays = (phRes.data ?? []) as { // The public holiday sessions:
    booking_id: string; // the booking,
    student_name: string; // the student's name,
    subject: string; // the subject,
    holiday_on: string; // the holiday's date,
    holiday_name: string; // its name,
    skipping: boolean; // whether the booking skips holidays,
    session_id: string | null; // and the session that day (if any).
  }[]; // (end of the type)
  const mine = new Set(((linksRes.data ?? []) as { student_id: string }[]).map((l) => l.student_id)); // Their own children.
  const children = ( // The children they can ask for:
    (studentsRes.data ?? []) as { id: string; full_name: string; account_id: string | null; student_subjects: { subject: string }[] }[] // from the students,
  ) // (end of the type)
    .filter((s) => isAdmin || mine.has(s.id) || s.account_id === viewerId) // keeping their own children, themselves, or everyone for admins,
    .map((s) => ({ id: s.id, name: s.full_name, subjects: s.student_subjects.map((x) => x.subject) })) // each with an id, name and subjects,
    .filter((s) => s.subjects.length > 0); // and only those with a subject.
  const tutors = ((tutorsRes.data ?? []) as unknown as { account_id: string; account: { full_name: string } | null }[]).map((t) => ({ // The tutors to choose from:
    id: t.account_id, // each tutor's id,
    name: t.account?.full_name ?? "Tutor", // and name.
  })); // End of the tutors.
  const libraries = (libsRes.data ?? []) as { id: string; name: string }[]; // The libraries.

  const line = (r: SessionRequest) => // One line describing a request:
    `${r.student_name} · ${r.subject} · ${KIND_NAMES[r.kind] ?? r.kind}` + // the student, subject and kind,
    (r.kind === "extra" && r.event_on ? ` before ${r.event_label ?? "an event"} on ${shortDate(r.event_on)}` : "") + // the event (for an extra session),
    (r.kind !== "extra" && r.event_on ? ` · ${shortDate(r.event_on)}` : "") + // the date (for other kinds),
    (r.wants ? ` · wants ${WANTS_NAMES[r.wants] ?? r.wants}` : ""); // and what they'd like (if given).

  // A day before the event is the latest an extra session can be.
  const dayBefore = (iso: string) => { // Gives the day before a date:
    const d = new Date(`${iso}T00:00:00`); // the date,
    d.setDate(d.getDate() - 1); // moved back a day,
    return d.toISOString().slice(0, 10); // given back as text.
  }; // End of dayBefore.

  return ( // Shows:
    <>{/* (a group) */}
      {canAsk && holidays.length > 0 && ( // If they can ask and there are holiday sessions:
        <Card // a card:
          title="Public holiday weeks" // its title,
          description="Sessions that fall on a public holiday in the next few months. You can skip public holidays for a booking and ask for a one-off at another time that week." // its help text.
        >{/* (end of the card's settings) */}
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {holidays.map((h) => ( // for each holiday session:
              <li key={`${h.booking_id}-${h.holiday_on}`} className="space-y-2 py-3 first:pt-0">{/* a row: */}
                <p>{/* a line: */}
                  <span className="font-medium">{/* in bold: */}
                    {h.holiday_name}, {shortDate(h.holiday_on)}{/* the holiday's name and date. */}
                  </span>{/* End of the bold part. */}
                  <span className="text-zinc-600">{/* in grey: */}
                    {" "}{/* a space, */}
                    · {h.student_name} · {h.subject} ·{" "}{/* the student and subject, then a space, */}
                    {h.skipping ? "skipped (no session that day)" : h.session_id ? "session booked that day" : "no session that day"}{/* whether there's a session that day. */}
                  </span>{/* End of the grey part. */}
                </p>{/* End of the line. */}
                <SkipPublicHolidaysForm bookingId={h.booking_id} skipping={h.skipping} />{/* the skip-holidays switch. */}
              </li> // End of the row.
            ))}{/* End of the loop. */}
          </ul>{/* End of the list. */}
        </Card> // End of the card.
      )}{/* End of this part. */}

      {canAsk && children.length > 0 && ( // If they can ask and have a child with a subject:
        <Card collapsible defaultOpen={false} title="Ask for a session" description="An extra session before a big event, a one-off for a public holiday week, or cover while your tutor is away.">{/* a fold-up card: */}
          <SessionRequestForm students={children} today={today} />{/* the ask-for-a-session form. */}
        </Card> // End of the card.
      )}{/* End of this part. */}

      <Card // the requests card:
        title="Requests" // its title,
        description={ // its help text:
          isAdmin // for admins,
            ? "Families' requests for one-off sessions, oldest first. The student's tutor can offer a time too." // their wording,
            : isTutor // for tutors,
              ? "Requests from your students' families. If you can, offer a time; the family then approves it." // their wording,
              : "Your requests and where they are up to." // otherwise the family's wording.
        } // (end of the help text)
      >{/* (end of the card's settings) */}
        {open.length === 0 ? ( // if no open requests:
          <Empty>No open requests.</Empty> // says so.
        ) : ( // otherwise:
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {open.map((r) => { // for each open request:
              const isTheirTutor = r.tutor_id === viewerId; // whether this person is the student's tutor,
              return ( // shows:
                <li key={r.id} className="space-y-2 py-4 first:pt-0">{/* a row: */}
                  <p className="font-medium">{line(r)}</p>{/* the request's line, */}
                  <p className="text-zinc-600">{/* a grey line: */}
                    {REQUEST_STATUS[r.status] ?? r.status} · asked {shortDate(r.created_at.slice(0, 10))}{/* its status and when asked, */}
                    {r.tutor_name && ` · tutor ${r.tutor_name}`}{/* and the tutor (if any). */}
                  </p>{/* End of the line. */}
                  {r.note && <p className="text-zinc-600">Note: {r.note}</p>}{/* the family's note (if any). */}
                  {r.status === "open" && (isAdmin || isTheirTutor) && ( // If open and they're an admin or the tutor:
                    <OfferOneOffForm // the offer-a-time form:
                      requestId={r.id} // the request,
                      isAdmin={isAdmin} // whether they're an admin,
                      tutors={r.tutor_id ? [{ id: r.tutor_id, name: r.tutor_name ?? "Usual tutor" }, ...tutors.filter((t) => t.id !== r.tutor_id)] : tutors} // the tutors (the usual tutor first),
                      libraries={libraries} // the libraries,
                      today={today} // today's date,
                      before={r.kind === "extra" && r.event_on ? dayBefore(r.event_on) : null} // and the latest date (the day before the event, for an extra session).
                    /> // End of the form.
                  )}{/* End of this part. */}
                  {isAdmin && <CloseRequestForm id={r.id} status="declined" label="Couldn't arrange it" />}{/* Admins can decline it. */}
                  {!isAdmin && !isTutor && <CloseRequestForm id={r.id} status="withdrawn" label="Withdraw" />}{/* Families can withdraw it. */}
                </li> // End of the row.
              ); // End of what's shown for this request.
            })}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}

      {closed.length > 0 && ( // If there are closed requests:
        <Card collapsible defaultOpen={false} title="Earlier requests">{/* a fold-up card: */}
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {closed.map((r) => ( // for each:
              <li key={r.id} className="py-2">{/* a row: */}
                <span className="font-medium">{line(r)}</span>{/* the request's line, */}
                <span className="text-zinc-600"> · {REQUEST_STATUS[r.status] ?? r.status}</span>{/* its status, */}
                {r.staff_note && <span className="block text-zinc-600">{r.staff_note}</span>}{/* CLG's note (if any). */}
              </li> // End of the row.
            ))}{/* End of the loop. */}
          </ul>{/* End of the list. */}
        </Card> // End of the card.
      )}{/* End of this part. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of RequestsSection.

// ---------------------------------------------------------------------------
// Blocks
// ---------------------------------------------------------------------------
type Block = { // A block as listed:
  id: string; // its id,
  tutor_name: string; // the tutor's name,
  student_name: string; // the student's name,
  blocked_by_role: string; // who made it (tutor or family),
  reason: string; // the reason,
  created_at: string; // when it was made,
  followed_up_at: string | null; // when CLG followed up (if yet),
  follow_up_note: string | null; // the follow-up note (if any),
  lifted_at: string | null; // and when it was lifted (if it was).
}; // End of Block.

export async function BlocksSection({ // The blocks section, given:
  viewerId, // the signed-in person,
  isAdmin, // whether they're an admin,
  isTutor, // whether they're a tutor,
  bookings, // and their bookings.
}: { // The types of those:
  viewerId: string; // an id,
  isAdmin: boolean; // yes or no,
  isTutor: boolean; // yes or no,
  bookings: { tutor_id: string; tutor_name: string; student_id: string; student_name: string }[]; // each booking's tutor and student.
}) { // End of the types.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("list_blocks"); // Reads the blocks they can see.
  const blocks = (data ?? []) as Block[]; // The blocks.
  // Who each person can block: tutors their students they have had; families
  // the tutors their children have had.
  const seen = new Set<string>(); // Tutor-student pairs already added.
  const choices: { value: string; label: string }[] = []; // The people they can block.
  for (const b of bookings) { // For each booking:
    const asTutor = isTutor && b.tutor_id === viewerId; // whether they're the tutor here,
    if (!isAdmin && !asTutor && b.tutor_id === viewerId) continue; // skips their own tutoring if they aren't acting as a tutor,
    const key = `${b.tutor_id}:${b.student_id}`; // the pair as "tutor id:student id",
    if (seen.has(key)) continue; // already added: skips it,
    seen.add(key); // notes it's added,
    choices.push({ value: key, label: asTutor ? b.student_name : `${b.tutor_name} (for ${b.student_name})` }); // adds it (the student's name for tutors; the tutor's for families).
  } // End of the loop.
  const tutorChoices = choices.filter((c) => c.value.startsWith(`${viewerId}:`)); // The pairs where they're the tutor.
  const familyChoices = choices.filter((c) => !c.value.startsWith(`${viewerId}:`)); // The other pairs.

  return ( // Shows:
    <>{/* (a group) */}
      {!isAdmin && (isTutor ? tutorChoices.length > 0 : familyChoices.length > 0) && ( // For non-admins with someone to block:
        <Card // a fold-up card:
          collapsible // can fold,
          defaultOpen={false} // folded to start,
          title={isTutor ? "Block a student" : "Block a tutor"} // its title,
          description="If a match isn't working and shouldn't be suggested again. A reason is required, and CLG will follow up with you." // its help text.
        >{/* (end of the card's settings) */}
          <BlockForm choices={isTutor ? tutorChoices : familyChoices} asTutor={isTutor} />{/* the block form. */}
        </Card> // End of the card.
      )}{/* End of this part. */}
      <Card // the blocks card:
        title="Blocks" // its title,
        description={ // its help text:
          isAdmin // for admins,
            ? "Each block needs a follow-up with the person who made it, to understand what happened and help it not happen again. The other person isn't told." // their wording,
            : "Blocks you have made. Only CLG sees the reason." // otherwise everyone else's.
        } // (end of the help text)
      >{/* (end of the card's settings) */}
        {blocks.length === 0 ? ( // if no blocks:
          <Empty>No blocks.</Empty> // says so.
        ) : ( // otherwise:
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {blocks.map((b) => ( // for each block:
              <li key={b.id} className={`space-y-2 py-4 first:pt-0 ${b.lifted_at ? "text-zinc-400" : ""}`}>{/* a row (greyed if lifted): */}
                <p>{/* a line: */}
                  <span className="font-medium">{/* in bold: */}
                    {b.blocked_by_role === "tutor" ? `${b.tutor_name} blocked ${b.student_name}` : `${b.student_name}'s family blocked ${b.tutor_name}`}{/* who blocked whom. */}
                  </span>{/* End of the bold part. */}
                  <span className="text-zinc-600">{/* in grey: */}
                    {" "}{/* a space, */}
                    · {shortDate(b.created_at.slice(0, 10))}{/* the date, */}
                    {b.lifted_at ? " · lifted" : b.followed_up_at ? " · followed up" : isAdmin ? " · to follow up" : ""}{/* and lifted, followed up, or to follow up. */}
                  </span>{/* End of the grey part. */}
                </p>{/* End of the line. */}
                <p className="text-zinc-600">Reason: {b.reason}</p>{/* the reason. */}
                {isAdmin && b.follow_up_note && <p className="text-zinc-600">Follow-up: {b.follow_up_note}</p>}{/* the follow-up note (admins). */}
                {isAdmin && !b.lifted_at && !b.followed_up_at && <BlockFollowUpForm id={b.id} />}{/* the follow-up form (admins, if not done). */}
                {isAdmin && !b.lifted_at && ( // If an admin and not lifted:
                  <form action={liftBlock}>{/* the lift form: */}
                    <input type="hidden" name="id" value={b.id} />{/* the block (hidden), */}
                    <BusyButton type="submit" className="text-xs text-teal-800 underline">{/* the lift button: */}
                      Lift this block{/* its words, */}
                    </BusyButton>{/* end of the button. */}
                  </form> // End of the form.
                )}{/* End of this part. */}
              </li> // End of the row.
            ))}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of BlocksSection.

// ---------------------------------------------------------------------------
// Admins: libraries, with confirmation and opening hours
// ---------------------------------------------------------------------------
export async function LibrariesAdminSection() { // The admin libraries section.
  const supabase = await createClient(); // Connects to the database.
  const [libsRes, hoursRes, checksRes] = await Promise.all([ // Reads three things at once:
    supabase.from("libraries").select("id, name, suburb, address, active, confirmed_at, suggested_by, osm_ref").order("name"), // the libraries, by name,
    supabase.from("library_hours").select("library_id, weekday, opens, closes").order("weekday").order("opens"), // their opening hours, by day and time,
    supabase.rpc("library_checks"), // and libraries needing a look.
  ]); // End of the reads.
  const checks = (checksRes.data ?? []) as { library_id: string; name: string; suburb: string | null; problem: string }[]; // The libraries needing a look.
  const libraries = (libsRes.data ?? []) as { // The libraries:
    id: string; // each has an id,
    name: string; // a name,
    suburb: string | null; // a suburb (if known),
    address: string | null; // an address (if known),
    active: boolean; // whether it's in use,
    confirmed_at: string | null; // when it was confirmed (if yet),
    osm_ref: string | null; // and its OpenStreetMap reference (if any).
  }[]; // (end of the type)
  const hours = (hoursRes.data ?? []) as { library_id: string; weekday: number; opens: string; closes: string }[]; // The opening hours.
  const hoursOf = (id: string) => hours.filter((h) => h.library_id === id); // Gives one library's opening hours.
  return ( // Shows:
    <Card // a card:
      title="Libraries" // its title,
      description="Public libraries for in-person sessions. Confirm each library and add its opening hours: sessions are only offered at confirmed libraries, inside opening hours." // its help text.
    >{/* (end of the card's settings) */}
      {checks.length > 0 && ( // If there are libraries needing a look:
        <div className="mb-6 rounded-xl border border-amber-200 bg-amber-50 p-4">{/* an amber box: */}
          <p className="mb-2 text-sm font-medium text-amber-900">To do ({checks.length})</p>{/* the count, */}
          <ul className="space-y-2 text-sm">{/* a list: */}
            {checks.map((c) => ( // for each:
              <li key={c.library_id} className="flex flex-wrap items-center justify-between gap-2">{/* a row: */}
                <span>{/* (a group) */}
                  <a href={`#lib-${c.library_id}`} className="font-medium underline">{/* a link to the library below: */}
                    {c.name}{/* its name, */}
                  </a>{/* end of the link. */}
                  {c.suburb && ` · ${c.suburb}`}: {c.problem}{/* its suburb and what needs doing. */}
                </span>{/* End of the group. */}
                {c.problem.startsWith("Check") && ( // If it's an hours check:
                  <form action={markHoursChecked}>{/* the "still right" form: */}
                    <input type="hidden" name="library_id" value={c.library_id} />{/* the library (hidden), */}
                    <BusyButton type="submit" className="text-xs text-teal-800 underline">{/* the button: */}
                      Hours still right{/* its words, */}
                    </BusyButton>{/* end of the button. */}
                  </form> // End of the form.
                )}{/* End of this part. */}
              </li> // End of the row.
            ))}{/* End of the loop. */}
          </ul>{/* End of the list. */}
          <p className="mt-2 text-xs text-amber-900">{/* a help line: */}
            Only libraries a tutor or family has chosen are listed. Hours are re-checked every 6 months, and whenever
            sessions are first booked at a library, check its public holiday and school holiday hours.{/* when hours are checked. */}
          </p>{/* End of the help line. */}
        </div> // End of the box.
      )}{/* End of this part. */}
      {libraries.length === 0 ? ( // if no libraries:
        <Empty>No libraries yet.</Empty> // says so.
      ) : ( // otherwise:
        <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
          {libraries.map((l) => { // for each library:
            const h = hoursOf(l.id); // its opening hours,
            return ( // shows:
              <li key={l.id} id={`lib-${l.id}`} className="space-y-2 py-4 first:pt-0">{/* a row (with a link target): */}
                <div className="flex items-center justify-between gap-3">{/* the top line: */}
                  <span className={l.active ? "" : "text-zinc-400"}>{/* (greyed if hidden) */}
                    <span className="font-medium">{l.name}</span>{/* its name, */}
                    {l.address && ` · ${l.address}`}{/* its address (if known), */}
                    {l.suburb && ` · ${l.suburb}`}{/* its suburb (if known), */}
                    {!l.active && " (hidden)"}{/* hidden (if so), */}
                    {!l.confirmed_at && <span className="ml-2 text-xs text-amber-800">to confirm</span>}{/* to confirm (if not yet), */}
                    {l.confirmed_at && h.length === 0 && <span className="ml-2 text-xs text-amber-800">opening hours missing</span>}{/* opening hours missing (if confirmed without hours). */}
                  </span>{/* End of the group. */}
                  <form action={setLibraryActive}>{/* the hide/show form: */}
                    <input type="hidden" name="id" value={l.id} />{/* the library (hidden), */}
                    <input type="hidden" name="active" value={l.active ? "false" : "true"} />{/* the new setting (hidden), */}
                    <BusyButton type="submit" className="text-xs text-teal-800 underline">{/* the button: */}
                      {l.active ? "Hide" : "Show"}{/* Hide or Show. */}
                    </BusyButton>{/* End of the button. */}
                  </form>{/* End of the form. */}
                </div>{/* End of the top line. */}
                {h.length > 0 && ( // If it has hours:
                  <div className="text-zinc-600">{/* a grey line: */}
                    {h.map((x) => `${WEEKDAY_NAMES[x.weekday - 1].slice(0, 3)} ${clockTime(x.opens)}–${clockTime(x.closes)}`).join(" · ")}{" "}{/* each day's hours, then a space, */}
                    <form action={removeLibraryHours} className="inline">{/* the clear-hours form: */}
                      <input type="hidden" name="library_id" value={l.id} />{/* the library (hidden), */}
                      <BusyButton type="submit" className="text-xs text-teal-800 underline">{/* the button: */}
                        Clear hours{/* its words, */}
                      </BusyButton>{/* end of the button. */}
                    </form>{/* End of the form. */}
                  </div> // End of the line.
                )}{/* End of this part. */}
                <details>{/* a fold-out: */}
                  <summary className="cursor-pointer text-xs text-teal-800 underline">Add opening hours</summary>{/* its heading, */}
                  <div className="mt-2 space-y-3">{/* a box: */}
                    {l.osm_ref && h.length === 0 && <FillHoursForm libraryId={l.id} />}{/* the fill-from-OpenStreetMap form (if loaded from there and no hours), */}
                    <LibraryHoursForm libraryId={l.id} />{/* the add-hours form. */}
                  </div>{/* End of the box. */}
                </details>{/* End of the fold-out. */}
                {!l.confirmed_at && h.length > 0 && <ConfirmLibraryForm libraryId={l.id} />}{/* the confirm form (if not confirmed and has hours). */}
              </li> // End of the row.
            ); // End of what's shown for this library.
          })}{/* End of the loop. */}
        </ul> // End of the list.
      )}{/* End of this part. */}
      <SubHeading>Load all South Australian libraries</SubHeading>{/* a small heading, */}
      <LoadLibrariesForm />{/* the load SA libraries form, */}
      <SubHeading>Add a library</SubHeading>{/* a small heading, */}
      <LibraryForm />{/* the add-a-library form. */}
      <p className="mt-4 text-xs text-zinc-500">{/* the map credit line: */}
        Library details loaded from OpenStreetMap: © OpenStreetMap contributors, available under the Open Database
        Licence (openstreetmap.org/copyright).{/* (end of the text) */}
      </p>{/* End of the line. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of LibrariesAdminSection.
