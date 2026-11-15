// Summary: shared helpers for the scheduling module: session lengths, the
// local time zone, and turning dates, times, places and statuses into plain
// words for the scheduling pages.

// The session lengths families can book, in minutes (1 hr to 3 hr in half-hour steps).
export const SESSION_LENGTHS = [60, 90, 120, 150, 180] as const;

// All students are in South Australia for now. Times are shown in the
// student's local time; this is the default until other states join.
export const LOCAL_TIME_ZONE = "Australia/Adelaide";

// The days of the week, Monday first.
export const WEEKDAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

// "16:30:00" -> "4:30pm"
export function clockTime(value: string): string {
  const [h, m] = value.split(":").map(Number); // Splits into hour and minute numbers.
  const suffix = h >= 12 ? "pm" : "am"; // Noon onwards is "pm".
  const hour = h % 12 === 0 ? 12 : h % 12; // Turns 24-hour into 12-hour (0 and 12 both show as 12).
  return `${hour}:${String(m).padStart(2, "0")}${suffix}`; // Joins them, with minutes always two digits.
} // End of clockTime.

// Short clock wording for quiet hours: "21:00:00" -> "9pm", "05:30:00" -> "5:30am".
export function shortClock(value: string): string { // Takes a time of day as text.
  return clockTime(value).replace(":00", ""); // Uses the usual wording, without ":00" when it's on the hour.
} // End of shortClock.

// 90 -> "1.5 hr"
export function lengthLabel(minutes: number): string {
  return `${minutes / 60} hr`; // Minutes divided by 60, followed by "hr".
} // End of lengthLabel.

// A session's date and time in local time, e.g. "Mon 3 Nov, 4:00pm".
export function sessionWhen(iso: string): string {
  const d = new Date(iso); // Reads the stored moment.
  const date = d.toLocaleDateString("en-AU", { weekday: "short", day: "numeric", month: "short", timeZone: LOCAL_TIME_ZONE }); // "Mon 3 Nov" in Adelaide time.
  const time = d // The time part:
    .toLocaleTimeString("en-AU", { hour: "numeric", minute: "2-digit", hour12: true, timeZone: LOCAL_TIME_ZONE }) // "4:00 PM" in Adelaide time,
    .replace(" ", "") // without the space,
    .toLowerCase(); // in lower case ("4:00pm").
  return `${date}, ${time}`; // Joins date and time.
} // End of sessionWhen.

// A date as "3 Nov 2026".
export function shortDate(iso: string): string {
  return new Date(`${iso.slice(0, 10)}T00:00:00`).toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric" }); // Uses just the date part.
} // End of shortDate.

// Where a session happens, in plain words.
export function placeLabel(delivery: string, libraryName: string | null): string {
  if (delivery === "online") return "Online"; // Online sessions.
  if (delivery === "home") return "At home"; // At the student's home.
  if (delivery === "school") return "At school"; // At the student's school.
  return libraryName ?? "Library"; // Otherwise a library, by name if known.
} // End of placeLabel.

// Plain names for each session stage.
export const SESSION_STATUS_NAMES: Record<string, string> = {
  scheduled: "Booked", // Coming up.
  completed: "Done", // Happened.
  cancelled: "Cancelled", // Called off.
  no_show: "No-show", // Someone didn't turn up.
}; // End of the session stage names.

// Plain names for each booking request stage.
export const BOOKING_STATUS_NAMES: Record<string, string> = {
  requested: "Waiting for the tutor", // Sent to the tutor, not yet answered.
  confirmed: "Confirmed", // The tutor accepted.
  declined: "Declined", // The tutor said no.
  cancelled: "Withdrawn", // The family withdrew it.
  ended: "Stopped", // Regular sessions have finished.
}; // End of the booking stage names.

// Today's date as YYYY-MM-DD in local time.
export function localToday(): string {
  return new Date().toLocaleDateString("en-CA", { timeZone: LOCAL_TIME_ZONE }); // The Canadian format happens to be YYYY-MM-DD.
} // End of localToday.

// Adds (or subtracts) whole days to a YYYY-MM-DD date.
export function addDays(isoDate: string, days: number): string {
  const d = new Date(`${isoDate}T00:00:00Z`); // Reads the date in universal time, so daylight saving can't shift it.
  d.setUTCDate(d.getUTCDate() + days); // Moves it by that many days.
  return d.toISOString().slice(0, 10); // Hands back YYYY-MM-DD.
} // End of addDays.

// The current time, read once per page request on the server.
export function currentTime(): number {
  return Date.now(); // Milliseconds since 1970, the computer's usual clock.
} // End of currentTime.

// A moment's local date (YYYY-MM-DD) and 24-hour time (HH:MM), for forms.
export function localDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-CA", { timeZone: LOCAL_TIME_ZONE }); // The date part, in Adelaide time.
} // End of localDate.

// A moment's local 24-hour time, e.g. "16:30", for form fields.
export function localClock(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: LOCAL_TIME_ZONE }); // British format gives HH:MM.
} // End of localClock.

// Why a session's times need an admin to check them, in plain words.
export const TIME_CHECK_REASONS: Record<string, string> = {
  different_end: "Tutor recorded a different end time", // The tutor changed the finish time.
  not_signed_on: "Tutor didn't sign on", // No sign-on was recorded.
  not_at_library: "Sign-on check didn't place the tutor at the library", // The location didn't match.
  no_location: "Signed on without a location check", // No location was shared.
}; // End of the time check reasons.

// Why a session is being cancelled: the short name the database keeps, and
// the words shown in the drop-down (Carla, 16 Nov 2026). "Other" needs a few words.
export const CANCEL_REASONS: [string, string][] = [ // (the list)
  ["sick", "Sick or unwell"], // sick,
  ["away", "Away or travelling"], // away,
  ["school_event", "School or uni event"], // a school or uni event,
  ["family", "Family matter"], // a family matter,
  ["clash", "Clashes with something else"], // a clash,
  ["other", "Other"], // other.
]; // End of the list.

// The seven dates (Monday to Sunday, YYYY-MM-DD) of the local week a
// session falls in. Make-up times must be in that week.
export function weekDates(iso: string): string[] {
  const day = localDate(iso); // The session's local date.
  const weekday = new Date(`${day}T00:00:00Z`).getUTCDay(); // Its day of the week (0 is Sunday).
  const monday = addDays(day, weekday === 0 ? -6 : 1 - weekday); // Steps back to that week's Monday.
  return Array.from({ length: 7 }, (_, i) => addDays(monday, i)); // Monday plus the next six days.
} // End of weekDates.

// "2026-11-20" -> "Thu 20 Nov", for drop-downs.
export function dayLabel(isoDate: string): string {
  return new Date(`${isoDate}T00:00:00Z`).toLocaleDateString("en-AU", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }); // Read and shown in universal time, so the date can't shift.
} // End of dayLabel.

// Start times every 15 minutes from 7am to 8:45pm ("07:00" to "20:45"),
// for choosing make-up times (sessions start on the quarter hour).
export const QUARTER_HOURS: string[] = Array.from({ length: 14 * 4 }, (_, i) => // 14 hours of four quarter hours each:
  `${String(7 + Math.floor(i / 4)).padStart(2, "0")}:${String((i % 4) * 15).padStart(2, "0")}`, // the hour from 7, and 00, 15, 30 or 45 minutes.
); // End of the list.

// Plain words for where a make-up offer is up to.
export const MAKEUP_STATUS_NAMES: Record<string, string> = {
  waiting: "Waiting for a pick", // Two times offered, not yet answered.
  confirming: "Waiting for confirmation", // One side picked; the other side must agree first.
  picked: "Make-up booked", // A time was picked and booked.
  declined: "Neither time works", // The other side said neither works.
  expired: "Not picked in time", // Both times passed with no answer.
  none_offered: "No other time this week", // The person cancelling couldn't offer times.
}; // End of the make-up stage names.
