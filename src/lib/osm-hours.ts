// Reads simple OpenStreetMap opening hours, such as
// "Mo-Fr 09:30-17:00; Sa 10:00-13:00; Su off", into weekly rows
// (weekday 1 = Monday). Anything more complicated (public holiday rules,
// months, week numbers) returns null, and the admin enters the hours by hand.

export type WeeklyHours = { weekday: number; opens: string; closes: string };

const DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];

function dayList(part: string): number[] | null {
  const out: number[] = [];
  for (const piece of part.split(",")) {
    const range = piece.trim().match(/^(Mo|Tu|We|Th|Fr|Sa|Su)(?:-(Mo|Tu|We|Th|Fr|Sa|Su))?$/);
    if (!range) return null;
    const from = DAYS.indexOf(range[1]);
    const to = range[2] ? DAYS.indexOf(range[2]) : from;
    if (to < from) return null;
    for (let d = from; d <= to; d++) out.push(d + 1);
  }
  return out;
}

export function parseOsmHours(value: string | undefined | null): WeeklyHours[] | null {
  if (!value) return null;
  const text = value.trim();
  if (text === "24/7") return null;
  const rows: WeeklyHours[] = [];
  for (const rule of text.split(";").map((r) => r.trim()).filter(Boolean)) {
    // "PH off" and similar public holiday notes: skip; admins check holidays separately.
    if (/^PH\b/.test(rule)) continue;
    const m = rule.match(/^([A-Za-z,\- ]+?)\s+(off|closed|[0-9:,\- ]+)$/);
    if (!m) return null;
    const days = dayList(m[1].replace(/\s+/g, ""));
    if (!days) return null;
    if (m[2] === "off" || m[2] === "closed") continue;
    for (const span of m[2].split(",")) {
      const t = span.trim().match(/^([0-2]\d):([0-5]\d)-([0-2]\d):([0-5]\d)$/);
      if (!t) return null;
      const opens = `${t[1]}:${t[2]}`;
      const closes = `${t[3]}:${t[4]}`;
      if (closes <= opens) return null;
      for (const d of days) rows.push({ weekday: d, opens, closes });
    }
  }
  return rows.length ? rows : null;
}
