// Summary: the weekly calendar for parents and students (Carla, 15 Nov 2026:
// "Student and parent profiles should also get a similar calendar entry as
// tutors do"). Shows one week at a time, Monday to Sunday, with each of the
// family's sessions: time, child, subject, tutor, place and a Join on Teams
// button for online sessions. Under it, the person can make a private link
// to see the same sessions in Google, Outlook or Apple calendar (without
// Teams links, which stay in the app).
//
// "?as=parent" shows it in the parent dashboard (their children's
// sessions); "?as=student" in the student dashboard (their own sessions).
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { Card, Empty, TextLink } from "@/components/ui"; // Shared page parts: card, empty line and text link.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { CalendarLinkCard } from "@/components/calendar-link-card"; // The calendar link controls.
import { WeekGrid } from "@/components/week-grid"; // The seven-day grid of sessions.
import { requireViewer, type Role } from "@/lib/auth"; // The signed-in person, and the role type.
import { currentTime, lengthLabel, placeLabel } from "@/lib/scheduling"; // The time now, length wording, place wording.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { // The calendar helpers:
  clockIn, // a time of day on a given clock,
  dateIn, // a date on a given clock,
  dayHeading, // a day's heading ("Mon 17 Nov"),
  isIsoDate, // whether text is a date,
  mondayOf, // the Monday of a week,
  plusDays, // adding days to a date,
  timeZoneForState, // a time zone from a state,
  timeZoneName, // a time zone's everyday name.
} from "@/lib/tutor-calendar"; // End of the helpers.

type Session = { // One session as the database lists it:
  id: string; // its id,
  status: string; // its status,
  student_id: string; // the student,
  student_name: string; // the student's name,
  tutor_name: string; // the tutor's name,
  subject: string; // the subject,
  delivery: string; // where,
  library_name: string | null; // the library's name (if any),
  starts_at: string; // when it starts,
  ends_at: string; // when it ends,
  meeting_url: string | null; // and its Teams link (if any).
}; // End of Session.

// A date and time in words for the link card, e.g. "12 Nov 2026, 4:30pm".
function when(iso: string, zone: string): string { // Takes the moment and the time zone.
  const date = new Date(iso).toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric", timeZone: zone }); // "12 Nov 2026" on that clock,
  return `${date}, ${clockIn(iso, zone)}`; // with the time.
} // End of when.

export default async function FamilyCalendarPage({ searchParams }: PageProps<"/dashboard/calendar">) { // The page itself (reads the address's settings).
  const viewer = await requireViewer(); // The signed-in person.
  const mine = (["parent", "student"] as Role[]).filter((r) => viewer.roles.includes(r)); // Their family dashboards (parent, student or both).
  if (mine.length === 0) redirect("/dashboard"); // Neither: sends them to their main dashboard.
  const params = await searchParams; // The address's settings.
  const asked = (typeof params.as === "string" ? params.as : "") as Role; // The dashboard in the address, if any.
  const role: Role = mine.includes(asked) ? asked : mine[0]; // That dashboard if they have it, otherwise their first family one.

  const supabase = await createClient(); // Connects to the database.
  // The students this dashboard is for: a parent's children, or the student themself.
  const familyRes = role === "parent" // Reads the students:
    ? await supabase.from("parent_student_links").select("student_id").eq("parent_id", viewer.id) // a parent's linked children,
    : await supabase.from("students").select("student_id:id").eq("account_id", viewer.id); // or the student's own record.
  const familyIds = new Set(((familyRes.data ?? []) as { student_id: string }[]).map((r) => r.student_id)); // Their ids.
  const [statesRes, linkRes] = await Promise.all([ // Reads two things at once:
    familyIds.size // the students' states (for the time zone), if there are any students:
      ? supabase.from("students").select("state").in("id", [...familyIds]).limit(1) // the first one's state,
      : Promise.resolve({ data: [] as { state: string }[] }), // otherwise none,
    supabase.from("family_calendar_links").select("created_at, last_used_at").eq("account_id", viewer.id).maybeSingle(), // and their calendar link (if any).
  ]); // End of the reads.
  const zone = timeZoneForState(((statesRes.data ?? []) as { state: string }[])[0]?.state); // The time zone of the student's state (Adelaide if unknown).
  const link = linkRes.data as { created_at: string; last_used_at: string | null } | null; // Their calendar link's details (if any).

  // The week to show: the one in the address (?week=YYYY-MM-DD), or this week.
  const today = dateIn(currentTime(), zone); // Today's date on the family's clock.
  const askedWeek = typeof params.week === "string" && isIsoDate(params.week) ? params.week : today; // The date asked for, or today.
  const monday = mondayOf(askedWeek); // That week's Monday.
  const days = Array.from({ length: 7 }, (_, i) => plusDays(monday, i)); // The week's seven dates, Monday to Sunday.

  // Reads a day either side, because the database's dates are in universal
  // time; each session is then placed on its day by the family's clock.
  const { data } = await supabase.rpc("list_sessions", { p_from: plusDays(monday, -1), p_to: plusDays(monday, 7) }); // The sessions they can see that week.
  const sessions = ((data ?? []) as Session[]).filter((s) => familyIds.has(s.student_id) && days.includes(dateIn(s.starts_at, zone))); // Only this dashboard's students, only this week.
  const booked = sessions.filter((s) => s.status !== "cancelled"); // Sessions going ahead (or done).
  const minutes = booked.reduce((t, s) => t + (new Date(s.ends_at).getTime() - new Date(s.starts_at).getTime()) / 60000, 0); // Total time this week, in minutes.

  const weekHref = (d: string) => `/dashboard/calendar?as=${role}&week=${d}`; // The address of a week's page in this dashboard.
  const isThisWeek = monday === mondayOf(today); // Whether this is the current week.
  const firstName = (name: string) => name.trim().split(/\s+/)[0] ?? name; // A person's first name.

  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="calendar">{/* the dashboard's tabs and menu, with Weekly calendar open: */}
      <Card // the week's card:
        title={`Week of ${dayHeading(monday)}`} // its title, e.g. "Week of Mon 17 Nov",
        description={`${booked.length} session${booked.length === 1 ? "" : "s"}${minutes ? `, ${lengthLabel(minutes)}` : ""}. Times are ${timeZoneName(zone)} time.`} // how many sessions and hours, and which clock the times use.
      >{/* (end of the card's settings) */}
        <nav className="mb-4 flex flex-wrap items-center gap-4 text-sm" aria-label="Choose a week">{/* the week buttons: */}
          <TextLink href={weekHref(plusDays(monday, -7))}>← Last week</TextLink>{/* the week before, */}
          {!isThisWeek && <TextLink href={weekHref(today)}>This week</TextLink>}{/* back to this week (if looking at another), */}
          <TextLink href={weekHref(plusDays(monday, 7))}>Next week →</TextLink>{/* the week after. */}
        </nav>{/* End of the week buttons. */}
        <WeekGrid // the seven days:
          days={days} // the week's dates,
          today={today} // today (outlined),
          zone={zone} // times on the family's clock,
          items={sessions.map((s) => ({ // each session:
            id: s.id, // its id,
            status: s.status, // status,
            starts_at: s.starts_at, // start,
            ends_at: s.ends_at, // end,
            lines: [ // the words under the time:
              ...(role === "parent" ? [s.student_name] : []), // the child (parents only; a student knows it's them),
              s.subject, // the subject,
              `with ${firstName(s.tutor_name)}`, // the tutor's first name,
              placeLabel(s.delivery, s.library_name), // and where.
            ], // (end of the words)
            meeting_url: s.meeting_url, // and the Teams link.
          }))} // (end of the sessions)
        />{/* End of the seven days. */}
        {sessions.length === 0 && ( // No sessions all week:
          <div className="mt-4">{/* a little space, then: */}
            <Empty>No sessions this week. New bookings appear here once they are confirmed.</Empty>{/* a friendly note. */}
          </div> // End of the note.
        )}{/* End of the empty part. */}
        <p className="mt-4 text-sm">{/* a link to the rest: */}
          <TextLink href={`/schedule?as=${role}`}>Sessions</TextLink> has your bookings, cancellations and away dates.{/* where to manage bookings. */}
        </p>{/* End of the link. */}
      </Card>{/* End of the week's card. */}

      <Card // the calendar link card:
        title="Add to your own calendar" // its title,
        description="A private link that shows your CLG sessions in Google, Outlook or Apple calendar, and keeps them up to date. It shows only first names, the subject, the time and the place. For online sessions, join from this page (Teams links stay in the app for safety). Keep it to yourself, or share it only with family who should see these sessions." // what it does and what it shows.
      >{/* (end of the card's settings) */}
        <CalendarLinkCard // the link controls:
          kind="family" // a family member's link,
          hasLink={Boolean(link)} // whether they already have one,
          madeOn={link ? when(link.created_at, zone) : null} // when it was made,
          lastUsed={link?.last_used_at ? when(link.last_used_at, zone) : null} // and when a calendar app last used it.
        />{/* End of the link controls. */}
        <p className="mt-4 text-xs text-zinc-500">{/* a note on timing: */}
          Calendar apps check for changes every few hours (Google can take up to a day), so check this page or Sessions for last-minute changes.{/* that updates aren't instant. */}
        </p>{/* End of the note. */}
      </Card>{/* End of the calendar link card. */}
    </DashboardFrame> // End of the dashboard frame.
  ); // End of what's shown.
} // End of FamilyCalendarPage.
