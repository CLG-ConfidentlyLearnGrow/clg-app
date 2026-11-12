// Summary: helpers for the tutor's weekly calendar and their private
// calendar link (Carla, 12 Nov 2026). Works out each tutor's time zone,
// the days of a week in that time zone, and writes the calendar file
// (the ".ics" format that Google, Outlook and Apple calendars all read).
//
import { LOCAL_TIME_ZONE } from "@/lib/scheduling"; // Adelaide, the default time zone.

// The time zone for each Australian state, so a tutor sees times as their
// own clock shows them (a Victorian tutor sees Melbourne time). The same
// list as the database's private.state_timezone.
const STATE_TIME_ZONES: Record<string, string> = { // Each state's code and its time zone:
  SA: "Australia/Adelaide", // South Australia,
  NSW: "Australia/Sydney", // New South Wales,
  VIC: "Australia/Melbourne", // Victoria,
  QLD: "Australia/Brisbane", // Queensland,
  WA: "Australia/Perth", // Western Australia,
  TAS: "Australia/Hobart", // Tasmania,
  ACT: "Australia/Sydney", // the ACT (same clock as Sydney),
  NT: "Australia/Darwin", // the Northern Territory.
}; // End of the list.

// A tutor's time zone from the state they work in (Adelaide if not set).
export function timeZoneForState(state: string | null | undefined): string { // Takes the state code, if any.
  return (state && STATE_TIME_ZONES[state]) || LOCAL_TIME_ZONE; // The state's zone, or Adelaide.
} // End of timeZoneForState.

// A time zone's everyday name, e.g. "Australia/Melbourne" -> "Melbourne".
export function timeZoneName(zone: string): string { // Takes the time zone.
  return zone.split("/").pop()?.replace(/_/g, " ") ?? zone; // The last part, with underscores as spaces.
} // End of timeZoneName.

// A moment's date (YYYY-MM-DD) as the clock reads in a time zone.
export function dateIn(iso: string | number, zone: string): string { // Takes the moment and the time zone.
  return new Date(iso).toLocaleDateString("en-CA", { timeZone: zone }); // The Canadian format happens to be YYYY-MM-DD.
} // End of dateIn.

// A moment's time of day in a time zone, e.g. "4:30pm".
export function clockIn(iso: string, zone: string): string { // Takes the moment and the time zone.
  return new Date(iso) // Reads the moment,
    .toLocaleTimeString("en-AU", { hour: "numeric", minute: "2-digit", hour12: true, timeZone: zone }) // as "4:30 pm" on that clock,
    .replace(/\s/g, "") // without spaces,
    .toLowerCase(); // in lower case ("4:30pm").
} // End of clockIn.

// Adds whole days to a YYYY-MM-DD date.
export function plusDays(isoDate: string, days: number): string { // Takes the date and how many days.
  const d = new Date(`${isoDate}T00:00:00Z`); // Reads it in universal time, so daylight saving can't shift it.
  d.setUTCDate(d.getUTCDate() + days); // Moves it by that many days.
  return d.toISOString().slice(0, 10); // Hands back YYYY-MM-DD.
} // End of plusDays.

// The Monday of the week a date falls in (weeks run Monday to Sunday).
export function mondayOf(isoDate: string): string { // Takes a YYYY-MM-DD date.
  const d = new Date(`${isoDate}T00:00:00Z`); // Reads it in universal time.
  const fromMonday = (d.getUTCDay() + 6) % 7; // Days since Monday (Monday 0 … Sunday 6).
  return plusDays(isoDate, -fromMonday); // Steps back to Monday.
} // End of mondayOf.

// A date as a column heading, e.g. "Mon 17 Nov".
export function dayHeading(isoDate: string): string { // Takes a YYYY-MM-DD date.
  return new Date(`${isoDate}T00:00:00Z`).toLocaleDateString("en-AU", { // Reads it, and writes it as:
    weekday: "short", // the short day name,
    day: "numeric", // the day number,
    month: "short", // and the short month,
    timeZone: "UTC", // read in universal time (it's a plain date, so no shifting).
  }); // End of the wording.
} // End of dayHeading.

// Whether some text looks like a YYYY-MM-DD date (for the week in the address).
export function isIsoDate(value: string): boolean { // Takes the text.
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`)); // Right shape and a real date.
} // End of isIsoDate.

// ---------------------------------------------------------------------------
// The calendar file (.ics)
// ---------------------------------------------------------------------------

// One session as the database's calendar feed gives it.
export type FeedSession = { // A feed row:
  session_id: string; // the session's id,
  status: string; // its status (scheduled, completed, cancelled, no_show),
  student_first_name: string; // the student's first name,
  subject: string; // the subject,
  delivery: string; // where (online, library, home, school),
  place_name: string | null; // the library's name (libraries only),
  place_address: string | null; // the library's address (libraries only),
  starts_at: string; // when it starts,
  ends_at: string; // when it ends,
  meeting_url: string | null; // the Teams link (online, not cancelled),
  time_zone: string; // the tutor's time zone.
}; // End of FeedSession.

// Makes text safe inside a calendar file: backslashes, semicolons, commas
// and line breaks each need a backslash in front (the .ics rules).
function icsText(value: string): string { // Takes the text.
  return value // Starting from the text:
    .replace(/\\/g, "\\\\") // doubles any backslash,
    .replace(/;/g, "\\;") // marks semicolons,
    .replace(/,/g, "\\,") // marks commas,
    .replace(/\r?\n/g, "\\n"); // and turns line breaks into "\n".
} // End of icsText.

// A moment in the calendar file's universal-time format, e.g. 20261117T053000Z.
function icsTime(iso: string | number): string { // Takes the moment.
  return new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, ""); // Drops dashes, colons and milliseconds.
} // End of icsTime.

// Splits a long line into pieces of at most 75 bytes, each new piece
// starting with a space (the .ics rule, so calendar apps read it whole).
function fold(line: string): string { // Takes one line.
  const bytes = new TextEncoder(); // Counts bytes (some characters take more than one).
  const parts: string[] = []; // The pieces so far.
  let current = ""; // The piece being built.
  for (const ch of line) { // Goes through each character:
    const limit = parts.length === 0 ? 75 : 74; // the first piece may be 75 bytes; the rest 74 (plus their leading space),
    if (bytes.encode(current + ch).length > limit) { // if this character would make the piece too long,
      parts.push(current); // closes the piece,
      current = ""; // and starts a new one.
    } // End of the length check.
    current += ch; // Adds the character.
  } // End of the characters.
  parts.push(current); // Closes the last piece.
  return parts.join("\r\n "); // Joins the pieces, each new one on its own line starting with a space.
} // End of fold.

// Plain words for where a session happens, for the calendar entry.
function whereWords(s: FeedSession): string { // Takes a session.
  if (s.delivery === "online") return "Online (Teams)"; // Online.
  if (s.delivery === "library") return [s.place_name ?? "Library", s.place_address].filter(Boolean).join(", "); // A library, with its address.
  if (s.delivery === "school") return "At the student's school"; // At school.
  return "In person (see the CLG app)"; // At home: no address in the calendar (the app has the details).
} // End of whereWords.

// Writes the whole calendar file for a tutor's sessions.
export function buildCalendar(sessions: FeedSession[], appUrl: string): string { // Takes the sessions and the app's web address.
  const zone = sessions[0]?.time_zone ?? LOCAL_TIME_ZONE; // The tutor's time zone (Adelaide if there are no sessions).
  const stamp = icsTime(Date.now()); // When this file was made.
  const lines: string[] = [ // The calendar's opening lines:
    "BEGIN:VCALENDAR", // starts the calendar,
    "VERSION:2.0", // the format's version,
    "PRODID:-//CLG Tutoring//CLG app//EN", // who made it,
    "CALSCALE:GREGORIAN", // the everyday calendar,
    "METHOD:PUBLISH", // a calendar to subscribe to (not an invitation),
    "X-WR-CALNAME:CLG sessions", // its name in the calendar app,
    `X-WR-TIMEZONE:${zone}`, // the tutor's time zone (times below are universal; apps show them on the tutor's clock),
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H", // asks apps to check for changes every hour,
    "X-PUBLISHED-TTL:PT1H", // the same, for apps that read this older line.
  ]; // End of the opening lines.
  for (const s of sessions) { // For each session:
    const cancelled = s.status === "cancelled"; // whether it's cancelled,
    const title = `${cancelled ? "Cancelled: " : ""}CLG: ${s.student_first_name} – ${s.subject}`; // its title, e.g. "CLG: Sam – Mathematics",
    const details = [ // the notes inside the entry:
      `${s.student_first_name} – ${s.subject}`, // the student's first name and subject,
      whereWords(s), // where,
      s.meeting_url ? `Join on Teams: ${s.meeting_url}` : "", // the Teams link (if any),
      cancelled ? "This session was cancelled." : "", // a note if it's cancelled,
      `Details and changes: ${appUrl}/dashboard/tutor/calendar`, // where to see more in the app.
    ].filter(Boolean).join("\n"); // (leaving out blank lines, one per line)
    lines.push( // Adds the entry:
      "BEGIN:VEVENT", // starts it,
      `UID:${s.session_id}@clgtutoring.com`, // its lasting id (so changes update the same entry),
      `DTSTAMP:${stamp}`, // when this copy was made,
      `DTSTART:${icsTime(s.starts_at)}`, // when it starts,
      `DTEND:${icsTime(s.ends_at)}`, // when it ends,
      `SUMMARY:${icsText(title)}`, // its title,
      `LOCATION:${icsText(s.meeting_url ?? whereWords(s))}`, // where (the Teams link for online sessions, so it's one tap to join),
      `DESCRIPTION:${icsText(details)}`, // the notes,
      ...(s.meeting_url ? [`URL:${s.meeting_url}`] : []), // the Teams link again, as the entry's link (if any),
      `STATUS:${cancelled ? "CANCELLED" : "CONFIRMED"}`, // cancelled or going ahead,
      `TRANSP:${cancelled ? "TRANSPARENT" : "OPAQUE"}`, // cancelled ones don't mark the tutor as busy,
      "END:VEVENT", // ends it.
    ); // End of the entry.
  } // End of the sessions.
  lines.push("END:VCALENDAR"); // Ends the calendar.
  return lines.map(fold).join("\r\n") + "\r\n"; // Folds long lines and joins them with the line breaks the format needs.
} // End of buildCalendar.
