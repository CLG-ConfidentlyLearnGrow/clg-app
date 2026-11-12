// Summary: the tutor's weekly calendar (Carla, 12 Nov 2026). Shows one week
// at a time, Monday to Sunday, with each of the tutor's sessions: time,
// student, subject, place and the Teams link for online sessions. Times are
// on the tutor's own clock (the state they work in; Adelaide if not set).
// Under it, the tutor can make a private link to see the same sessions in
// Google, Outlook or Apple calendar.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { Card, Empty, TextLink } from "@/components/ui"; // Shared page parts: card, empty line and text link.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Whether two-step sign-in is still needed, and the signed-in person.
import { SESSION_STATUS_NAMES, currentTime, lengthLabel, placeLabel } from "@/lib/scheduling"; // Session status names, the time now, length wording, place wording.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { // The calendar helpers:
  clockIn, // a time of day on a given clock,
  dateIn, // a date on a given clock,
  dayHeading, // a day's heading ("Mon 17 Nov"),
  isIsoDate, // whether text is a date,
  mondayOf, // the Monday of a week,
  plusDays, // adding days to a date,
  timeZoneForState, // a tutor's time zone from their state,
  timeZoneName, // a time zone's everyday name.
} from "@/lib/tutor-calendar"; // End of the helpers.
import { CalendarLinkCard } from "./link-card"; // The calendar link controls.

type Session = { // One session as the database lists it:
  id: string; // its id,
  status: string; // its status,
  student_name: string; // the student's name,
  tutor_id: string; // the tutor,
  subject: string; // the subject,
  delivery: string; // where,
  library_name: string | null; // the library's name (if any),
  starts_at: string; // when it starts,
  ends_at: string; // when it ends,
  meeting_url: string | null; // and its Teams link (if any).
}; // End of Session.

// A date and time in words for the link card, e.g. "12 Nov 2026, 4:30pm".
function when(iso: string, zone: string): string { // Takes the moment and the tutor's time zone.
  const date = new Date(iso).toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric", timeZone: zone }); // "12 Nov 2026" on their clock,
  return `${date}, ${clockIn(iso, zone)}`; // with the time.
} // End of when.

export default async function TutorCalendarPage({ searchParams }: PageProps<"/dashboard/tutor/calendar">) { // The page itself (reads the address's settings).
  const viewer = await requireViewer(); // The signed-in person.
  if (!viewer.roles.includes("tutor")) redirect("/dashboard"); // Not a tutor: sends them to their main dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step sign-in not set up: sends them to set it up.
  const params = await searchParams; // The address's settings.

  const supabase = await createClient(); // Connects to the database.
  const [workRes, linkRes] = await Promise.all([ // Reads two things at once:
    supabase.from("tutor_work_settings").select("work_state").eq("tutor_id", viewer.id).maybeSingle(), // the state they work in,
    supabase.from("tutor_calendar_links").select("created_at, last_used_at").eq("tutor_id", viewer.id).maybeSingle(), // and their calendar link (if any).
  ]); // End of the reads.
  const zone = timeZoneForState((workRes.data as { work_state: string | null } | null)?.work_state); // Their time zone.
  const link = linkRes.data as { created_at: string; last_used_at: string | null } | null; // Their calendar link's details (if any).

  // The week to show: the one in the address (?week=YYYY-MM-DD), or this week.
  const today = dateIn(currentTime(), zone); // Today's date on the tutor's clock.
  const askedWeek = typeof params.week === "string" && isIsoDate(params.week) ? params.week : today; // The date asked for, or today.
  const monday = mondayOf(askedWeek); // That week's Monday.
  const days = Array.from({ length: 7 }, (_, i) => plusDays(monday, i)); // The week's seven dates, Monday to Sunday.

  // Reads a day either side, because the database's dates are in universal
  // time; each session is then placed on its day by the tutor's own clock.
  const { data } = await supabase.rpc("list_sessions", { p_from: plusDays(monday, -1), p_to: plusDays(monday, 7) }); // The sessions they can see that week.
  const sessions = ((data ?? []) as Session[]).filter((s) => s.tutor_id === viewer.id && days.includes(dateIn(s.starts_at, zone))); // Only their own, only this week.
  const byDay = new Map(days.map((d) => [d, sessions.filter((s) => dateIn(s.starts_at, zone) === d)])); // Each day's sessions.
  const booked = sessions.filter((s) => s.status !== "cancelled"); // Sessions going ahead (or done).
  const minutes = booked.reduce((t, s) => t + (new Date(s.ends_at).getTime() - new Date(s.starts_at).getTime()) / 60000, 0); // Their total time this week, in minutes.

  const weekHref = (d: string) => `/dashboard/tutor/calendar?week=${d}`; // The address of a week's page.
  const isThisWeek = monday === mondayOf(today); // Whether this is the current week.

  return ( // Shows:
    <DashboardFrame role="tutor" roles={viewer.roles} current="calendar">{/* the tutor dashboard's tabs and menu, with Weekly calendar open: */}
      <Card // the week's card:
        title={`Week of ${dayHeading(monday)}`} // its title, e.g. "Week of Mon 17 Nov",
        description={`${booked.length} session${booked.length === 1 ? "" : "s"}${minutes ? `, ${lengthLabel(minutes)}` : ""}. Times are ${timeZoneName(zone)} time.`} // how many sessions and hours, and which clock the times use.
      >{/* (end of the card's settings) */}
        <nav className="mb-4 flex flex-wrap items-center gap-4 text-sm" aria-label="Choose a week">{/* the week buttons: */}
          <TextLink href={weekHref(plusDays(monday, -7))}>← Last week</TextLink>{/* the week before, */}
          {!isThisWeek && <TextLink href={weekHref(today)}>This week</TextLink>}{/* back to this week (if looking at another), */}
          <TextLink href={weekHref(plusDays(monday, 7))}>Next week →</TextLink>{/* the week after. */}
        </nav>{/* End of the week buttons. */}

        <ol className="grid gap-3 md:grid-cols-7">{/* the seven days: one under another on phones, side by side on wider screens: */}
          {days.map((d) => { // For each day:
            const list = byDay.get(d) ?? []; // its sessions,
            const isToday = d === today; // whether it's today.
            return ( // Shows:
              <li key={d} className={`rounded-xl border p-3 ${isToday ? "border-teal-400 bg-teal-50/40" : "border-zinc-200"}`}>{/* a box for the day (outlined in teal if it's today): */}
                <p className="mb-2 text-sm font-semibold">{/* the day's heading: */}
                  {dayHeading(d)}{/* e.g. "Mon 17 Nov", */}
                  {isToday && <span className="ml-1 text-xs font-normal text-teal-800">(today)</span>}{/* and "(today)" if it is. */}
                </p>{/* End of the heading. */}
                {list.length === 0 ? ( // No sessions that day:
                  <p className="text-xs text-zinc-400">No sessions</p> // says so, quietly.
                ) : ( // Otherwise:
                  <ul className="space-y-2">{/* the day's sessions: */}
                    {list.map((s) => { // For each session:
                      const cancelled = s.status === "cancelled"; // whether it's cancelled.
                      return ( // Shows:
                        <li key={s.id} className={`rounded-lg bg-white p-2 text-xs shadow-sm ring-1 ring-zinc-100 ${cancelled ? "opacity-60" : ""}`}>{/* a small card (faded if cancelled): */}
                          <p className={`font-semibold ${cancelled ? "line-through" : ""}`}>{/* the time (crossed out if cancelled): */}
                            {clockIn(s.starts_at, zone)}–{clockIn(s.ends_at, zone)}{/* start to end, */}
                          </p>{/* End of the time. */}
                          <p>{s.student_name}</p>{/* the student, */}
                          <p className="text-zinc-600">{s.subject}</p>{/* the subject, */}
                          <p className="text-zinc-600">{placeLabel(s.delivery, s.library_name)}</p>{/* where, */}
                          {s.status !== "scheduled" && <p className="text-zinc-500">{SESSION_STATUS_NAMES[s.status] ?? s.status}</p>}{/* its status, unless simply booked, */}
                          {s.meeting_url && !cancelled && ( // the Teams link, for online sessions going ahead:
                            <a href={s.meeting_url} target="_blank" rel="noreferrer" className="font-medium text-teal-700 underline">{/* opens Teams in a new tab, */}
                              Join on Teams{/* its words. */}
                            </a> // End of the link.
                          )}{/* End of the Teams part. */}
                        </li> // End of the session's card.
                      ); // End of what's shown for this session.
                    })}{/* End of the sessions. */}
                  </ul> // End of the day's sessions.
                )}{/* End of the day's contents. */}
              </li> // End of the day's box.
            ); // End of what's shown for this day.
          })}{/* End of the days. */}
        </ol>{/* End of the seven days. */}
        {sessions.length === 0 && ( // No sessions all week:
          <div className="mt-4">{/* a little space, then: */}
            <Empty>No sessions this week. New bookings appear here once they&apos;re confirmed.</Empty>{/* a friendly note. */}
          </div> // End of the note.
        )}{/* End of the empty part. */}
        <p className="mt-4 text-sm">{/* a link to the rest: */}
          <TextLink href="/schedule?as=tutor">Sessions</TextLink> has your bookings, sign-on and session records.{/* where to sign on and record sessions. */}
        </p>{/* End of the link. */}
      </Card>{/* End of the week's card. */}

      <Card // the calendar link card:
        title="Add to your own calendar" // its title,
        description="A private link that shows your CLG sessions in Google, Outlook or Apple calendar, and keeps them up to date. It shows only each student's first name, the subject, the time, the place and the Teams link. Keep it to yourself." // what it does and what it shows.
      >{/* (end of the card's settings) */}
        <CalendarLinkCard // the link controls:
          hasLink={Boolean(link)} // whether they already have a link,
          madeOn={link ? when(link.created_at, zone) : null} // when it was made,
          lastUsed={link?.last_used_at ? when(link.last_used_at, zone) : null} // and when a calendar app last used it.
        />{/* End of the link controls. */}
        <p className="mt-4 text-xs text-zinc-500">{/* a note on timing: */}
          Calendar apps check for changes every few hours (Google can take up to a day), so always check this page or Sessions for last-minute changes.{/* that updates aren't instant. */}
        </p>{/* End of the note. */}
      </Card>{/* End of the calendar link card. */}
    </DashboardFrame> // End of the dashboard frame.
  ); // End of what's shown.
} // End of TutorCalendarPage.
