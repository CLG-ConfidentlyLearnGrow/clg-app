// Summary: the Sessions page: sessions, bookings, booking, session places, how
// long to book, away dates, requests, blocks, notices, book again, waitlist,
// where tutors teach, times to check, tutor availability and libraries.
// It shows as the Sessions tab inside one dashboard at a time (Carla,
// 12 Nov 2026): "?as=tutor" shows the tutor's sessions in the tutor
// dashboard, "?as=parent" the family's in the parent dashboard, and so on.
//
import Link from "next/link"; // The Next.js link, for moving between pages without a full reload.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { after } from "next/server"; // Runs a job after the page is sent, so it doesn't slow the page.
import { PushSettings, type PushDevice } from "@/components/push-settings"; // The pop-up notifications controls and a device's shape (Carla, 18 Nov 2026).
import { cancelForTutorAway, leaveWaitlist, markNoticesRead, removeAwayDates, tickOffNotice, waitlistCheckedIn } from "@/app/actions/scheduling"; // Scheduling actions: cancel for tutor away dates, leave the waitlist, mark notices read, remove away dates, tick off one notice, record a waitlist check-in.
import { Button, Card, Empty, Field, Select, SubHeading, TextLink } from "@/components/ui"; // Shared page parts: button, card, empty line, field, drop-down, small heading and text link.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import { ROLE_ORDER } from "@/lib/roles"; // The order of the dashboards.
import { sessionsHref } from "@/lib/dashboard-menu"; // The address of a dashboard's Sessions tab.
import { sessionTabs } from "@/lib/menu-sub-tabs"; // Each dashboard's Sessions sub-tabs (Carla, 20 Nov 2026).
import { // The extra sections:
  BlocksSection, // blocks,
  LibrariesAdminSection, // libraries (admins),
  RequestsSection, // requests,
  StudyDatesToCheck, // study dates to check (admins),
  StudyPeriodBlock, // a child's study period.
} from "./extra-sections"; // End of the list.
import { QuietHoursForm, SuggestLibraryForm, SummaryMinutesForm } from "./extra-forms"; // The quiet hours setting, the "suggest a library" form and the summary time setting.
import { FRONT_DESK, FULL_ADMIN, getAdminLevel, needsTwoStep, requireViewer } from "@/lib/auth"; // Admin level groups, the level reader, two-step sign-in check, and the signed-in person.
import { // Scheduling helpers:
  BOOKING_STATUS_NAMES, // booking status names,
  MAKEUP_STATUS_NAMES, // make-up offer status names,
  SESSION_LENGTHS, // session lengths,
  SESSION_STATUS_NAMES, // session status names,
  WEEKDAY_NAMES, // weekday names,
  addDays, // add days,
  TIME_CHECK_REASONS, // reasons for a time check,
  clockTime, // clock time wording,
  currentTime, // the time now,
  localClock, // a time's local clock,
  localDate, // a time's local date,
  lengthLabel, // length wording,
  localToday, // today's date,
  placeLabel, // place wording,
  sessionWhen, // session time wording,
  shortClock, // short clock wording (e.g. "9pm"),
  shortDate, // short dates.
} from "@/lib/scheduling"; // End of the helpers.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { schedulingCounts } from "@/lib/scheduling-counts"; // The to-do numbers for the scheduling tabs.
import { runTeamsSyncQuietly } from "@/lib/teams/sync"; // Keeps Teams links up to date, quietly.
import { // The scheduling forms:
  AnswerForm, // answer a booking request,
  ApproveForm, // approve an offer,
  AvailabilityCheckForm, // confirm availability for next term,
  AwayForm, // add away dates,
  BookForm, // book a session,
  CancelForm, // cancel,
  MakeupAnswerForm, // pick a make-up time,
  MakeupConfirmForm, // confirm a picked make-up time,
  ConfirmTimesForm, // confirm a session's times,
  EndTimeForm, // change a session's end time,
  OutcomeForm, // record what happened in a session,
  RunningLateForm, // tell the family and CLG the tutor is running late,
  PlacesForm, // where a tutor teaches,
  RenewalForm, // answer "book again?",
  SignOnForm, // sign on,
  BookingLengthForm, // how long to book,
  StudentPlacesForm, // a student's session places,
  StudentTravelForm, // a student's address and travel distance,
  type StudentTerm, // the term dates type,
  TermForm, // add a term,
  WaitlistForm, // join the waitlist.
} from "./forms"; // End of the forms.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while sending.
import { TutorChangeAnswerBox } from "@/components/tutor-change-answer-box"; // The "Please confirm a change" box for tutor changes.

// The scheduling module's one page. Each person sees the sections that fit
// their roles; the database decides which bookings and sessions they see.

type Booking = { // A weekly booking as listed:
  id: string; // its id,
  status: string; // its status,
  expired: boolean; // whether the request has expired,
  student_id: string; // the student,
  student_name: string; // their name,
  year_level: string | null; // their year level (if known),
  tutor_id: string; // the tutor,
  tutor_name: string; // their name,
  subject: string; // the subject,
  weekday: number; // the weekday,
  start_time: string; // the start time,
  minutes: number; // the length in minutes,
  delivery: string; // where,
  library_name: string | null; // the library's name (if any),
  first_date: string; // the first session date,
  last_date: string; // the last session date,
  family_note: string | null; // the family's note (if any),
  tutor_note: string | null; // the tutor's note (if any),
  tutor_reply_by: string; // when the tutor must reply by,
  sessions_left: number; // and how many sessions are left.
}; // End of Booking.

type Session = { // One session as listed:
  id: string; // its id,
  status: string; // its status,
  student_id: string; // the student,
  student_name: string; // the student's name,
  tutor_id: string; // the tutor,
  tutor_name: string; // their name,
  subject: string; // the subject,
  delivery: string; // where,
  library_name: string | null; // the library's name (if any),
  starts_at: string; // when it starts,
  ends_at: string; // when it ends,
  cancelled_by_role: string | null; // who cancelled it (if anyone),
  meeting_url: string | null; // and its online meeting link (if any).
}; // End of Session.

type MakeupOffer = { // Two make-up times offered after a cancel (Carla, 16 Nov 2026):
  id: string; // the offer's id,
  session_id: string; // the cancelled session,
  student_id: string; // the student,
  tutor_id: string; // the tutor,
  student_name: string; // the student's name (first name only for tutors),
  tutor_name: string; // the tutor's name,
  subject: string; // the subject,
  cancelled_starts_at: string; // when the cancelled session was,
  reason: string | null; // the reason given, in words,
  offered_by_role: string; // who cancelled: family, tutor or admin,
  answer_by: string; // who picks: family or tutor,
  option_1: string | null; // the first time offered,
  option_2: string | null; // the second time offered,
  status: string; // where it's up to,
  picked_at: string | null; // the time picked (if any),
  answer_note: string | null; // why neither works (if said).
}; // End of MakeupOffer.

type TimeOption = { // A time that could be booked:
  tutor_id: string; // the tutor,
  tutor_name: string; // their name,
  weekday: number; // the weekday,
  start_time: string; // the start time,
  end_time: string; // the end time,
  delivery: string; // where,
  library_id: string | null; // the library (if any),
  library_name: string | null; // its name,
  joins_other_sessions: boolean; // whether it sits next to the tutor's other sessions,
  learning_support: boolean; // whether the tutor has learning support experience,
  preferred: boolean; // and whether it's one of the family's preferred times.
}; // End of TimeOption.

const list = (v: string | string[] | undefined) => (v === undefined ? [] : Array.isArray(v) ? v : [v]); // Turns an address value into a list (none, one or several).
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? ""; // Gives one value from the address (the first if there are several).

export default async function SchedulePage({ searchParams }: PageProps<"/schedule">) { // The page itself (reads the address's settings).
  const viewer = await requireViewer(); // The signed-in person.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step sign-in not set up: sends them to set it up.
  const params = await searchParams; // The address's settings.
  // Keep Teams links up to date (at most every few minutes; never slows the page).
  after(runTeamsSyncQuietly); // Starts the Teams link update after the page is sent.

  // Admin levels: full admins (owner, operations) get every tool; support
  // admins can book, cancel and see sessions for any family.
  const adminLevel = viewer.roles.includes("admin") ? await getAdminLevel() : null; // Their admin level, if they're an admin.
  const deskLevel = adminLevel !== null && FRONT_DESK.includes(adminLevel); // Whether they're a front-desk admin.
  const fullLevel = adminLevel !== null && FULL_ADMIN.includes(adminLevel); // Whether they're a full admin.

  // Which dashboards have a Sessions tab for this person: admin (front desk
  // only; finance admins work in Billing), tutor, parent and student.
  const mine = ROLE_ORDER.filter((r) => (r === "admin" ? deskLevel : viewer.roles.includes(r))); // Their dashboards with Sessions, in tab order.
  if (mine.length === 0) redirect("/dashboard"); // None: back to their dashboard.

  // The menu's sections for one dashboard. Each dashboard sees only the
  // parts that fit it: admins everything, tutors their schedule, offers and
  // notices, families booking, their schedule and notices.
  const sectionsFor = (r: Role) => sessionTabs(r, adminLevel); // One dashboard's Sessions sub-tabs (the shared list the side menu also uses, so it can show them from any page).
  // Matching has its own tab now.
  if (params.section === "matching") redirect("/matching"); // Matching asked for: goes to its page.

  // The dashboard this page shows in: the one in the address ("as"), or,
  // for an old link without one, the first dashboard that has the section asked for.
  const asked = one(params.as) as Role; // The dashboard in the address, if any.
  const role: Role = mine.includes(asked) // If they have that dashboard:
    ? asked // use it,
    : (mine.find((r) => sectionsFor(r).some((s) => s.id === params.section)) ?? mine[0]); // otherwise the first one with that section (or their first).
  const isAdmin = role === "admin" && fullLevel; // Whether this is the admin dashboard of a full admin.
  const isDesk = role === "admin" && deskLevel; // Whether this is the admin dashboard of a front-desk admin.
  const isTutor = role === "tutor"; // Whether this is the tutor dashboard.
  const isFamily = role === "parent" || role === "student"; // Whether this is a family dashboard (parent or student).
  const canBook = isDesk || isFamily; // Whether they can book here (front desk and families).
  // Booking, searching for times and the waitlist are CLG staff jobs for now.
  // Families see their sessions and approve the times CLG offers.
  const sections = sectionsFor(role); // This dashboard's sections.
  const section = sections.find((s) => s.id === params.section)?.id ?? "sessions"; // The open section (the overview if none or unknown).
  const here = (sec: string) => sessionsHref(role, sec); // The address of one section in this dashboard.

  const supabase = await createClient(); // Connects to the database.
  const unreadRes = await supabase // Counts unread notices:
    .from("session_notices") // from session_notices,
    .select("id", { count: "exact", head: true }) // counting only,
    .is("read_at", null); // not yet read.
  const unread = unreadRes.count ?? 0; // The unread count.
  const renewalsRes = canBook // Counts "book again?" questions to answer (if they can book):
    ? await supabase.from("term_renewals").select("id", { count: "exact", head: true }).is("answered_at", null) // from term_renewals, not yet answered,
    : null; // otherwise none.
  const renewalsToAnswer = renewalsRes?.count ?? 0; // The count.
  // Admins: how many subjects are waiting for a tutor.
  // The tutor's own availability check for this term, if not yet answered.
  const myCheckRes = isTutor // The tutor's latest unanswered availability check:
    ? await supabase // if they're a tutor,
        .from("availability_checks") // from availability_checks,
        .select("id") // the id,
        .eq("tutor_id", viewer.id) // for this tutor,
        .is("confirmed_at", null) // not yet confirmed,
        .order("asked_at", { ascending: false }) // newest first,
        .limit(1) // just one,
        .maybeSingle() // if any.
    : null; // otherwise none.
  const myCheck = myCheckRes?.data as { id: string } | null | undefined; // The check (if any).
  const [bookingsRes, sessionsRes, requestTimesRes, makeupRes] = await Promise.all([ // Reads four things at once:
    supabase.rpc("list_bookings"), // the bookings they can see,
    supabase.rpc("list_sessions", { p_from: addDays(localToday(), -14), p_to: addDays(localToday(), 70) }), // sessions from 2 weeks ago to 10 weeks ahead,
    supabase.rpc("booking_request_times"), // when each booking was asked for (to show the newest first),
    supabase.rpc("list_makeup_offers"), // and make-up times offered after cancels (open ones and the last 30 days).
  ]); // End of the reads.
  // Each dashboard shows only its own: all of them for admins, the tutor's
  // own in the tutor dashboard, and the family's children in a family one
  // (so an admin who is also a parent sees just their own children there).
  const familyIds = new Set<string>(); // The students this family dashboard is for.
  if (role === "parent") { // In the parent dashboard:
    const links = await supabase.from("parent_student_links").select("student_id").eq("parent_id", viewer.id); // their children,
    for (const l of links.data ?? []) familyIds.add(l.student_id as string); // added to the list.
  } // End of the parent part.
  if (role === "student") { // In the student dashboard:
    const own = await supabase.from("students").select("id").eq("account_id", viewer.id); // their own student record,
    for (const o of own.data ?? []) familyIds.add(o.id as string); // added to the list.
  } // End of the student part.
  const ours = (tutorId: string, studentId: string) => // Whether a booking or session belongs in this dashboard:
    role === "admin" || (role === "tutor" ? tutorId === viewer.id : familyIds.has(studentId)); // admins all, tutors theirs, families their children's.
  const askedAt = new Map( // When each booking was asked for, by booking:
    ((requestTimesRes.data ?? []) as { id: string; requested_at: string }[]).map((r) => [r.id, r.requested_at]), // (id, time) pairs.
  ); // End of the map.
  const bookings = ((bookingsRes.data ?? []) as Booking[]) // The bookings for this dashboard:
    .filter((b) => ours(b.tutor_id, b.student_id)) // only this dashboard's,
    .sort((a, b) => (askedAt.get(b.id) ?? "").localeCompare(askedAt.get(a.id) ?? "")); // most recently asked for first (Carla, 12 Nov 2026).
  // Filter for the Bookings list (Carla, 12 Nov 2026): "?show=confirmed" etc.
  const show = BOOKING_FILTERS.some((f) => f.key === one(params.show)) ? one(params.show) : "all"; // The chosen filter (all if none or unknown).
  const shownBookings = show === "all" ? bookings : bookings.filter((b) => bookingFilterKey(b) === show); // The bookings that match it.
  const sessions = ((sessionsRes.data ?? []) as Session[]).filter((x) => ours(x.tutor_id, x.student_id)); // The sessions for this dashboard.
  const makeups = ((makeupRes.data ?? []) as MakeupOffer[]).filter((o) => ours(o.tutor_id, o.student_id)); // The make-up offers for this dashboard.
  // Whether a side ("tutor" or "family") is this dashboard's own. Only the
  // tutor and the family answer for themselves; CLG staff can't (Carla, 16 Nov 2026).
  const mySide = (side: string) => (isTutor ? side === "tutor" : isFamily && side === "family"); // the tutor dashboard is the tutor's side, a family dashboard the family's.
  // Make-up times waiting for this person to pick: the tutor's when the family
  // cancelled, the family's when the tutor (or CLG) cancelled.
  const makeupsToPick = makeups.filter( // Offers to pick from here:
    (o) => o.status === "waiting" && o.option_1 !== null && o.option_2 !== null && mySide(o.answer_by), // still waiting, with two times, and this side picks.
  ); // End of the filter.
  // Picked times waiting for this side to confirm (when CLG offered the times).
  const makeupsToConfirm = makeups.filter( // Offers to confirm here:
    (o) => o.status === "confirming" && o.picked_at !== null && mySide(o.answer_by === "tutor" ? "family" : "tutor"), // picked by the other side, waiting for this one.
  ); // End of the filter.
  const otherMakeups = makeups.filter((o) => !makeupsToPick.includes(o) && !makeupsToConfirm.includes(o)); // The rest, to show where they're up to.
  // Sign-on details for the tutor's own sessions.
  const mySessionIds = sessions.filter((s) => s.tutor_id === viewer.id).map((s) => s.id); // The tutor's own sessions.
  const signRes = mySessionIds.length // If there are any, reads:
    ? await supabase.from("sessions").select("id, signed_on_at, tutor_end_at, times_confirmed_at").in("id", mySessionIds) // their sign-on, end time and times-confirmed details,
    : null; // otherwise none.
  const signOf = new Map( // Each session's sign-on details, by session:
    (signRes?.data ?? []).map((r) => [ // from the rows,
      r.id as string, // the session id,
      r as { signed_on_at: string | null; tutor_end_at: string | null; times_confirmed_at: string | null }, // and its details.
    ]), // (end of the list)
  ); // End of signOf.
  // Who has approved each request (an offer from CLG needs the tutor and the family).
  const requestedIds = bookings.filter((b) => b.status === "requested").map((b) => b.id); // Bookings waiting for approval.
  const approvalsRes = requestedIds.length // If any, reads:
    ? await supabase.from("bookings").select("id, needs_family_ok, tutor_ok_at, family_ok_at").in("id", requestedIds) // who has approved each,
    : null; // otherwise none.
  const approvals = new Map( // Each request's approvals, by booking:
    ((approvalsRes?.data ?? []) as { id: string; needs_family_ok: boolean; tutor_ok_at: string | null; family_ok_at: string | null }[]).map( // from the rows,
      (a) => [a.id, a], // each by its id.
    ), // (end of the list)
  ); // End of approvals.
  const waitingForMe = bookings.filter( // Requests waiting for this tutor:
    (b) => isTutor && b.status === "requested" && !b.expired && b.tutor_id === viewer.id && !approvals.get(b.id)?.tutor_ok_at, // in the tutor dashboard: requested, not expired, theirs, not yet accepted by them.
  ); // End of the filter.
  // What a tutor sees before accepting: first name, year level, subject,
  // goal, place and time. The rest opens once they and the family accept.
  const goalRes = await Promise.all( // Reads the offer card for each:
    waitingForMe.map((w) => supabase.rpc("offer_card", { p_booking: w.id }).maybeSingle()), // for each request, its goal.
  ); // End of the reads.
  const goalOf = new Map( // Each request's goal, by booking:
    waitingForMe.map((w, i) => [w.id, ((goalRes[i].data as { goal: string | null } | null)?.goal ?? "").trim()]), // the goal (or blank).
  ); // End of goalOf.
  const familyToApprove = bookings.filter((b) => { // Offers waiting for the family:
    const a = approvals.get(b.id); // the request's approvals,
    return isFamily && b.status === "requested" && !b.expired && a?.needs_family_ok && !a.family_ok_at && b.tutor_id !== viewer.id; // in a family dashboard: requested, not expired, needs the family, not yet approved by them, and not this tutor's.
  }); // End of the filter.
  // A family must choose how often they pay before booking or approving
  // (Carla, 20 Nov 2026). Only the person who pays gets rows back here.
  const planChoices = isFamily // For a family dashboard:
    ? (((await supabase.rpc("billing_my_plan_choices")).data ?? []) as { family_id: string; chosen: boolean }[]) // their plan choices,
    : []; // otherwise none.
  const planMissing = planChoices.some((c) => !c.chosen); // Whether any family they pay for has not chosen yet.

  // Numbers on tabs that need action ("How long to book", Libraries).
  const counts = await schedulingCounts(supabase); // The scheduling to-do numbers.

  const now = currentTime(); // The time now.
  const upcoming = sessions.filter((s) => new Date(s.ends_at).getTime() >= now); // Sessions not yet over.
  const weekAgo = now - 7 * 24 * 3600 * 1000; // A week ago.
  const recentMine = sessions.filter( // The tutor's sessions from the last week:
    (s) => // each session:
      isTutor && // in the tutor dashboard,
      s.tutor_id === viewer.id && // theirs,
      s.status === "completed" && // completed,
      new Date(s.ends_at).getTime() < now && // already ended,
      new Date(s.ends_at).getTime() > weekAgo, // and in the last week.
  ); // End of the filter.
  // The tutor's own late starts from the last 90 days, so the record CLG
  // reviews is open to them too (Carla, 18 Nov 2026).
  const lateRes = isTutor ? await supabase.rpc("list_session_lateness", { p_days: 90 }) : null; // Reads them (tutor dashboard only).
  const myLate = ((lateRes?.data ?? []) as { id: string; tutor_id: string; starts_at: string; student_first_name: string; subject: string; told_minutes: number | null; told_before_start: boolean | null; signed_on_late_minutes: number | null; review_status: string; counts_as_late: boolean }[]).filter((l) => l.tutor_id === viewer.id && l.counts_as_late); // Only their own late starts (an admin who also tutors sees everyone's in the list; a notice followed by an on-time sign-on does not count).
  const toRecord = sessions.filter( // Sessions to record:
    (s) => s.status === "scheduled" && new Date(s.starts_at).getTime() <= now && (isAdmin || s.tutor_id === viewer.id), // still scheduled but started, and theirs (or any, for admins).
  ); // End of the filter.

  return ( // Shows:
    <DashboardFrame // the dashboard tabs and side menu:
      role={role} // for this dashboard,
      roles={viewer.roles} // with the person's roles (for the tabs and numbers),
      current="sessions" // with the Sessions tab open,
      sub={section} // on the open section,
      items={sections.map((s) => ({ // with Sessions' sections under it, each with:
        ...s, // its details,
        href: here(s.id), // its address in this dashboard,
        count: // its number:
          s.id === "sessions" && makeupsToPick.length + makeupsToConfirm.length // for the overview, make-up times to pick or confirm,
            ? makeupsToPick.length + makeupsToConfirm.length // that number,
            : s.id === "bookings" && waitingForMe.length + familyToApprove.length // for bookings, requests and offers waiting,
            ? waitingForMe.length + familyToApprove.length // that number,
            : s.id === "notices" && unread // for notices, unread ones,
              ? unread // that number,
              : s.id === "next-term" && renewalsToAnswer // for book again, questions to answer,
                ? renewalsToAnswer // that number,
                : counts[s.id] || undefined, // otherwise the to-do number (if any).
      }))} // (end of the sections)
    >{/* (end of the frame's settings) */}
      {section === "sessions" && ( // The sessions section:
        <>{/* (a group) */}
          {(isTutor || isFamily) && <TutorChangeAnswerBox />}{/* tutor changes CLG has asked this tutor or family to confirm (shows nothing if none), */}
          {myCheck && ( // If the tutor has an availability check:
            <Card // a card:
              title="Is your availability right for next term?" // its title,
              description="Families will soon be booking for next term. Please check your weekly availability, then let us know. Booked sessions are not changed." // its help text.
            >{/* (end of the card's settings) */}
              <p className="mb-3 text-sm">{/* a line: */}
                <TextLink href="/dashboard/tutor?section=hours">Check or update your availability</TextLink>{/* a link to their availability. */}
              </p>{/* End of the line. */}
              <AvailabilityCheckForm id={myCheck.id} />{/* the confirm form. */}
            </Card> // End of the card.
          )}{/* End of this part. */}
          {!isDesk && planMissing && ( // For a payer who has not chosen a plan yet:
            <p className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">{/* an amber notice: */}
              Please choose how often you would like to pay before booking or approving sessions.{" "}{/* what is needed, then, */}
              <TextLink href="/billing">Choose in Billing</TextLink>{/* a link to Billing. */}
            </p> // End of the notice.
          )}{/* End of this part. */}
          {!isDesk && familyToApprove.length > 0 && ( // For families with offers to approve:
            <p className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">{/* an amber notice: */}
              CLG has offered {familyToApprove.length === 1 ? "a session time" : `${familyToApprove.length} session times`}{" "}{/* how many, then, */}
              for you to approve. <TextLink href={here("bookings")}>See offers</TextLink>{/* a link to see them. */}
            </p> // End of the notice.
          )}{/* End of this part. */}
          {waitingForMe.length > 0 && ( // If the tutor has requests to answer:
            <p className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">{/* an amber notice: */}
              You have {waitingForMe.length} booking request{waitingForMe.length > 1 ? "s" : ""} to answer.{" "}{/* how many, then, */}
              <TextLink href={here("bookings")}>See requests</TextLink>{/* a link to see them. */}
            </p> // End of the notice.
          )}{/* End of this part. */}
          {makeupsToPick.length > 0 && ( // If there are make-up times to pick:
            <Card // a card:
              title="Pick a make-up time" // its title,
              description="A session was cancelled and two other times were offered in the same week. Pick one to book it, or say neither works." // its help text.
            >{/* (end of the card's settings) */}
              <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                {makeupsToPick.map((o) => ( // for each offer:
                  <li key={o.id} className="space-y-3 py-4 first:pt-0">{/* a row: */}
                    <p>{/* what was cancelled: */}
                      <span className="font-medium">{o.student_name}</span>{/* the student, */}
                      <span className="text-zinc-600">{/* in grey: */}
                        {" "}{/* a space, */}
                        · {o.subject} with {o.tutor_name} · was {sessionWhen(o.cancelled_starts_at)}{/* the subject, tutor and cancelled time, */}
                        {o.reason && ` · ${o.reason}`}{/* and the reason (if any). */}
                      </span>{/* End of the grey part. */}
                    </p>{/* End of the line. */}
                    <MakeupAnswerForm offerId={o.id} option1={o.option_1 as string} option2={o.option_2 as string} />{/* the pick form. */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul>{/* End of the list. */}
            </Card> // End of the card.
          )}{/* End of this part. */}
          {makeupsToConfirm.length > 0 && ( // If there are picked make-up times to confirm:
            <Card // a card:
              title="Confirm a make-up time" // its title,
              description="CLG offered times after a cancel, and the other side picked one. It is booked once you confirm." // its help text.
            >{/* (end of the card's settings) */}
              <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                {makeupsToConfirm.map((o) => ( // for each offer:
                  <li key={o.id} className="space-y-3 py-4 first:pt-0">{/* a row: */}
                    <p>{/* what was cancelled: */}
                      <span className="font-medium">{o.student_name}</span>{/* the student, */}
                      <span className="text-zinc-600">{/* in grey: */}
                        {" "}{/* a space, */}
                        · {o.subject} with {o.tutor_name} · was {sessionWhen(o.cancelled_starts_at)}{/* the subject, tutor and cancelled time, */}
                        {o.reason && ` · ${o.reason}`}{/* and the reason (if any). */}
                      </span>{/* End of the grey part. */}
                    </p>{/* End of the line. */}
                    <MakeupConfirmForm offerId={o.id} pickedAt={o.picked_at as string} />{/* the confirm form. */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul>{/* End of the list. */}
            </Card> // End of the card.
          )}{/* End of this part. */}
          {otherMakeups.length > 0 && ( // If there are other make-up offers to show:
            <Card // a card:
              collapsible // can fold,
              defaultOpen={false} // folded to start,
              title="Make-up times" // its title,
              description="Times offered after a cancel in the last 30 days, and where each is up to." // its help text.
            >{/* (end of the card's settings) */}
              <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                {otherMakeups.map((o) => ( // for each offer:
                  <li key={o.id} className="flex flex-wrap items-baseline justify-between gap-2 py-3 first:pt-0">{/* a row: */}
                    <span>{/* (a group) */}
                      <span className="font-medium">{o.student_name}</span>{/* the student, */}
                      <span className="text-zinc-600">{/* in grey: */}
                        {" "}{/* a space, */}
                        · {o.subject} with {o.tutor_name} · was {sessionWhen(o.cancelled_starts_at)}{/* the subject, tutor and cancelled time, */}
                        {(o.status === "picked" || o.status === "confirming") && o.picked_at && ` · ${o.status === "picked" ? "now" : "picked"} ${sessionWhen(o.picked_at)}`}{/* the new time, if one was picked, */}
                        {o.status === "waiting" && o.option_1 && o.option_2 && ` · offered ${sessionWhen(o.option_1)} or ${sessionWhen(o.option_2)}`}{/* the two times, while waiting, */}
                        {o.status === "declined" && o.answer_note && ` · "${o.answer_note}"`}{/* why neither works, if said. */}
                      </span>{/* End of the grey part. */}
                    </span>{/* End of the group. */}
                    <span className="rounded-full bg-zinc-100 px-3 py-0.5 text-xs text-zinc-600">{/* a grey tag: */}
                      {o.status === "waiting" // where it's up to: waiting for a pick,
                        ? `Waiting for ${o.answer_by === "tutor" ? "the tutor" : "the family"} to pick` // (names who picks),
                        : o.status === "confirming" // waiting for the other side to confirm,
                          ? `Waiting for ${o.answer_by === "tutor" ? "the family" : "the tutor"} to confirm` // (names who confirms),
                          : (MAKEUP_STATUS_NAMES[o.status] ?? o.status)}{/* or the stage's name. */}
                    </span>{/* End of the tag. */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul>{/* End of the list. */}
            </Card> // End of the card.
          )}{/* End of this part. */}
          {toRecord.length > 0 && ( // If sessions need recording:
            <Card title="Did these sessions happen?" description="Mark each one done or a no-show.">{/* a card: */}
              <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                {toRecord.map((s) => ( // for each session:
                  <li key={s.id} className="flex flex-wrap items-center justify-between gap-3 py-3 first:pt-0">{/* a row: */}
                    <span>{/* (a group) */}
                      <span className="font-medium">{sessionWhen(s.starts_at)}</span>{/* when, */}
                      <span className="text-zinc-600">{/* in grey: */}
                        {" "}{/* a space, */}
                        · {s.student_name} · {s.subject}{/* the student and subject. */}
                      </span>{/* End of the grey part. */}
                    </span>{/* End of the group. */}
                    <OutcomeForm id={s.id} />{/* the done or no-show form. */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul>{/* End of the list. */}
            </Card> // End of the card.
          )}{/* End of this part. */}
          {recentMine.length > 0 && ( // If the tutor had sessions in the last week:
            <Card // a card:
              collapsible // can fold,
              defaultOpen={false} // folded to start,
              title="Your recent sessions" // its title,
              description="You are signed off at the booked end time. If you finished at a different time, tell CLG here within a week." // its help text.
            >{/* (end of the card's settings) */}
              <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                {recentMine.map((s) => { // for each session:
                  const sign = signOf.get(s.id); // its sign-on details,
                  return ( // shows:
                    <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 py-3 first:pt-0">{/* a row: */}
                      <span>{/* (a group) */}
                        <span className="font-medium">{sessionWhen(s.starts_at)}</span>{/* when, */}
                        <span className="text-zinc-600">{/* in grey: */}
                          {" "}{/* a space, */}
                          · {s.student_name} · {s.subject}{/* the student and subject. */}
                        </span>{/* End of the grey part. */}
                      </span>{/* End of the group. */}
                      {sign?.times_confirmed_at ? ( // if times are confirmed:
                        <span className="text-xs text-zinc-600">Times confirmed</span> // says so.
                      ) : sign?.tutor_end_at ? ( // if they gave a different end time:
                        <span className="text-xs text-zinc-600">{/* a grey note: */}
                          Finished {clockTime(localClock(sign.tutor_end_at))}: waiting for CLG{/* the end time, waiting for CLG. */}
                        </span> // End of the note.
                      ) : ( // otherwise:
                        <EndTimeForm id={s.id} date={localDate(s.starts_at)} bookedEnd={localClock(s.ends_at)} /> // the end time form.
                      )}{/* End of this part. */}
                    </li> // End of the row.
                  ); // End of what's shown for this session.
                })}{/* End of the loop. */}
              </ul>{/* End of the list. */}
            </Card> // End of the card.
          )}{/* End of this part. */}
          {myLate.length > 0 && ( // If the tutor had late starts in the last 90 days:
            <Card // a card:
              collapsible // can fold,
              defaultOpen={false} // folded to start,
              title={`Your late starts (last 90 days): ${myLate.length}`} // its title, with how many,
              description="Sessions you signed on to more than 5 minutes after the start, or told CLG you were running late for. CLG reviews these." // its help text.
            >{/* (end of the card's settings) */}
              <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                {myLate.map((l) => ( // for each one:
                  <li key={l.id} className="py-2 first:pt-0">{/* a row: */}
                    <span className="font-medium">{sessionWhen(l.starts_at)}</span>{/* when, */}
                    <span className="text-zinc-600">{/* in grey: */}
                      {" "}· {l.student_first_name} · {l.subject}{/* the learner and subject, */}
                      {l.signed_on_late_minutes != null ? ` · signed on ${l.signed_on_late_minutes} minutes late` : ""}{/* how late they signed on, */}
                      {l.told_minutes != null ? ` · you gave notice${l.told_before_start ? " before the start" : " after the start"}` : " · no notice given"}{/* and whether they gave notice. */}
                    </span>{/* End of the grey part. */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul>{/* End of the list. */}
            </Card> // End of the card.
          )}{/* End of this part. */}
          <Card title="Upcoming sessions" description="Times are Adelaide time.">{/* the upcoming sessions card: */}
            {upcoming.length === 0 ? ( // if none:
              <Empty>{/* a line: */}
                No sessions booked yet.{/* says none yet, */}
                {isDesk ? ( // for front desk:
                  <>{/* (a group) */}
                    {" "}{/* a space, */}
                    <TextLink href={here("book")}>Book a session</TextLink>{/* a link to book one. */}
                  </> // End of the group.
                ) : ( // otherwise:
                  canBook && " CLG will send you a time to approve." // for families, that CLG will send a time.
                )}{/* End of this part. */}
              </Empty> // End of the line.
            ) : ( // otherwise:
              <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                {upcoming.map((s) => ( // for each session:
                  <li key={s.id} className="flex flex-wrap items-baseline justify-between gap-2 py-3 first:pt-0">{/* a row: */}
                    <span>{/* (a group) */}
                      <span className="font-medium">{sessionWhen(s.starts_at)}</span>{/* when, */}
                      <span className="text-zinc-600">{/* in grey: */}
                        {" "}{/* a space, */}
                        · {s.student_name} with {s.tutor_name} · {s.subject} · {placeLabel(s.delivery, s.library_name)}{/* the student, tutor, subject and place. */}
                      </span>{/* End of the grey part. */}
                      {s.meeting_url && s.status === "scheduled" && ( // If it has an online link and is still on:
                        <a href={s.meeting_url} className="ml-2 text-teal-800 underline" target="_blank" rel="noreferrer">{/* a join link: */}
                          Join{/* its words, */}
                        </a> // end of the link.
                      )}{/* End of this part. */}
                    </span>{/* End of the group. */}
                    {s.status === "scheduled" ? ( // if it's still on:
                      <span className="flex flex-wrap items-center gap-3">{/* a row of actions: */}
                        {isTutor && // in the tutor dashboard,
                          s.tutor_id === viewer.id && // for the tutor's own session,
                          new Date(s.starts_at).getTime() - 30 * 60 * 1000 <= now && // from 30 minutes before it starts:
                          (signOf.get(s.id)?.signed_on_at ? ( // if signed on,
                            <span className="rounded-full bg-teal-50 px-3 py-0.5 text-xs text-teal-900">Signed on</span> // a "Signed on" tag,
                          ) : ( // otherwise:
                            <SignOnForm id={s.id} atLibrary={s.delivery === "library"} /> // the sign-on form (location check for a library).
                          ))}{/* End of this part. */}
                        {isTutor && // in the tutor dashboard,
                          s.tutor_id === viewer.id && // for the tutor's own session,
                          !signOf.get(s.id)?.signed_on_at && // not yet signed on,
                          new Date(s.starts_at).getTime() - 3 * 3600 * 1000 <= now && // from 3 hours before it starts
                          new Date(s.starts_at).getTime() + 30 * 60 * 1000 >= now && ( // until 30 minutes after:
                            <RunningLateForm id={s.id} /> // the running late form (Carla, 18 Nov 2026).
                          )}{/* End of this part. */}
                        {new Date(s.starts_at).getTime() > now && ( // if it hasn't started:
                          <CancelForm id={s.id} kind="session" isAdmin={isDesk} isTutor={isTutor} startsAt={s.starts_at} today={localToday()} /> // the cancel form (reason and two make-up times in the session's week).
                        )}{/* End of this part. */}
                      </span> // End of the actions.
                    ) : ( // otherwise:
                      <span className="rounded-full bg-zinc-100 px-3 py-0.5 text-xs text-zinc-600">{/* a grey tag: */}
                        {SESSION_STATUS_NAMES[s.status] ?? s.status}{/* its status, */}
                        {s.cancelled_by_role && ` by ${s.cancelled_by_role === "admin" ? "CLG" : s.cancelled_by_role}`}{/* and who cancelled it (if anyone). */}
                      </span> // End of the tag.
                    )}{/* End of this part. */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul> // End of the list.
            )}{/* End of this part. */}
          </Card>{/* End of the card. */}
        </> // End of the group.
      )}{/* End of the sessions section. */}

      {section === "bookings" && ( // The bookings section:
        <Card title="Bookings" description="Each booking is the same time every week, up to its last date. Newest first.">{/* a card: */}
          {isDesk && <p className="mb-4 text-sm">Need to give a student a new tutor for sessions already booked? <TextLink href="/schedule/change-tutor">Change tutor on booked sessions</TextLink></p>}{/* for matching admins, the way to move sessions to a new tutor, */}
          {bookings.length > 0 && ( // when there are bookings, filter buttons:
            <nav aria-label="Show bookings" className="mb-4 flex flex-wrap gap-2 text-sm">{/* a row of filter links: */}
              {BOOKING_FILTERS.map((f) => { // for each filter:
                const n = f.key === "all" ? bookings.length : bookings.filter((b) => bookingFilterKey(b) === f.key).length; // how many bookings it has,
                if (n === 0 && f.key !== show) return null; // hidden when it has none (unless it's the one chosen),
                return ( // shows:
                  <Link // a link:
                    key={f.key} // (its key in the list)
                    href={f.key === "all" ? here("bookings") : `${here("bookings")}&show=${f.key}`} // to the list with this filter,
                    aria-current={f.key === show ? "page" : undefined} // marked as current when chosen,
                    className={`rounded-full border px-3 py-1 ${f.key === show ? "border-zinc-800 bg-zinc-800 text-white" : "border-zinc-200 text-zinc-700 hover:bg-zinc-50"}`} // dark when chosen, outlined otherwise.
                  >{/* (end of the link's settings) */}
                    {f.label} ({n}){/* the filter's name and count. */}
                  </Link> // End of the link.
                ); // End of what's shown.
              })}{/* End of the filters. */}
            </nav> // End of the filter row.
          )}{/* (end of the filter check) */}
          {shownBookings.length === 0 ? ( // if none to show:
            <Empty>{bookings.length === 0 ? "No bookings yet." : "No bookings with this status."}</Empty> // says so.
          ) : ( // otherwise:
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {shownBookings.map((b) => { // for each booking shown:
                const live = b.status === "confirmed" || (b.status === "requested" && !b.expired); // whether it's still running or waiting,
                const approval = approvals.get(b.id); // its approvals,
                const forMe = waitingForMe.some((w) => w.id === b.id); // whether the tutor must answer it,
                const forFamily = !isDesk && familyToApprove.some((w) => w.id === b.id); // whether the family must approve it,
                const waiting = b.status === "requested" && !b.expired && approval?.needs_family_ok; // whether it's waiting for confirmation,
                return ( // shows:
                  <li key={b.id} className="space-y-2 py-4 first:pt-0">{/* a row: */}
                    <div className="flex flex-wrap items-baseline justify-between gap-2">{/* the top line: */}
                      <span>{/* (a group) */}
                        <span className="font-medium">{/* in bold: */}
                          {WEEKDAY_NAMES[b.weekday - 1]}s, {clockTime(b.start_time)} ({lengthLabel(b.minutes)}){/* the weekday, time and length. */}
                        </span>{/* End of the bold part. */}
                        <span className="text-zinc-600">{/* in grey: */}
                          {" "}{/* a space, */}
                          · {b.student_name}{/* the student, */}
                          {b.year_level && ` (${b.year_level})`} with {b.tutor_name} · {b.subject} ·{" "}{/* their year level, tutor and subject, then, */}
                          {placeLabel(b.delivery, b.library_name)}{/* the place. */}
                        </span>{/* End of the grey part. */}
                      </span>{/* End of the group. */}
                      <span // a status tag:
                        className={`rounded-full px-3 py-0.5 text-xs ${
                          b.status === "confirmed" ? "bg-teal-50 text-teal-900" : "bg-zinc-100 text-zinc-600"
                        }`} // (teal when confirmed, grey otherwise)
                      >{/* (end of the tag's settings) */}
                        {b.expired ? "Expired" : waiting ? "Waiting for confirmation" : (BOOKING_STATUS_NAMES[b.status] ?? b.status)}{/* its status. */}
                      </span>{/* End of the tag. */}
                    </div>{/* End of the top line. */}
                    <p className="text-zinc-600">{/* a grey line: */}
                      {shortDate(b.first_date)} to {shortDate(b.last_date)}{/* the first and last dates, */}
                      {b.status === "confirmed" && ` · ${b.sessions_left} session${b.sessions_left === 1 ? "" : "s"} to come`}{/* sessions to come (if confirmed), */}
                      {b.status === "requested" && // if waiting,
                        !b.expired && // and not expired,
                        ` · ${waiting ? "to approve" : "tutor to answer"} by ${new Date(b.tutor_reply_by).toLocaleString("en-AU", {
                          weekday: "short",
                          hour: "numeric",
                          minute: "2-digit",
                          timeZone: "Australia/Adelaide",
                        })}`}{/* who must answer and by when. */}
                    </p>{/* End of the line. */}
                    {forMe && goalOf.get(b.id) && <p className="text-zinc-600">Goal: {goalOf.get(b.id)}</p>}{/* the goal (for the tutor to answer). */}
                    {b.family_note && <p className="text-zinc-600">Family note: {b.family_note}</p>}{/* the family's note (if any). */}
                    {b.tutor_note && <p className="text-zinc-600">Tutor note: {b.tutor_note}</p>}{/* the tutor's note (if any). */}
                    {waiting && approval && ( // If waiting for confirmation:
                      <p className="text-zinc-700">{/* a line: */}
                        Tutor: {approval.tutor_ok_at ? "approved ✓" : "waiting"} · Family:{" "}{/* whether the tutor and, */}
                        {approval.family_ok_at ? "approved ✓" : "waiting"}{/* the family have approved. */}
                      </p> // End of the line.
                    )}{/* End of this part. */}
                    {forMe && <AnswerForm bookingId={b.id} />}{/* The tutor's accept or decline form. */}
                    {forFamily && <ApproveForm bookingId={b.id} />}{/* The family's approve form. */}
                    {live && !forMe && !forFamily && <CancelForm id={b.id} kind="booking" isAdmin={isDesk} />}{/* The cancel form (when nothing is waiting on this person). */}
                  </li> // End of the row.
                ); // End of what's shown for this booking.
              })}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of this part. */}
        </Card> // End of the card.
      )}{/* End of the bookings section. */}

      {section === "book" && isDesk && <BookSection params={params} viewerId={viewer.id} isAdmin={isDesk} />}{/* The book section (front desk). */}
      {section === "book" && isAdmin && <SummaryTimeCard />}{/* The summary time setting (owner and operations admins). */}

      {section === "places" && isTutor && <PlacesSection viewerId={viewer.id} />}{/* The "where you teach" section (tutors). */}

      {section === "libraries" && isAdmin && <LibrariesAdminSection filter={one(params.libs)} search={one(params.q)} hrefFor={(f) => `${here("libraries")}&libs=${f}${one(params.q) ? `&q=${encodeURIComponent(one(params.q))}` : ""}`} hiddenFields={{ as: role, section: "libraries" }} />}{/* The libraries section (admins). */}

      {section === "requests" && (canBook || isTutor) && ( // The requests section:
        <RequestsSection viewerId={viewer.id} isAdmin={isDesk} isTutor={isTutor} canAsk={canBook && !isDesk} /> // requests (only families can ask).
      )}{/* End of this part. */}

      {section === "blocks" && ( // The blocks section:
        <BlocksSection // blocks:
          viewerId={viewer.id} // the signed-in person,
          isAdmin={isAdmin} // whether they're an admin,
          isTutor={isTutor} // whether they're a tutor,
          bookings={bookings.filter((b) => b.status !== "declined")} // their bookings (not declined ones),
          familyStudentIds={isFamily ? [...familyIds] : null} // and, in a family dashboard, their own children (and themselves).
        /> // (end of the blocks)
      )}{/* End of this part. */}

      {section === "times" && isAdmin && <TimesSection />}{/* The times to check section (admins). */}

      {section === "tutor-availability" && isAdmin && <TutorAvailabilitySection />}{/* The tutor availability section (admins). */}

      {section === "notices" && <NoticesSection viewerId={viewer.id} unread={unread} isAdmin={isAdmin} />}{/* The notices section (with the quiet hours setting for owner and operations admins). */}

      {section === "away" && <AwaySection viewerId={viewer.id} isAdmin={isAdmin} isTutor={isTutor} familyStudentIds={isFamily ? [...familyIds] : null} />}{/* The away dates section (this dashboard's own). */}

      {section === "waitlist" && isDesk && <WaitlistSection isAdmin={isDesk} />}{/* The waitlist section (front desk). */}

      {section === "next-term" && canBook && <NextTermSection isAdmin={isDesk} />}{/* The book again section. */}


      {section === "child-places" && canBook && <ChildPlacesSection viewerId={viewer.id} isAdmin={isAdmin} params={params} />}{/* The session places section. */}
      {section === "booking-length" && canBook && <BookingLengthSection viewerId={viewer.id} isAdmin={isAdmin} params={params} />}{/* The how long to book section. */}
    </DashboardFrame> // End of the dashboard frame.
  ); // End of what's shown.
} // End of SchedulePage.

// ---------------------------------------------------------------------------
// Book a session: choose the child, subject, length and places, then a time.
// ---------------------------------------------------------------------------
async function BookSection({ // Takes:
  params, // the address's settings,
  viewerId, // the signed-in person,
  isAdmin, // and whether they're an admin.
}: { // The types of those:
  params: Record<string, string | string[] | undefined>; // the settings,
  viewerId: string; // an id,
  isAdmin: boolean; // yes or no.
}) { // End of the types.
  const supabase = await createClient(); // Connects to the database.
  const [studentsRes, linksRes, librariesRes] = await Promise.all([ // Reads three things at once:
    supabase.from("students").select("id, full_name, year_level, account_id").order("full_name"), // the students, by name,
    supabase.from("parent_student_links").select("student_id").eq("parent_id", viewerId), // their own children,
    supabase.from("libraries").select("id, name, suburb").eq("active", true).order("name"), // libraries in use, by name.
  ]); // End of the reads.
  const mine = new Set((linksRes.data ?? []).map((l) => l.student_id as string)); // Their own children.
  // Admins can book for anyone; families only for their own children.
  const students = (studentsRes.data ?? []).filter((s) => isAdmin || mine.has(s.id) || s.account_id === viewerId); // The students they can book for.
  const libraries = librariesRes.data ?? []; // The libraries.

  const studentId = one(params.student) || (students.length === 1 ? students[0].id : ""); // The chosen student (or the only one).
  const student = students.find((s) => s.id === studentId); // That student.
  const subjectsRes = student // If chosen, reads:
    ? await supabase.from("student_subjects").select("subject, working_level").eq("student_id", student.id).order("added_at") // their subjects and levels,
    : null; // otherwise none.
  const subjectRows = (subjectsRes?.data ?? []) as { subject: string; working_level: string | null }[]; // The subjects and levels.
  const subjects = subjectRows.map((r) => r.subject); // The subject names.

  const subject = one(params.subject) || subjects[0] || ""; // The chosen subject (or the first).
  // Shown to the person matching: school year and the level they work at in this subject.
  const workingLevel = subjectRows.find((r) => r.subject.toLowerCase() === subject.toLowerCase())?.working_level ?? null; // The level they work at in this subject.
  const minutes = Number(one(params.minutes)) || 60; // The length (1 hr if not set).
  const go = one(params.go) === "1"; // Whether the search button was pressed.
  // "auto" (from the Matching tab) searches straight away with the saved places.
  const searched = go || one(params.auto) === "1"; // Whether to search.
  // Before a search, start from the places saved for this child.
  const savedRes = // Reads saved places:
    student && !go // if a student is chosen and before a search,
      ? await supabase.from("student_places").select("online, library_ids").eq("student_id", student.id).maybeSingle() // their saved places,
      : null; // otherwise none.
  const saved = savedRes?.data as { online: boolean; library_ids: string[] } | null | undefined; // The saved places.
  // For the end date: the family's "book until" date and the student's term dates.
  const [untilRes, termsRes] = student // Reads two things:
    ? await Promise.all([ // if a student is chosen, at once:
        supabase.from("student_places").select("book_until").eq("student_id", student.id).maybeSingle(), // their "book until" date,
        supabase.rpc("student_term_dates", { p_student: student.id }), // and their term dates.
      ]) // (end of the reads)
    : [null, null]; // otherwise none.
  const bookUntil = (untilRes?.data?.book_until as string | null | undefined) ?? null; // The "book until" date (if any).
  const terms = (termsRes?.data ?? []) as StudentTerm[]; // The term dates.
  const online = go ? one(params.online) === "1" : (saved?.online ?? true); // Online or not (from the search, or saved places, or yes).
  const chosenLibs = go ? list(params.lib) : (saved?.library_ids ?? []); // The libraries chosen (from the search, or saved places).
  const days = list(params.day).map(Number).filter((d) => d >= 1 && d <= 7); // The days chosen (1 to 7 only).
  const earliest = one(params.from); // The earliest time.
  const latest = one(params.to); // The latest time.
  const tomorrow = addDays(localToday(), 1); // Tomorrow.
  const start = one(params.start) >= tomorrow ? one(params.start) : tomorrow; // The first date (tomorrow at the earliest).

  let options: TimeOption[] = []; // The times found.
  let searchError = ""; // A search problem message (if any).
  if (searched && student && subject) { // If searching for a student and subject:
    const { data, error } = await supabase.rpc("offer_options", { // reads suitable times:
      p_student: student.id, // for this student,
      p_subject: subject, // this subject,
      p_minutes: minutes, // this length,
      p_online: online, // online or not,
      p_libraries: chosenLibs, // these libraries,
      p_first_date: start, // from this date,
      p_weekdays: days.length ? days : null, // on these days (any if none chosen),
      p_earliest: earliest || null, // no earlier than (if set),
      p_latest: latest || null, // finished by (if set).
    }); // End of the read.
    if (error) searchError = /violates|syntax|relation|column|function/i.test(error.message) ? "Could not search. Please try again." : error.message; // If it failed: a plain message (the database's words unless technical).
    options = (data ?? []) as TimeOption[]; // The times found.
  } // End of the search.

  const box = "flex items-start gap-2 text-sm"; // The style for a tick box line.
  return ( // Shows:
    <>{/* (a group) */}
      <Card // the booking card:
        title="Book a session" // its title,
        description="Choose what is needed and where. You will see only tutors who suit and are available, then pick a time." // its help text.
      >{/* (end of the card's settings) */}
        {student && subject && ( // If a student and subject are chosen:
          <p className="mb-4 rounded-lg bg-zinc-50 px-3 py-2 text-sm">{/* a summary line: */}
            <span className="font-medium">{student.full_name}</span> · {subject} · School year:{" "}{/* the name, subject and school year, */}
            {student.year_level ?? "not set"} · Working level: {workingLevel ?? "not sure"}{/* the year level and working level. */}
          </p> // End of the line.
        )}{/* End of this part. */}
        {students.length === 0 ? ( // if no students:
          <Empty>{/* a line: */}
            Add your child first. <TextLink href="/dashboard/parent?section=add">Add a child</TextLink>{/* asks to add a child first. */}
          </Empty> // End of the line.
        ) : ( // otherwise:
          <form method="get" action="/schedule" className="space-y-5">{/* the search form (stays on this page): */}
            <input type="hidden" name="as" value="admin" />{/* the admin dashboard (hidden; only front desk books), */}
            <input type="hidden" name="section" value="book" />{/* this section (hidden), */}
            <input type="hidden" name="go" value="1" />{/* marks the search button pressed (hidden), */}
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns: */}
              <Select label="Who is it for?" name="student" defaultValue={studentId} required>{/* the student drop-down: */}
                <option value="" disabled>{/* a "Choose…" prompt that can't be picked: */}
                  Choose…{/* its words, */}
                </option>{/* end of the prompt. */}
                {students.map((s) => ( // for each student:
                  <option key={s.id} value={s.id}>{/* an option: */}
                    {s.full_name}{/* their name, */}
                    {s.year_level ? ` (${s.year_level})` : ""}{/* and year level (if known). */}
                  </option> // End of the option.
                ))}{/* End of the loop. */}
              </Select>{/* End of the drop-down. */}
              {student && subjects.length > 0 ? ( // if the student has subjects:
                <Select label="Subject" name="subject" defaultValue={subject} required>{/* the subject drop-down: */}
                  {subjects.map((s) => ( // for each subject:
                    <option key={s} value={s}>{/* an option: */}
                      {s}{/* its name, */}
                    </option> // end of the option.
                  ))}{/* End of the loop. */}
                </Select> // End of the drop-down.
              ) : student ? ( // if the student has none:
                <p className="self-end text-sm text-zinc-600">{/* a line: */}
                  No subjects asked for yet. Add them under &quot;See or change details&quot; on your dashboard.{/* says where to add them. */}
                </p> // End of the line.
              ) : ( // if no student chosen:
                <p className="self-end text-sm text-zinc-600">Choose who it is for, then press Find times.</p> // says to choose one.
              )}{/* End of this part. */}
            </div>{/* End of the columns. */}
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">{/* three columns: */}
              <Select label="How long" name="minutes" defaultValue={String(minutes)}>{/* the length drop-down: */}
                {SESSION_LENGTHS.map((m) => ( // for each length:
                  <option key={m} value={m}>{/* an option: */}
                    {lengthLabel(m)}{/* its wording, */}
                  </option> // end of the option.
                ))}{/* End of the loop. */}
              </Select>{/* End of the drop-down. */}
              <Field label="Starting from" name="start" type="date" defaultValue={start} min={tomorrow} />{/* the first date (tomorrow at the earliest). */}
            </div>{/* End of the columns. */}

            <fieldset className="space-y-2">{/* the "Where" group: */}
              <legend className="mb-1 text-sm font-medium text-zinc-800">Where</legend>{/* its heading, */}
              <label className={box}>{/* a tick box line: */}
                <input type="checkbox" name="online" value="1" defaultChecked={online} className="mt-1" /> Online{/* online. */}
              </label>{/* End of the line. */}
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">{/* two columns: */}
                {libraries.map((l) => ( // for each library:
                  <label key={l.id} className={box}>{/* a tick box line: */}
                    <input // the tick box:
                      type="checkbox" // a tick box,
                      name="lib" // named lib,
                      value={l.id} // for this library,
                      defaultChecked={chosenLibs.includes(l.id)} // ticked if chosen,
                      className="mt-1" // styled.
                    />{/* (end of the tick box) */}
                    <span>{/* (a group) */}
                      {l.name}{/* its name, */}
                      {l.suburb && <span className="text-zinc-500"> · {l.suburb}</span>}{/* and suburb (if known). */}
                    </span>{/* End of the group. */}
                  </label> // End of the line.
                ))}{/* End of the loop. */}
              </div>{/* End of the columns. */}
              <p className="text-xs text-zinc-600">{/* a help line: */}
                In-person sessions are at public libraries. Libraries within the family&apos;s travel distance (set under
                Session places) are included without ticking them, and so are learners&apos; homes within a tutor&apos;s
                travel distance. Ticking more places and times means more tutors can be offered, but no match is
                guaranteed.{/* (end of the text) */}
              </p>{/* End of the help line. */}
            </fieldset>{/* End of the group. */}

            <fieldset className="space-y-2">{/* the "When suits" group: */}
              <legend className="mb-1 text-sm font-medium text-zinc-800">When suits (optional)</legend>{/* its heading, */}
              <div className="flex flex-wrap gap-x-4 gap-y-2">{/* a row: */}
                {WEEKDAY_NAMES.map((d, i) => ( // for each weekday:
                  <label key={d} className={box}>{/* a tick box line: */}
                    <input type="checkbox" name="day" value={i + 1} defaultChecked={days.includes(i + 1)} className="mt-1" />{" "}{/* the tick box, then a space, */}
                    {d.slice(0, 3)}{/* the short day name. */}
                  </label> // End of the line.
                ))}{/* End of the loop. */}
              </div>{/* End of the row. */}
              <div className="grid grid-cols-2 gap-4 sm:w-2/3">{/* two columns: */}
                <Field label="No earlier than" name="from" type="time" defaultValue={earliest} />{/* no earlier than, */}
                <Field label="Finished by" name="to" type="time" defaultValue={latest} />{/* finished by. */}
              </div>{/* End of the columns. */}
            </fieldset>{/* End of the group. */}

            <Button type="submit">Find times</Button>{/* the search button. */}
          </form> // End of the form.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}

      {searched && student && subject && ( // After a search:
        <Card title="Available times" description={`${subject} for ${student.full_name}, ${lengthLabel(minutes)} each week.`}>{/* the times card: */}
          {searchError ? ( // if the search failed:
            <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">{/* an alert: */}
              {searchError}{/* the problem. */}
            </p> // End of the alert.
          ) : options.length === 0 ? ( // if nothing found:
            <>{/* (a group) */}
              <Empty>{/* a line: */}
                No available times match. Try more days, a wider time, online, or more libraries, or join the waitlist and
                CLG will be in touch when a suitable tutor is available.{/* (end of the text) */}
              </Empty>{/* End of the line. */}
              <div className="mt-4">{/* a box: */}
                <WaitlistForm // the waitlist form:
                  request={{ // with the request:
                    student_id: student.id, // the student,
                    subject, // the subject,
                    minutes, // the length,
                    online: online ? "1" : "0", // online or not,
                    libraries: chosenLibs.join(","), // the libraries,
                    weekdays: days.join(","), // the days,
                    earliest, // no earlier than,
                    latest, // finished by.
                  }} // (end of the request)
                />{/* End of the form. */}
              </div>{/* End of the box. */}
            </> // End of the group.
          ) : ( // otherwise:
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {options.slice(0, 40).map((o, i) => ( // for the first 40 times:
                <li // a row:
                  key={`${o.tutor_id}-${o.weekday}-${o.start_time}-${o.delivery}-${o.library_id}`} // one per time,
                  className={`flex flex-wrap items-center justify-between gap-2 py-3 first:pt-0 ${isAdmin && i === 0 ? "rounded-lg bg-teal-50 px-3" : ""}`} // the first highlighted for admins.
                >{/* (end of the row's settings) */}
                  <span>{/* (a group) */}
                    {isAdmin && i === 0 && ( // For admins, the first time:
                      <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-teal-800">Suggested</span> // "Suggested".
                    )}{/* End of this part. */}
                    <span className="font-medium">{/* in bold: */}
                      {WEEKDAY_NAMES[o.weekday - 1]} {clockTime(o.start_time)} to {clockTime(o.end_time)}{/* the day and times. */}
                    </span>{/* End of the bold part. */}
                    <span className="text-zinc-600">{/* in grey: */}
                      {" "}{/* a space, */}
                      · {o.tutor_name} · {placeLabel(o.delivery, o.library_name)}{/* the tutor and place. */}
                    </span>{/* End of the grey part. */}
                    {o.learning_support && ( // If the tutor has learning support experience:
                      <span className="ml-2 rounded-full bg-teal-50 px-2 text-xs text-teal-900">{/* a tag: */}
                        Learning support experience{/* its words, */}
                      </span> // end of the tag.
                    )}{/* End of this part. */}
                    {o.preferred && ( // If it's a preferred time:
                      <span className="ml-2 rounded-full bg-amber-50 px-2 text-xs text-amber-900">Preferred time</span> // a tag.
                    )}{/* End of this part. */}
                    {isAdmin && o.joins_other_sessions && ( // For admins, if it sits next to the tutor's other sessions:
                      <span className="ml-2 rounded-full bg-amber-50 px-2 text-xs text-amber-900">Joins tutor&apos;s block</span> // a tag.
                    )}{/* End of this part. */}
                  </span>{/* End of the group. */}
                  <BookForm // the book form:
                    option={{ // the time:
                      student_id: student.id, // the student,
                      subject, // the subject,
                      tutor_id: o.tutor_id, // the tutor,
                      weekday: o.weekday, // the weekday,
                      start_time: o.start_time, // the start time,
                      minutes, // the length,
                      delivery: o.delivery, // where,
                      library_id: o.library_id, // and the library.
                    }} // (end of the time)
                    defaultFirst={start} // the first date,
                    defaultLast={bookUntil ?? ""} // the last date (book until, if set),
                    terms={terms} // the term dates,
                    bookUntil={bookUntil} // how long to book,
                    isAdmin={isAdmin} // whether they're an admin,
                    startOpen={isAdmin && i === 0} // open to start for an admin's first time,
                    suggested={ // the suggested time:
                      isAdmin && options[0] // for admins:
                        ? { // the first time:
                            student_id: student.id, // the student,
                            subject, // the subject,
                            tutor_id: options[0].tutor_id, // the tutor,
                            weekday: options[0].weekday, // the weekday,
                            start_time: options[0].start_time, // the start time,
                            minutes, // the length,
                            delivery: options[0].delivery, // where,
                            library_id: options[0].library_id, // and the library.
                          } // (end of the suggestion)
                        : null // otherwise none.
                    } // (end of the suggested time)
                  />{/* End of the form. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of this part. */}
          {options.length > 40 && ( // If more than 40:
            <p className="mt-3 text-xs text-zinc-600">Showing the first 40. Narrow the days or times to see others.</p> // says only 40 are shown.
          )}{/* End of this part. */}
        </Card> // End of the card.
      )}{/* End of this part. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of BookSection.

// ---------------------------------------------------------------------------
// Tutors: online or in person, and which libraries
// ---------------------------------------------------------------------------
async function PlacesSection({ viewerId }: { viewerId: string }) { // The "where you teach" section for a tutor.
  const supabase = await createClient(); // Connects to the database.
  const [librariesRes, placesRes, settingsRes] = await Promise.all([ // Reads three things at once:
    supabase.from("libraries").select("id, name, suburb, confirmed_at").eq("active", true).order("name"), // libraries in use, by name,
    supabase.from("tutor_places").select("library_id").eq("tutor_id", viewerId), // the libraries the tutor chose,
    supabase.from("tutor_session_settings").select("online, in_person, learning_support").eq("tutor_id", viewerId).maybeSingle(), // and their online, in person and learning support settings.
  ]); // End of the reads.
  return ( // Shows:
    <Card // a card:
      title="Where you teach" // its title,
      description={ // its help text:
        <>{/* (a group) */}
          Families only see times inside your availability and weekly hours (set in your{" "}{/* the words, then a space, */}
          <TextLink href="/dashboard/tutor?section=hours">tutor dashboard</TextLink>).{/* a link to their dashboard. */}
        </> // End of the group.
      } // (end of the help text)
    >{/* (end of the card's settings) */}
      <PlacesForm // the places form:
        libraries={(librariesRes.data ?? []).map((l) => ({ // the libraries:
          id: l.id as string, // each id,
          name: l.confirmed_at ? (l.name as string) : `${l.name} (CLG is checking this library)`, // name (noting if CLG is still checking it),
          suburb: l.suburb as string | null, // and suburb.
        }))} // (end of the libraries)
        chosen={(placesRes.data ?? []).map((p) => p.library_id as string)} // the libraries they chose,
        settings={settingsRes.data ?? { online: true, in_person: true, learning_support: false }} // and their settings (or defaults).
      />{/* End of the form. */}
      <p className="mt-4 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">{/* an amber note: */}
        In-person sessions are only at public libraries CLG has confirmed, and only inside the library&apos;s opening
        hours. The easiest way to choose libraries is to set a travel distance on each time you add in your{" "}{/* (the words, then a space) */}
        <TextLink href="/dashboard/tutor?section=hours">tutor dashboard</TextLink>: libraries within that distance are
        offered automatically, and the boxes below are then not needed. Sessions at a student&apos;s home are arranged by
        CLG only.{/* (end of the text) */}
      </p>{/* End of the note. */}
      <SubHeading>Teach at a library that is not listed?</SubHeading>{/* a small heading, */}
      <p className="text-sm text-zinc-600">Add it here. CLG checks it and adds its opening hours before families can book it.</p>{/* what happens when they suggest one, */}
      <SuggestLibraryForm />{/* the suggest form. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of PlacesSection.

// ---------------------------------------------------------------------------
// Away dates: tutors for themselves, families for their children
// ---------------------------------------------------------------------------
// One booked session that falls on a tutor's away dates (admins only).
type TutorAwaySession = { // A session:
  session_id: string; // its id,
  starts_at: string; // when it starts,
  ends_at: string; // when it ends,
  student_name: string; // the student,
  tutor_name: string; // the tutor,
  subject: string; // the subject,
  away_from: string; // the first day away,
  away_to: string; // the last day away,
  reason: string | null; // the tutor's reason (if any),
  tutor_offer: string | null; // and what the tutor can offer instead (if anything).
}; // End of TutorAwaySession.

async function AwaySection({ // The away dates section, given:
  viewerId, // the signed-in person,
  isAdmin, // whether they're a full admin in the admin dashboard,
  isTutor, // whether this is the tutor dashboard,
  familyStudentIds, // and, in a family dashboard, their own children (and themselves).
}: { // The types of those:
  viewerId: string; // an id,
  isAdmin: boolean; // yes or no,
  isTutor: boolean; // yes or no,
  familyStudentIds: string[] | null; // student ids (none outside a family dashboard).
}) { // End of the types.
  const supabase = await createClient(); // Connects to the database.
  const [awayRes, studentsRes, linksRes, tutorsRes, teachesRes, tutorAwayRes] = await Promise.all([ // Reads six things at once:
    supabase // the away dates:
      .from("away_dates") // from away_dates,
      .select("id, tutor_id, student_id, from_date, to_date, reason") // these details,
      .gte("to_date", localToday()) // not yet over,
      .order("from_date"), // earliest first.
    supabase.from("students").select("id, full_name, account_id").order("full_name"), // the students, by name,
    supabase.from("parent_student_links").select("student_id").eq("parent_id", viewerId), // their own children,
    isAdmin ? supabase.from("accounts").select("id, full_name") : Promise.resolve({ data: [] as { id: string; full_name: string }[] }), // everyone's names (admins only),
    isTutor // and, in the tutor dashboard, the students they're matched with:
      ? supabase.from("tutor_assignments").select("student_id, starts_on, ends_on").eq("tutor_id", viewerId) // their matches,
      : Promise.resolve({ data: [] as { student_id: string; starts_on: string; ends_on: string | null }[] }), // (none otherwise),
    isAdmin ? supabase.rpc("tutor_away_sessions") : Promise.resolve({ data: [] }), // and, for admins, sessions on a tutor's away dates.
  ]); // End of the reads.
  const tutorAway = (tutorAwayRes.data ?? []) as TutorAwaySession[]; // The sessions on a tutor's away dates (admins only).
  const today = localToday(); // Today's date.
  const teaches = new Set( // The students this tutor teaches now:
    (teachesRes.data ?? []) // from their matches,
      .filter((t) => t.starts_on <= today && (!t.ends_on || t.ends_on >= today)) // the current ones,
      .map((t) => t.student_id as string), // by student.
  ); // End of the list.
  const students = studentsRes.data ?? []; // The students.
  const mine = new Set((linksRes.data ?? []).map((l) => l.student_id as string)); // Their own children.
  const myChildren = students.filter((s) => mine.has(s.id) || s.account_id === viewerId); // Their own children's details (and themselves as a student).
  const nameOf = new Map<string, string>([ // Each person's name, by id:
    ...students.map((s) => [s.id, s.full_name] as [string, string]), // the students,
    ...(tutorsRes.data ?? []).map((a) => [a.id, a.full_name] as [string, string]), // and everyone else (admins).
  ]); // End of nameOf.
  const choices = [ // Who they can add away dates for:
    ...(isTutor ? [{ value: "me", label: "Me (as a tutor)" }] : []), // themselves (tutors),
    ...myChildren.map((s) => ({ value: `student:${s.id}`, label: s.full_name })), // and their children.
  ]; // End of the choices.
  // Each dashboard shows only its own: the tutor's own dates and their
  // students' in the tutor dashboard, the family's in a family one, all of
  // them in the admin dashboard. (Someone who is also an admin is sent every
  // away date by the database, so this keeps admin work out of other tabs.)
  const away = (awayRes.data ?? []).filter((a) => // The away dates for this dashboard:
    isTutor // in the tutor dashboard,
      ? a.tutor_id === viewerId || (!!a.student_id && teaches.has(a.student_id)) // their own, or a student they teach;
      : familyStudentIds // in a family dashboard,
        ? !!a.student_id && familyStudentIds.includes(a.student_id) // their own children's;
        : true, // in the admin dashboard, all of them.
  ); // End of the away dates.

  return ( // Shows:
    <>{/* (a group) */}
      {isAdmin && ( // For owner and Operations admins:
        <Card // the tutor away sessions card (Carla, 22 Nov 2026):
          title="Sessions during tutor away dates" // its title,
          description="A tutor's away dates no longer cancel sessions on their own. Contact each family to offer another time or tutor. Changing the session to another time or tutor takes it off this list. If nothing suits, choose Cancel session: the family gets full credit and is told." // what to do.
        >{/* (end of the card's settings) */}
          {tutorAway.length === 0 ? ( // if none:
            <Empty>No booked sessions fall on a tutor&apos;s away dates.</Empty> // says so.
          ) : ( // otherwise:
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {tutorAway.map((t) => ( // for each session:
                <li key={t.session_id} className="flex flex-wrap items-center justify-between gap-2 py-2.5 first:pt-0">{/* a row: */}
                  <span className="space-y-0.5">{/* (a group) */}
                    <span className="block font-medium">{t.student_name} · {t.subject}</span>{/* the student and subject, */}
                    <span className="block text-zinc-600">{/* in grey: */}
                      {sessionWhen(t.starts_at)} with {t.tutor_name}, away {t.away_from === t.away_to ? shortDate(t.away_from) : `${shortDate(t.away_from)} to ${shortDate(t.away_to)}`}{t.reason ? ` (${t.reason})` : ""}{/* when, the tutor and their away dates, */}
                    </span>{/* End of the grey part. */}
                    {t.tutor_offer && <span className="block text-zinc-600">The tutor can offer instead: {t.tutor_offer}</span>}{/* and what the tutor offered (if anything). */}
                  </span>{/* End of the group. */}
                  <form action={cancelForTutorAway}>{/* the cancel form: */}
                    <input type="hidden" name="id" value={t.session_id} />{/* the session (hidden), */}
                    <BusyButton type="submit" className="text-xs text-red-700 underline">{/* the cancel button: */}
                      Cancel session{/* its words, */}
                    </BusyButton>{/* end of the button. */}
                  </form>{/* End of the form. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of this part. */}
        </Card> // End of the card.
      )}{/* End of the admin part. */}
      <Card // the away dates card:
        title="Away dates" // its title,
        description={ // its help text:
          isTutor // for tutors,
            ? "Holidays, camps or exams. New bookings skip these dates. For booked sessions on your own away dates, CLG offers each family another time or tutor, or cancels." // what happens to their sessions (Carla, 22 Nov 2026),
            : "Holidays, camps or exams. A student's booked sessions on these dates are cancelled, and new bookings skip them. For a tutor's away dates, CLG offers each family another time or tutor, or cancels." // otherwise the general wording.
        } // (end of the help text)
      >{/* (end of the card's settings) */}
        {away.length === 0 ? ( // if none:
          <Empty>No away dates coming up.</Empty> // says so.
        ) : ( // otherwise:
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {away.map((a) => { // for each away date:
              const who = a.tutor_id === viewerId ? "You" : (nameOf.get((a.tutor_id ?? a.student_id) as string) ?? "Tutor"); // who (You, the person's name, or "Tutor"),
              const canRemove = isAdmin || a.tutor_id === viewerId || (a.student_id && myChildren.some((c) => c.id === a.student_id)); // whether this person can remove it,
              return ( // shows:
                <li key={a.id} className="flex flex-wrap items-center justify-between gap-2 py-2.5 first:pt-0">{/* a row: */}
                  <span>{/* (a group) */}
                    <span className="font-medium">{who}</span>{/* who, */}
                    <span className="text-zinc-600">{/* in grey: */}
                      {" "}{/* a space, */}
                      · {a.from_date === a.to_date ? shortDate(a.from_date) : `${shortDate(a.from_date)} to ${shortDate(a.to_date)}`}{/* the date or dates, */}
                      {a.reason && ` · ${a.reason}`}{/* and the reason (if any). */}
                    </span>{/* End of the grey part. */}
                  </span>{/* End of the group. */}
                  {canRemove && ( // If they can remove it:
                    <form action={removeAwayDates}>{/* the remove form: */}
                      <input type="hidden" name="id" value={a.id} />{/* the away date (hidden), */}
                      <BusyButton type="submit" className="text-xs text-red-700 underline">{/* the remove button: */}
                        Remove{/* its words, */}
                      </BusyButton>{/* end of the button. */}
                    </form> // End of the form.
                  )}{/* End of this part. */}
                </li> // End of the row.
              ); // End of what's shown for this one.
            })}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of this part. */}
        {choices.length > 0 && ( // If they can add any:
          <>{/* (a group) */}
            <SubHeading>Add away dates</SubHeading>{/* a small heading, */}
            <AwayForm choices={choices} today={localToday()} isTutor={isTutor} />{/* the add form. */}
          </> // End of the group.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of AwaySection.

// ---------------------------------------------------------------------------
// Waitlist: families see their places; admins see everyone waiting
// ---------------------------------------------------------------------------
type WaitPlace = { // A waitlist place as listed:
  id: string; // its id,
  student_name: string; // the student's name,
  year_level: string | null; // their year level (if known),
  subject: string; // the subject,
  minutes: number; // the length in minutes,
  online: boolean; // online or not,
  library_names: string[]; // the libraries' names,
  weekdays: number[] | null; // the days (if chosen),
  earliest: string | null; // no earlier than (if set),
  latest: string | null; // finished by (if set),
  tutor_name: string | null; // a tutor they're waiting for (if any),
  note: string | null; // a note (if any),
  created_at: string; // when they joined,
  checked_in_at: string | null; // when CLG last checked in with the family (if ever),
  check_in_due: boolean; // whether a weekly check-in is due (Carla, 22 Nov 2026),
  times_now_free: number; // and how many times are free now.
}; // End of WaitPlace.

async function WaitlistSection({ isAdmin }: { isAdmin: boolean }) { // The waitlist section.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("list_waitlist"); // Reads the waitlist they can see.
  const places = (data ?? []) as WaitPlace[]; // The places.
  return ( // Shows:
    <Card // a card:
      title="Waitlist" // its title,
      description={ // its help text:
        isAdmin // for admins,
          ? "Everyone waiting for a tutor, oldest first. Check in with each family every week: \"Check in due\" shows when 7 days have passed since the last check-in. Press \"Checked in\" after you contact them." // their wording (weekly check-ins, Carla 22 Nov 2026),
          : "Your children waiting for a suitable tutor. CLG will be in touch when one is available." // otherwise the family's.
      } // (end of the help text)
    >{/* (end of the card's settings) */}
      {places.length === 0 ? ( // if empty:
        <Empty>Nobody is on the waitlist.</Empty> // says so.
      ) : ( // otherwise:
        <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
          {places.map((w) => ( // for each place:
            <li key={w.id} className="space-y-1 py-3 first:pt-0">{/* a row: */}
              <div className="flex flex-wrap items-baseline justify-between gap-2">{/* the top line: */}
                <span>{/* (a group) */}
                  <span className="font-medium">{w.student_name}</span>{/* the student's name, */}
                  <span className="text-zinc-600">{/* in grey: */}
                    {w.year_level && ` (${w.year_level})`} · {w.subject} · {lengthLabel(w.minutes)}{/* their year level, subject and length. */}
                  </span>{/* End of the grey part. */}
                </span>{/* End of the group. */}
                <span className="flex items-center gap-2">{/* the tags: */}
                  {isAdmin && w.check_in_due && ( // if a weekly check-in is due (admins only):
                    <span className="rounded-full bg-amber-50 px-2 text-xs text-amber-900">Check in due</span> // a tag.
                  )}{/* End of this part. */}
                  {w.times_now_free > 0 && ( // if times are free now:
                    <span className="rounded-full bg-teal-50 px-2 text-xs text-teal-900">{/* a tag: */}
                      {w.times_now_free} time{w.times_now_free === 1 ? "" : "s"} available now{/* how many. */}
                    </span> // End of the tag.
                  )}{/* End of this part. */}
                </span>{/* End of the tags. */}
              </div>{/* End of the top line. */}
              <p className="text-zinc-600">{/* a grey line: */}
                {[w.online ? "Online" : null, ...w.library_names].filter(Boolean).join(", ")}{/* the places, */}
                {w.weekdays?.length ? ` · ${w.weekdays.map((d) => WEEKDAY_NAMES[d - 1].slice(0, 3)).join(", ")}` : ""}{/* the days (if any), */}
                {w.earliest && ` · from ${clockTime(w.earliest)}`}{/* no earlier than (if set), */}
                {w.latest && ` · finished by ${clockTime(w.latest)}`}{/* finished by (if set), */}
                {w.tutor_name && ` · waiting for ${w.tutor_name}`}{/* the tutor they're waiting for (if any), */}
                {` · since ${shortDate(w.created_at)}`}{/* since when, */}
                {isAdmin && ` · last check-in ${w.checked_in_at ? shortDate(w.checked_in_at) : "not yet"}`}{/* and, for admins, the last check-in. */}
              </p>{/* End of the line. */}
              {w.note && <p className="text-zinc-600">Note: {w.note}</p>}{/* the note (if any). */}
              <div className="flex flex-wrap items-center gap-4">{/* the row's buttons, side by side: */}
                {isAdmin && ( // admins record check-ins:
                  <form action={waitlistCheckedIn}>{/* the check-in form: */}
                    <input type="hidden" name="id" value={w.id} />{/* the place (hidden), */}
                    <BusyButton type="submit" className="text-xs text-brand underline">{/* the button: */}
                      Checked in{/* its words, */}
                    </BusyButton>{/* end of the button. */}
                  </form> // End of the form.
                )}{/* End of the check-in. */}
                <form action={leaveWaitlist}>{/* the remove form: */}
                  <input type="hidden" name="id" value={w.id} />{/* the place (hidden), */}
                  <BusyButton type="submit" className="text-xs text-red-700 underline">{/* the button: */}
                    Take off the waitlist{/* its words, */}
                  </BusyButton>{/* end of the button. */}
                </form>{/* End of the form. */}
              </div>{/* End of the buttons. */}
            </li> // End of the row.
          ))}{/* End of the loop. */}
        </ul> // End of the list.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of WaitlistSection.

// ---------------------------------------------------------------------------
// How long each family wants to book for: the last date, and whether
// sessions go ahead in school holidays and on public holidays. Families must
// fill it in; CLG admins can change it (one student at a time, from Matching).
// ---------------------------------------------------------------------------
async function BookingLengthSection({ // Takes:
  viewerId, // the signed-in person,
  isAdmin, // whether they're an admin,
  params, // and the address's settings.
}: { // The types of those:
  viewerId: string; // an id,
  isAdmin: boolean; // yes or no,
  params: Record<string, string | string[] | undefined>; // the settings.
}) { // End of the types.
  const supabase = await createClient(); // Connects to the database.
  const [studentsRes, linksRes, placesRes] = await Promise.all([ // Reads three things at once:
    supabase.from("students").select("id, full_name, account_id").order("full_name"), // the students, by name,
    supabase.from("parent_student_links").select("student_id").eq("parent_id", viewerId), // their own children,
    supabase.from("student_places").select("student_id, book_until, include_school_holidays, include_public_holidays"), // and each student's booking length answers.
  ]); // End of the reads.
  const mine = new Set((linksRes.data ?? []).map((l) => l.student_id as string)); // Their own children.
  const wanted = one(params.student); // The student asked for in the address (if any).
  const all = studentsRes.data ?? []; // All the students.
  const students = // The students to show:
    isAdmin && wanted ? all.filter((s) => s.id === wanted) : all.filter((s) => mine.has(s.id) || s.account_id === viewerId); // for admins, the one asked for; otherwise their own children (and themselves).
  const places = new Map( // Each student's answers, by student:
    ( // (the rows)
      (placesRes.data ?? []) as { // from the rows:
        student_id: string; // the student,
        book_until: string | null; // book until (if set),
        include_school_holidays: boolean | null; // school holidays (if said),
        include_public_holidays: boolean | null; // public holidays (if said).
      }[] // (end of the type)
    ).map((p) => [p.student_id, p]), // each by student.
  ); // End of places.
  const termsFor = new Map<string, StudentTerm[]>( // Each student's term dates, by student:
    await Promise.all( // reads them all at once:
      students.map(async (s) => { // for each student:
        const { data } = await supabase.rpc("student_term_dates", { p_student: s.id }); // reads their term dates,
        return [s.id as string, (data ?? []) as StudentTerm[]] as const; // and pairs them with the student.
      }), // End of each.
    ), // End of the reads.
  ); // End of termsFor.
  return ( // Shows:
    <Card // a card:
      title="How long to book" // its title,
      description="The last date for sessions, and whether they go ahead in school holidays and on public holidays. CLG needs this before offering times. It can be changed later." // its help text.
    >{/* (end of the card's settings) */}
      {students.length === 0 ? ( // if no students:
        isAdmin ? ( // for admins:
          <Empty>{/* a line: */}
            Choose a student from the <TextLink href="/matching">Matching</TextLink> tab to see this.{/* says to choose one from Matching. */}
          </Empty> // End of the line.
        ) : ( // otherwise:
          <Empty>No children yet.</Empty> // says no children yet.
        ) // (end of this part)
      ) : ( // otherwise:
        <div className="space-y-6">{/* a list: */}
          {students.map((s) => { // for each student:
            const p = places.get(s.id); // their answers,
            return ( // shows:
              <div key={s.id} className="space-y-2">{/* a block: */}
                <SubHeading>{s.full_name}</SubHeading>{/* their name, */}
                <BookingLengthForm // the form:
                  studentId={s.id} // the student,
                  today={localToday()} // today's date,
                  terms={termsFor.get(s.id) ?? []} // their term dates,
                  until={p?.book_until ?? ""} // book until,
                  schoolHolidays={p?.include_school_holidays ?? null} // school holidays,
                  publicHolidays={p?.include_public_holidays ?? null} // public holidays.
                />{/* End of the form. */}
              </div> // End of the block.
            ); // End of what's shown for this student.
          })}{/* End of the loop. */}
        </div> // End of the list.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of BookingLengthSection.

// ---------------------------------------------------------------------------
// Where and when each student can have sessions. Admins set the places
// (online and libraries); families give preferred times and study dates.
// ---------------------------------------------------------------------------
async function ChildPlacesSection({ // Takes:
  viewerId, // the signed-in person,
  isAdmin, // whether they're an admin,
  params, // and the address's settings.
}: { // The types of those:
  viewerId: string; // an id,
  isAdmin: boolean; // yes or no,
  params: Record<string, string | string[] | undefined>; // the settings.
}) { // End of the types.
  const supabase = await createClient(); // Connects to the database.
  const [studentsRes, linksRes, librariesRes, placesRes] = await Promise.all([ // Reads four things at once:
    supabase.from("students").select("id, full_name, account_id, year_level").order("full_name"), // the students, by name,
    supabase.from("parent_student_links").select("student_id").eq("parent_id", viewerId), // their own children,
    supabase.from("libraries").select("id, name, suburb").eq("active", true).not("confirmed_at", "is", null).order("name"), // confirmed libraries in use, by name,
    supabase.from("student_places").select("student_id, online, library_ids, preferred_days, preferred_parts, preferred_school_hours, tutor_preferences, travel_address, travel_km"), // and each student's places, preferred times and travel distance.
  ]); // End of the reads.
  const mine = new Set((linksRes.data ?? []).map((l) => l.student_id as string)); // Their own children.
  const wanted = one(params.student); // The student asked for in the address (if any).
  // Admins see one student at a time (from the matching list); families see their children.
  const all = studentsRes.data ?? []; // All the students.
  const students = // The students to show:
    isAdmin && wanted // for admins with one asked for,
      ? all.filter((s) => s.id === wanted) // just that one,
      : all.filter((s) => mine.has(s.id) || s.account_id === viewerId); // otherwise their own children (and themselves).
  const places = new Map( // Each student's places, by student:
    ( // (the rows)
      (placesRes.data ?? []) as { // from the rows:
        student_id: string; // the student,
        online: boolean; // online or not,
        library_ids: string[]; // libraries,
        preferred_days: number[] | null; // preferred days (if any),
        preferred_parts: string[] | null; // preferred parts of the day (if any),
        preferred_school_hours: boolean; // school hours or not,
        tutor_preferences: string | null; // tutor preferences (if any),
        travel_address: string | null; // the address they travel from (if any),
        travel_km: number | null; // and how far they will travel (if set).
      }[] // (end of the type)
    ).map((p) => [p.student_id, p]), // each by student.
  ); // End of places.
  return ( // Shows:
    <Card // a card:
      title={isAdmin ? "Session places" : "Preferred times"} // its title (session places for admins, preferred times for families),
      description={ // its help text:
        isAdmin // for admins,
          ? "Where and when this student can have sessions, how far the family will travel, and the study dates that sessions follow. Tutors are matched only where both can go. Preferred times are a preference, not a guarantee." // their wording,
          : "Days and times that suit each child, how far you will travel to a library, and the study dates sessions follow." // otherwise the family's.
      } // (end of the help text)
    >{/* (end of the card's settings) */}
      {students.length === 0 ? ( // if no students:
        isAdmin ? ( // for admins:
          <Empty>{/* a line: */}
            Choose a student from the <TextLink href="/matching">Matching</TextLink> tab to see their
            places.{/* (end of the text) */}
          </Empty> // End of the line.
        ) : ( // otherwise:
          <Empty>No children yet.</Empty> // says no children yet.
        ) // (end of this part)
      ) : ( // otherwise:
        <div className="space-y-6">{/* a list: */}
          {students.map((s) => ( // for each student:
            <div key={s.id} className="space-y-2">{/* a block: */}
              <SubHeading>{s.full_name}</SubHeading>{/* their name, */}
              <StudentPlacesForm // the places form:
                studentId={s.id} // the student,
                libraries={librariesRes.data ?? []} // the libraries,
                online={places.get(s.id)?.online ?? true} // online (yes if not set),
                chosen={places.get(s.id)?.library_ids ?? []} // the libraries chosen,
                preferredDays={places.get(s.id)?.preferred_days ?? []} // preferred days,
                preferredParts={places.get(s.id)?.preferred_parts ?? []} // preferred parts of the day,
                schoolHours={places.get(s.id)?.preferred_school_hours ?? false} // school hours,
                showPlaces={isAdmin} // showing places only to admins,
                tutorPreferences={places.get(s.id)?.tutor_preferences ?? ""} // tutor preferences.
              />{/* End of the form. */}
              <StudentTravelForm // the travel distance form:
                studentId={s.id} // the student,
                address={places.get(s.id)?.travel_address ?? ""} // the saved address (if any),
                km={places.get(s.id)?.travel_km ?? null} // and distance (if any).
              />{/* End of the form. */}
              <StudyPeriodBlock studentId={s.id} yearLevel={(s.year_level as string | null) ?? null} />{/* their study period box. */}
            </div> // End of the block.
          ))}{/* End of the loop. */}
        </div> // End of the list.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of ChildPlacesSection.

// ---------------------------------------------------------------------------
// Book again: the question for each booking nearing the student's book-till
// date (asked 3 weeks before), and school term dates (admins)
// ---------------------------------------------------------------------------
type Renewal = { // A "book again?" question as listed:
  id: string; // its id,
  booking_id: string; // the booking,
  student_id: string; // the student's id,
  student_name: string; // the student's name,
  subject: string; // the subject,
  tutor_name: string | null; // the tutor's name (if any),
  weekday: number; // the weekday,
  start_time: string; // the start time,
  minutes: number; // the length in minutes,
  last_date: string; // the last session date,
  term_label: string | null; // the term's name (older questions only),
  term_ends_on: string | null; // the term's last day (older questions only),
  book_until: string | null; // the date the sessions stop (the book-till date, or the last date if earlier),
  new_book_until: string | null; // the new book-till date chosen (if answered),
  asked_at: string; // when asked,
  answered_at: string | null; // when answered (if yet),
  same_again: boolean | null; // same again (if answered),
  holidays: boolean | null; // sessions in the school holidays (if answered),
  public_holidays: boolean | null; // sessions on public holidays (if answered),
  change_what: string | null; // what to change (if anything),
  change_reason: string | null; // why (if given),
  feedback: string | null; // feedback (if any),
  testimonial_ok: boolean; // whether the feedback can be shared,
  next_status: string | null; // and what happens next (if decided).
}; // End of Renewal.

const CHANGE_NAMES: Record<string, string> = { time: "day and time", tutor: "tutor", both: "day, time and tutor" }; // The words for what to change.

async function NextTermSection({ isAdmin }: { isAdmin: boolean }) { // The book again section.
  const supabase = await createClient(); // Connects to the database.
  const [renewalsRes, termsRes] = await Promise.all([ // Reads two things at once:
    supabase.rpc("list_renewals"), // the "book again?" questions they can see,
    isAdmin // for admins:
      ? supabase // school terms:
          .from("school_terms") // from school_terms,
          .select("id, state, calendar, year, term, starts_on, ends_on") // these details,
          .gte("ends_on", addDays(localToday(), -120)) // ending no more than 120 days ago,
          .order("state") // by state,
          .order("starts_on") // then start date.
      : Promise.resolve({ data: [] }), // otherwise none.
  ]); // End of the reads.
  const renewals = (renewalsRes.data ?? []) as Renewal[]; // The questions.
  const open = renewals.filter((r) => !r.answered_at); // Not yet answered.
  const answered = renewals.filter((r) => r.answered_at); // Answered.
  const openStudents = [...new Set(open.map((r) => r.student_id))]; // The students with questions to answer (each once).
  const [placesRes, ...termLists] = await Promise.all([ // Reads, all at once:
    openStudents.length // if there are any,
      ? supabase // their current "How long to book" answers:
          .from("student_places") // from student_places,
          .select("student_id, include_school_holidays, include_public_holidays") // the two holiday answers,
          .in("student_id", openStudents) // for those students,
      : Promise.resolve({ data: [] }), // (otherwise none)
    ...openStudents.map((id) => supabase.rpc("student_term_dates", { p_student: id })), // and each student's term dates.
  ]); // End of the reads.
  const holidaysFor = new Map( // Each student's holiday answers, by student:
    ((placesRes.data ?? []) as { student_id: string; include_school_holidays: boolean | null; include_public_holidays: boolean | null }[]).map( // (the rows)
      (p) => [p.student_id, p] as const, // each by student.
    ), // (end of the map)
  ); // End of holidaysFor.
  const termsFor = new Map(openStudents.map((id, i) => [id, (termLists[i]?.data ?? []) as StudentTerm[]] as const)); // Each student's term dates, by student.
  const tomorrow = addDays(localToday(), 1); // Tomorrow.
  const terms = (termsRes.data ?? []) as { // The school terms:
    id: string; // each has an id,
    state: string; // a state,
    calendar: string; // government or private,
    year: number; // a year,
    term: number; // a term number,
    starts_on: string; // a first day,
    ends_on: string; // and a last day.
  }[]; // (end of the type)

  const bookingLine = (r: Renewal) => // One line describing a booking:
    `${r.student_name} · ${r.subject}${r.tutor_name ? ` with ${r.tutor_name}` : ""} · ${WEEKDAY_NAMES[r.weekday - 1]}s at ${clockTime(r.start_time)} · ${lengthLabel(r.minutes)}`; // student, subject, tutor, weekday, time and length.

  return ( // Shows:
    <>{/* (a group) */}
      <Card // the book again card:
        title="Book again" // its title,
        description={ // its help text:
          isAdmin // for admins,
            ? "Families are asked 3 weeks before each student's book-till date (or the booking's last date, if that comes first). They choose a new book-till date and answer the holiday questions again. Unanswered questions are listed first." // their wording,
            : "Before your book-till date, tell us whether you would like the same again, choose a new book-till date, and say whether you would like sessions in the school holidays and on public holidays." // otherwise the family's.
        } // (end of the help text)
      >{/* (end of the card's settings) */}
        {open.length === 0 ? ( // if nothing to answer:
          <Empty>Nothing to answer right now.</Empty> // says so.
        ) : ( // otherwise:
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {open.map((r) => ( // for each question:
              <li key={r.id} className="space-y-3 py-4 first:pt-0">{/* a row: */}
                <p>{/* a line: */}
                  <span className="font-medium">{bookingLine(r)}</span>{/* the booking, */}
                  <span className="block text-zinc-600">{/* in grey: */}
                    Last session {shortDate(r.last_date)}{r.book_until ? ` · Booked until ${shortDate(r.book_until)}` : ""}{/* the last session and the date the sessions stop (if known). */}
                  </span>{/* End of the grey part. */}
                </p>{/* End of the line. */}
                <RenewalForm // the answer form:
                  id={r.id} // for this question,
                  min={r.last_date >= localToday() ? addDays(r.last_date, 1) : tomorrow} // new date after the last session (and not in the past),
                  terms={termsFor.get(r.student_id) ?? []} // the student's term dates,
                  schoolHolidays={holidaysFor.get(r.student_id)?.include_school_holidays ?? null} // their school holidays answer so far,
                  publicHolidays={holidaysFor.get(r.student_id)?.include_public_holidays ?? null} // and their public holidays answer so far.
                />{/* (end of the form) */}
              </li> // End of the row.
            ))}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}

      {answered.length > 0 && ( // If there are answers:
        <Card collapsible defaultOpen={isAdmin} title="Answers">{/* a fold-up card (open for admins): */}
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {answered.map((r) => ( // for each answer:
              <li key={r.id} className="space-y-1 py-3 first:pt-0">{/* a row: */}
                <p className="font-medium">{bookingLine(r)}</p>{/* the booking, */}
                <p className="text-zinc-700">{/* a line: */}
                  {r.same_again // if same again,
                    ? `Same again${r.next_status ? ` (${(BOOKING_STATUS_NAMES[r.next_status] ?? r.next_status).toLowerCase()})` : ""}` // says so (and what has happened since),
                    : `Wants a different ${CHANGE_NAMES[r.change_what ?? ""] ?? "arrangement"}`}{/* otherwise what they'd like changed, */}
                  {r.new_book_until ? ` · until ${shortDate(r.new_book_until)}` : ""}{/* the new book-till date (if given), */}
                  {r.holidays ? " · with school holiday sessions" : " · no school holiday sessions"}{/* whether they want school holiday sessions, */}
                  {r.public_holidays === null ? "" : r.public_holidays ? " · with public holiday sessions" : " · no public holiday sessions"}{/* and public holiday sessions (if asked). */}
                </p>{/* End of the line. */}
                {r.change_reason && <p className="text-zinc-600">Why: {r.change_reason}</p>}{/* why (if given). */}
                {r.feedback && ( // If they gave feedback:
                  <p className="text-zinc-600">{/* a line: */}
                    Feedback: {r.feedback}{/* the feedback, */}
                    {isAdmin && (r.testimonial_ok ? " (may be used as a testimonial)" : " (not for sharing)")}{/* and whether it can be shared (admins). */}
                  </p> // End of the line.
                )}{/* End of this part. */}
              </li> // End of the row.
            ))}{/* End of the loop. */}
          </ul>{/* End of the list. */}
        </Card> // End of the card.
      )}{/* End of this part. */}

      {isAdmin && ( // For admins:
        <>{/* (a group) */}
          <StudyDatesToCheck />{/* study dates still to check, */}
          <Card // the school terms card:
            title="School terms" // its title,
            description="Used for renewal questions and for skipping the holidays. SA private schools have the same dates as government schools, except Term 2 ends a week earlier. Each student's last day of Term 4 is confirmed separately." // its help text.
          >{/* (end of the card's settings) */}
            {terms.length === 0 ? ( // if none:
              <Empty>No terms yet.</Empty> // says so.
            ) : ( // otherwise:
              <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                {terms.map((t) => ( // for each term:
                  <li key={t.id} className="py-2">{/* a row: */}
                    <span>{/* (a group) */}
                      <span className="font-medium">{/* in bold: */}
                        {t.state} {t.calendar === "private" ? "private schools " : ""}Term {t.term} {t.year}{/* the state, kind, term and year. */}
                      </span>{/* End of the bold part. */}
                      <span className="text-zinc-600">{/* in grey: */}
                        {" "}{/* a space, */}
                        · {shortDate(t.starts_on)} to {shortDate(t.ends_on)}{/* the first and last days. */}
                      </span>{/* End of the grey part. */}
                    </span>{/* End of the group. */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul> // End of the list.
            )}{/* End of this part. */}
          </Card>{/* End of the card. */}
          <Card collapsible defaultOpen={false} title="Add or correct a term">{/* a fold-up card: */}
            <TermForm />{/* the term form. */}
          </Card>{/* End of the card. */}
        </> // End of the group.
      )}{/* End of this part. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of NextTermSection.

// ---------------------------------------------------------------------------
// Admins: has each tutor checked their availability for next term?
// ---------------------------------------------------------------------------
type AvailabilityCheck = { // A tutor's availability check as listed:
  id: string; // its id,
  tutor_id: string; // the tutor,
  tutor_name: string; // their name,
  term_label: string; // the term's name,
  term_ends_on: string; // the term's last day,
  asked_at: string; // when asked,
  confirmed_at: string | null; // when confirmed (if yet),
  changed: boolean | null; // whether they changed anything (if answered),
  removed_slots: string[]; // times they removed,
  bookings_outside: number; // and how many bookings now fall outside their availability.
}; // End of AvailabilityCheck.

async function TutorAvailabilitySection() { // The tutor availability section (admins).
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("list_availability_checks"); // Reads the checks.
  const rows = (data ?? []) as AvailabilityCheck[]; // The checks.
  const weekAgo = currentTime() - 7 * 24 * 3600 * 1000; // A week ago.
  return ( // Shows:
    <Card // a card:
      title="Tutor availability" // its title,
      description="Each tutor is asked 4 weeks before term ends to check their availability for next term. Tutors who have not answered are listed first; they can still be booked." // its help text.
    >{/* (end of the card's settings) */}
      {rows.length === 0 ? ( // if none:
        <Empty>No tutors have been asked yet.</Empty> // says so.
      ) : ( // otherwise:
        <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
          {rows.map((r) => ( // for each check:
            <li key={r.id} className="space-y-1 py-3 first:pt-0">{/* a row: */}
              <p className="flex flex-wrap items-baseline justify-between gap-2">{/* the top line: */}
                <span>{/* (a group) */}
                  <span className="font-medium">{r.tutor_name}</span>{/* the tutor's name, */}
                  <span className="text-zinc-600"> · before {r.term_label} ends</span>{/* and which term. */}
                </span>{/* End of the group. */}
                {r.confirmed_at ? ( // if answered:
                  <span className="rounded-full bg-teal-50 px-2 text-xs text-teal-900">{/* a teal tag: */}
                    {r.changed ? "Updated" : "No changes"} · {shortDate(r.confirmed_at)}{/* updated or no changes, and when. */}
                  </span> // End of the tag.
                ) : ( // otherwise:
                  <span // a tag:
                    className={`rounded-full px-2 text-xs ${new Date(r.asked_at).getTime() < weekAgo ? "bg-amber-50 text-amber-900" : "bg-zinc-100 text-zinc-700"}`} // amber if asked over a week ago, grey otherwise.
                  >{/* (end of the tag's settings) */}
                    Not answered · asked {shortDate(r.asked_at)}{/* not answered, and when asked. */}
                  </span> // End of the tag.
                )}{/* End of this part. */}
              </p>{/* End of the top line. */}
              {r.removed_slots.length > 0 && ( // If they removed times:
                <p className="text-amber-900">Removed since last term: {r.removed_slots.join(", ")}</p> // which times.
              )}{/* End of this part. */}
              {r.bookings_outside > 0 && ( // If bookings fall outside:
                <p className="text-red-700">{/* a red line: */}
                  {r.bookings_outside} booking{r.bookings_outside === 1 ? " is" : "s are"} now outside their availability.
                  Please talk it through with them.{/* (end of the text) */}
                </p> // End of the line.
              )}{/* End of this part. */}
            </li> // End of the row.
          ))}{/* End of the loop. */}
        </ul> // End of the list.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of TutorAvailabilitySection.

// ---------------------------------------------------------------------------
// Admins: session times that need a look before pay
// ---------------------------------------------------------------------------
type TimeCheck = { // A session time to check:
  id: string; // its id,
  starts_at: string; // when it starts,
  ends_at: string; // when it ends,
  student_name: string; // the student's name,
  tutor_name: string; // the tutor's name,
  subject: string; // the subject,
  delivery: string; // where,
  library_name: string | null; // the library's name (if any),
  status: string; // its status,
  signed_on_at: string | null; // when the tutor signed on (if they did),
  tutor_end_at: string | null; // the end time the tutor gave (if any),
  tutor_time_note: string | null; // the tutor's note (if any),
  reason: string; // and why it needs a look.
}; // End of TimeCheck.

async function TimesSection() { // The times to check section (admins).
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("list_times_to_check"); // Reads the times to check.
  const rows = (data ?? []) as TimeCheck[]; // The rows.
  return ( // Shows:
    <Card // a card:
      title="Times to check" // its title,
      description="Sessions whose times need a look before pay: a different end time, no sign-on, or a location check that did not pass." // its help text.
    >{/* (end of the card's settings) */}
      {rows.length === 0 ? ( // if none:
        <Empty>Nothing to check.</Empty> // says so.
      ) : ( // otherwise:
        <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
          {rows.map((r) => ( // for each session:
            <li key={r.id} className="space-y-2 py-4 first:pt-0">{/* a row: */}
              <p>{/* a line: */}
                <span className="font-medium">{sessionWhen(r.starts_at)}</span>{/* when, */}
                <span className="text-zinc-600">{/* in grey: */}
                  {" "}{/* a space, */}
                  · {r.tutor_name} with {r.student_name} · {r.subject} · {placeLabel(r.delivery, r.library_name)}{/* the tutor, student, subject and place. */}
                </span>{/* End of the grey part. */}
              </p>{/* End of the line. */}
              <p className="text-amber-900">{TIME_CHECK_REASONS[r.reason] ?? r.reason}</p>{/* why it needs a look. */}
              <p className="text-zinc-600">{/* a grey line: */}
                Booked {clockTime(localClock(r.starts_at))} to {clockTime(localClock(r.ends_at))}{/* the booked times, */}
                {r.signed_on_at && ` · signed on ${clockTime(localClock(r.signed_on_at))}`}{/* when they signed on (if they did), */}
                {r.tutor_end_at && ` · tutor says finished ${clockTime(localClock(r.tutor_end_at))}`}{/* and the end time they gave (if any). */}
              </p>{/* End of the line. */}
              {r.tutor_time_note && <p className="text-zinc-600">Tutor&apos;s note: {r.tutor_time_note}</p>}{/* the tutor's note (if any). */}
              <ConfirmTimesForm // the confirm form:
                id={r.id} // the session,
                date={localDate(r.starts_at)} // the date,
                from={localClock( // the start: the sign-on time if later than booked,
                  r.signed_on_at && new Date(r.signed_on_at) > new Date(r.starts_at) ? r.signed_on_at : r.starts_at, // otherwise the booked start,
                )} // (end of the start)
                to={localClock(r.tutor_end_at ?? r.ends_at)} // the end: the tutor's end time, or the booked end.
              />{/* End of the form. */}
            </li> // End of the row.
          ))}{/* End of the loop. */}
        </ul> // End of the list.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of TimesSection.

// ---------------------------------------------------------------------------
// Notices: reminders and booking news, and how each person wants them
// ---------------------------------------------------------------------------
async function NoticesSection({ viewerId, unread, isAdmin }: { viewerId: string; unread: number; isAdmin: boolean }) { // The notices section (with the unread count, and whether they can change quiet hours).
  const supabase = await createClient(); // Connects to the database.
  const [noticesRes, doneRes, quietRes, devicesRes] = await Promise.all([ // Reads four things at once:
    supabase // their notices not yet ticked off as done:
      .from("session_notices") // from session_notices,
      .select("id, title, body, deliver_at, read_at") // these details,
      .is("done_at", null) // not done yet,
      .order("deliver_at", { ascending: false }) // newest first,
      .limit(50), // up to 50.
    supabase // their notices ticked off as done (Carla, 20 Nov 2026):
      .from("session_notices") // from session_notices,
      .select("id, title, body, deliver_at, done_at") // these details,
      .not("done_at", "is", null) // done,
      .order("done_at", { ascending: false }) // most recently done first,
      .limit(20), // up to 20.
    supabase // CLG's quiet hours:
      .from("quiet_hours_settings") // from the one shared setting,
      .select("starts_at, ends_at") // when they start and end,
      .maybeSingle(), // (one row).
    supabase // their devices with pop-ups turned on (Carla, 18 Nov 2026):
      .from("push_subscriptions") // from the devices table (they only ever see their own),
      .select("id, device_label, endpoint, last_seen_at, created_at") // these details,
      .eq("account_id", viewerId) // for this person,
      .order("last_seen_at", { ascending: false }), // most recently used first.
  ]); // End of the reads.
  const notices = noticesRes.data ?? []; // The notices still in the list.
  const doneNotices = doneRes.data ?? []; // The notices ticked off as done.
  const quietStarts = ((quietRes.data?.starts_at as string | undefined) ?? "21:00:00").slice(0, 5); // When quiet hours start, e.g. "21:00" (9pm if not found).
  const quietEnds = ((quietRes.data?.ends_at as string | undefined) ?? "05:00:00").slice(0, 5); // When they end, e.g. "05:00" (5am if not found).
  const quietWords = `${shortClock(quietStarts)} and ${shortClock(quietEnds)}`; // In words, e.g. "9pm and 5am".
  return ( // Shows:
    <>{/* (a group) */}
      <Card title="Notices" description="Reminders before each session, and news about your bookings. Tick off each one as seen, or as done once you have dealt with it.">{/* the notices card: */}
        {notices.length === 0 ? ( // if none:
          <Empty>{doneNotices.length > 0 ? "Nothing left to look at. Well done." : "No notices yet."}</Empty> // says so (and says well done if they ticked them all off).
        ) : ( // otherwise:
          <>{/* (a group) */}
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {notices.map((n) => ( // for each notice:
                <li key={n.id} className="py-3 first:pt-0">{/* a row: */}
                  <p className="flex flex-wrap items-baseline justify-between gap-2">{/* the top line: */}
                    <span className={n.read_at ? "font-medium text-zinc-700" : "font-semibold"}>{/* the title (bold if unread): */}
                      {!n.read_at && <span className="mr-2 inline-block h-2 w-2 rounded-full bg-teal-600" aria-label="New" />}{/* a dot if new, */}
                      {n.title}{/* the title. */}
                    </span>{/* End of the title. */}
                    <span className="text-xs text-zinc-500">{sessionWhen(n.deliver_at)}</span>{/* when it was sent. */}
                  </p>{/* End of the top line. */}
                  <p className="mt-1 text-zinc-600">{n.body}</p>{/* the message, */}
                  <div className="mt-2 flex flex-wrap gap-4">{/* the tick-off buttons (Carla, 20 Nov 2026): */}
                    {!n.read_at && <NoticeTickButton id={n.id} action="seen" label="Mark as seen" />}{/* "Mark as seen" (only if not yet seen), */}
                    <NoticeTickButton id={n.id} action="done" label="Mark as done" />{/* and "Mark as done" (moves it to the Done list). */}
                  </div>{/* End of the buttons. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
            {unread > 0 && ( // If any are unread:
              <form action={markNoticesRead} className="mt-4">{/* the mark-read form: */}
                <BusyButton type="submit" className="text-sm text-teal-800 underline">{/* the button: */}
                  Mark all as read{/* its words, */}
                </BusyButton>{/* end of the button. */}
              </form> // End of the form.
            )}{/* End of this part. */}
          </> // End of the group.
        )}{/* End of this part. */}
        {doneNotices.length > 0 && ( // If any are ticked off as done:
          <details className="mt-6">{/* a fold-out, closed to start with: */}
            <summary className="cursor-pointer text-sm font-medium text-zinc-700">Done ({doneNotices.length === 20 ? "latest 20" : doneNotices.length})</summary>{/* its heading, with how many, */}
            <ul className="mt-2 divide-y divide-zinc-100 text-sm text-zinc-500">{/* a greyed list: */}
              {doneNotices.map((n) => ( // for each done notice:
                <li key={n.id} className="py-3">{/* a row: */}
                  <p className="flex flex-wrap items-baseline justify-between gap-2">{/* the top line: */}
                    <span className="font-medium">{n.title}</span>{/* the title, */}
                    <span className="text-xs">Done {sessionWhen(n.done_at as string)}</span>{/* when it was ticked off. */}
                  </p>{/* End of the top line. */}
                  <p className="mt-1">{n.body}</p>{/* the message, */}
                  <div className="mt-2">{/* the undo button: */}
                    <NoticeTickButton id={n.id} action="not_done" label="Not done yet: put it back" />{/* puts it back in the list, if ticked by mistake. */}
                  </div>{/* End of the button. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
          </details> // End of the fold-out.
        )}{/* End of the done list. */}
      </Card>{/* End of the card. */}
      <Card title="Pop-up notifications">{/* the pop-up notifications card (Carla, 18 Nov 2026): */}
        <PushSettings devices={(devicesRes.data ?? []) as PushDevice[]} />{/* turn pop-ups on or off for this device, see other devices, and send a test. */}
      </Card>{/* End of the card. */}
      <Card collapsible defaultOpen={false} title="Reminders">{/* the reminders fold-up card (Carla, 22 Nov 2026: 24 hours and 1 hour for everyone): */}
        <p className="text-sm text-zinc-600">{/* A note: */}
          Everyone gets a reminder 24 hours before each session and another 1 hour before. Nothing arrives between {quietWords}, your
          local time. Reminders and notices show here in the app and as pop-ups if you turn them on; CLG does not send them by email.{/* when reminders come, and quiet hours. */}
        </p>{/* End of the note. */}
      </Card>{/* End of the card. */}
      {isAdmin && ( // Owner and operations admins also see:
        <Card // a card:
          collapsible // that opens and closes,
          defaultOpen={false} // starting closed, as it's rarely changed,
          title="Quiet hours (all of CLG)" // its title,
          description={`Nothing reaches families, tutors or staff between ${quietWords}, in each person's own local time. Anything due then arrives at ${shortClock(quietEnds)}. Security alerts to the owner still come straight away.`} // and what it does.
        >{/* (end of the card's settings) */}
          <QuietHoursForm starts={quietStarts} ends={quietEnds} />{/* the form to change them. */}
        </Card> // End of the card.
      )}{/* End of the quiet hours card. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of NoticesSection.

// One small tick-off button for a notice (Carla, 20 Nov 2026): "Mark as
// seen", "Mark as done", or "Not done yet". It sends the notice id and the
// action to tickOffNotice; the database checks the notice is the person's own.
function NoticeTickButton({ id, action, label }: { id: string; action: "seen" | "done" | "not_done"; label: string }) { // The notice, what to do, and the button words.
  return ( // Shows:
    <form action={tickOffNotice}>{/* a small form: */}
      <input type="hidden" name="id" value={id} />{/* the notice (hidden), */}
      <input type="hidden" name="action" value={action} />{/* what to do (hidden), */}
      <BusyButton type="submit" className="text-xs text-teal-800 underline">{/* the button: */}
        {label}{/* its words. */}
      </BusyButton>{/* End of the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of NoticeTickButton.

// The setting for time kept free after each tutor session to write the
// session summary (Carla, 12 Nov 2026). Shown to owner and operations admins
// under "Book a session"; the database also checks who may change it.
async function SummaryTimeCard() { // The summary time card.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.from("scheduling_settings").select("summary_minutes").maybeSingle(); // Reads the current setting.
  const current = (data?.summary_minutes as number | undefined) ?? 15; // The minutes (15 if not found).
  return ( // What's shown:
    <Card // a card:
      title="Time to write session summaries" // its title,
      description={`Tutors are paid for ${current} min after each session to write the summary, so times offered leave that gap before a tutor's next session. Start times are every 15 min.`} // what it does,
      collapsible // can be opened and closed,
      defaultOpen={false} // starts closed, as it's rarely changed.
    >{/* (end of the card's settings) */}
      <SummaryMinutesForm current={current} />{/* the form to change it. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of SummaryTimeCard.

// The filters on the Bookings list, in the order shown (Carla, 12 Nov 2026).
const BOOKING_FILTERS = [ // Each filter's key (in the address) and label:
  { key: "all", label: "All" }, // every booking,
  { key: "waiting", label: "Waiting" }, // asked for, not yet answered by everyone,
  { key: "confirmed", label: "Confirmed" }, // agreed and running,
  { key: "declined", label: "Declined" }, // the tutor or family said no,
  { key: "expired", label: "Expired" }, // not answered in time,
  { key: "withdrawn", label: "Withdrawn" }, // the family withdrew it,
  { key: "stopped", label: "Stopped" }, // regular sessions finished.
]; // End of the filters.

// Which filter a booking belongs to, from its status (and whether its
// answer time has run out).
function bookingFilterKey(b: { status: string; expired: boolean }): string { // Takes a booking's status and expiry.
  if (b.status === "requested") return b.expired ? "expired" : "waiting"; // Asked for: expired once its time ran out, otherwise waiting.
  if (b.status === "cancelled") return "withdrawn"; // Cancelled by the family: withdrawn.
  if (b.status === "ended") return "stopped"; // Ended: stopped.
  return b.status; // Confirmed and declined keep their own names.
} // End of bookingFilterKey.
