// Shared helpers for the scheduling module.

export const SESSION_LENGTHS = [60, 90, 120, 150, 180] as const;

// All students are in South Australia for now. Times are shown in the
// student's local time; this is the default until other states join.
export const LOCAL_TIME_ZONE = "Australia/Adelaide";

export const WEEKDAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

// "16:30:00" -> "4:30pm"
export function clockTime(value: string): string {
  const [h, m] = value.split(":").map(Number);
  const suffix = h >= 12 ? "pm" : "am";
  const hour = h % 12 === 0 ? 12 : h % 12;
  return `${hour}:${String(m).padStart(2, "0")}${suffix}`;
}

// 90 -> "1.5 hr"
export function lengthLabel(minutes: number): string {
  return `${minutes / 60} hr`;
}

// A session's date and time in local time, e.g. "Mon 3 Nov, 4:00pm".
export function sessionWhen(iso: string): string {
  const d = new Date(iso);
  const date = d.toLocaleDateString("en-AU", { weekday: "short", day: "numeric", month: "short", timeZone: LOCAL_TIME_ZONE });
  const time = d
    .toLocaleTimeString("en-AU", { hour: "numeric", minute: "2-digit", hour12: true, timeZone: LOCAL_TIME_ZONE })
    .replace(" ", "")
    .toLowerCase();
  return `${date}, ${time}`;
}

export function shortDate(iso: string): string {
  return new Date(`${iso.slice(0, 10)}T00:00:00`).toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric" });
}

export function placeLabel(delivery: string, libraryName: string | null): string {
  if (delivery === "online") return "Online";
  if (delivery === "home") return "At home";
  return libraryName ?? "Library";
}

export const SESSION_STATUS_NAMES: Record<string, string> = {
  scheduled: "Booked",
  completed: "Done",
  cancelled: "Cancelled",
  no_show: "No-show",
};

export const BOOKING_STATUS_NAMES: Record<string, string> = {
  requested: "Waiting for the tutor",
  confirmed: "Confirmed",
  declined: "Declined",
  cancelled: "Withdrawn",
  ended: "Stopped",
};

// Today's date as YYYY-MM-DD in local time.
export function localToday(): string {
  return new Date().toLocaleDateString("en-CA", { timeZone: LOCAL_TIME_ZONE });
}

export function addDays(isoDate: string, days: number): string {
  const d = new Date(`${isoDate}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

// The current time, read once per page request on the server.
export function currentTime(): number {
  return Date.now();
}
