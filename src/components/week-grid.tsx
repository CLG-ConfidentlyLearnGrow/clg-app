// Summary: one week of sessions, Monday to Sunday, as seven day boxes (side
// by side on wider screens, one under another on phones). Shared by the
// tutors' and families' weekly calendar pages (Carla, 12 and 15 Nov 2026).
//
import { SESSION_STATUS_NAMES } from "@/lib/scheduling"; // Plain names for each session status.
import { clockIn, dateIn, dayHeading } from "@/lib/tutor-calendar"; // A time on a clock, a date on a clock, and a day's heading.

// One session as the grid shows it.
export type WeekItem = { // A session:
  id: string; // its id,
  status: string; // its status (scheduled, completed, cancelled, no_show),
  starts_at: string; // when it starts,
  ends_at: string; // when it ends,
  lines: string[]; // the lines of words under the time (e.g. student, subject, place),
  meeting_url: string | null; // and its Teams link (online sessions; shown as a Join button).
}; // End of WeekItem.

// Shows the week. "days" are the seven dates; "today" is today's date on
// the viewer's clock; "zone" is the clock the times are shown on.
export function WeekGrid({ days, today, zone, items }: { days: string[]; today: string; zone: string; items: WeekItem[] }) { // Takes the week and its sessions.
  return ( // Shows:
    <ol className="grid gap-3 md:grid-cols-7">{/* the seven days: one under another on phones, side by side on wider screens: */}
      {days.map((d) => { // For each day:
        const list = items.filter((s) => dateIn(s.starts_at, zone) === d); // its sessions,
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
                      {s.lines.map((line, i) => ( // each line of words:
                        <p key={i} className={i === 0 ? "" : "text-zinc-600"}>{line}</p> // the first plain, the rest grey.
                      ))}{/* End of the lines. */}
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
    </ol> // End of the seven days.
  ); // End of what's shown.
} // End of WeekGrid.
