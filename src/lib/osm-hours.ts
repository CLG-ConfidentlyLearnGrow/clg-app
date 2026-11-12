// Reads simple OpenStreetMap opening hours, such as
// "Mo-Fr 09:30-17:00; Sa 10:00-13:00; Su off", into weekly rows
// (weekday 1 = Monday). Anything more complicated (public holiday rules,
// months, week numbers) returns null, and the admin enters the hours by hand.

// One opening time: the weekday, when it opens and when it closes.
export type WeeklyHours = { weekday: number; opens: string; closes: string }; // (the shape)

const DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]; // The OpenStreetMap day codes, Monday first.

// Turns day codes like "Mo-Fr,Su" into weekday numbers (or nothing if it can't).
function dayList(part: string): number[] | null { // (takes the day part of a rule)
  const out: number[] = []; // The weekday numbers found.
  for (const piece of part.split(",")) { // For each comma-separated piece:
    const range = piece.trim().match(/^(Mo|Tu|We|Th|Fr|Sa|Su)(?:-(Mo|Tu|We|Th|Fr|Sa|Su))?$/); // checks it's one day or a range of days,
    if (!range) return null; // anything else: can't read it.
    const from = DAYS.indexOf(range[1]); // The first day's position,
    const to = range[2] ? DAYS.indexOf(range[2]) : from; // the last day's position (the same if it's one day),
    if (to < from) return null; // a range that runs backwards: can't read it.
    for (let d = from; d <= to; d++) out.push(d + 1); // Adds every day in the range (1 is Monday).
  } // End of the loop.
  return out; // Hands back the days.
} // End of dayList.

// Reads a whole opening hours text into weekly rows (or nothing if it can't).
export function parseOsmHours(value: string | undefined | null): WeeklyHours[] | null { // (takes the text, which may be missing)
  if (!value) return null; // No text: nothing.
  const text = value.trim(); // The text without spaces at either end.
  if (text === "24/7") return null; // Open all the time: nothing (the admin enters hours).
  const rows: WeeklyHours[] = []; // The opening times found.
  for (const rule of text.split(";").map((r) => r.trim()).filter(Boolean)) { // For each rule between semicolons (skipping blanks):
    // "PH off" and similar public holiday notes: skip; admins check holidays separately.
    if (/^PH\b/.test(rule)) continue; // skips public holiday rules,
    const m = rule.match(/^([A-Za-z,\- ]+?)\s+(off|closed|[0-9:,\- ]+)$/); // splits it into its days and its times (or "off"),
    if (!m) return null; // anything else: can't read it.
    const days = dayList(m[1].replace(/\s+/g, "")); // Reads the days (ignoring spaces),
    if (!days) return null; // days it can't read: can't read the text.
    if (m[2] === "off" || m[2] === "closed") continue; // Closed on those days: moves on.
    for (const span of m[2].split(",")) { // For each time span on those days:
      const t = span.trim().match(/^([0-2]\d):([0-5]\d)-([0-2]\d):([0-5]\d)$/); // checks it's like 09:30-17:00,
      if (!t) return null; // anything else: can't read it.
      const opens = `${t[1]}:${t[2]}`; // The opening time,
      const closes = `${t[3]}:${t[4]}`; // the closing time,
      if (closes <= opens) return null; // closing before opening: can't read it.
      for (const d of days) rows.push({ weekday: d, opens, closes }); // Adds a row for each of the days.
    } // End of the time spans.
  } // End of the rules.
  return rows.length ? rows : null; // Hands back the rows, or nothing if there were none.
} // End of parseOsmHours.
