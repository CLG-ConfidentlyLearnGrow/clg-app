// Reads the Australian Curriculum v9 Excel file ("Download entire
// curriculum" from australiancurriculum.edu.au/downloads). Each subject (and
// each language pathway) becomes one curriculum, and each content
// description becomes one skill. Elaborations (examples) are left out.
// Runs in the browser, so the large file never has to be uploaded whole.

export const ACARA_SHEET = "Learning areas";
export const ACARA_VERSION = "9.0";

export type AcaraSkill = { code: string; level_band: string; description: string };
export type AcaraCurriculum = {
  key: string;
  learningArea: string;
  subject: string;
  code: string;
  name: string;
  skills: AcaraSkill[];
};

// The licence credit ACARA asks for (CC BY 4.0).
export function acaraSource(accessed: string) {
  return (
    "© Australian Curriculum, Assessment and Reporting Authority (ACARA) 2010 to present, unless otherwise indicated. " +
    `This material was downloaded from the Australian Curriculum website (accessed ${accessed}) and was not modified. ` +
    "The material is licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)."
  );
}

type Cell = unknown;

const text = (v: Cell) => (v == null ? "" : String(v)).trim();

// Content descriptions are plain text, but strip any HTML to be safe.
function plain(v: Cell) {
  return text(v)
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&rsquo;|&lsquo;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function levelName(level: string) {
  return level === "Foundation Year" ? "Foundation" : level;
}

// A short code for the curriculum, for example AC9-MATHEMATICS or
// AC9-FRENCH-7-10. Long names use their initials.
function shortCode(subject: string, pathway: string, sequence: string) {
  const part = (s: string, max: number) => {
    const words = s.replace(/[^A-Za-z0-9 -]/g, "").split(/[\s]+/).filter(Boolean);
    const joined = words.join("").toUpperCase();
    if (joined.length <= max) return joined;
    return words
      .map((w) => (/^\d/.test(w) ? w : w[0]))
      .join("")
      .toUpperCase()
      .slice(0, max);
  };
  const pieces = ["AC9", part(subject, 14)];
  if (pathway) pieces.push(part(pathway.replace(/ ?Pathway.*$/i, ""), 5));
  if (sequence) pieces.push(sequence.replace(/ ?Sequence$/i, "").replace(/[^A-Za-z0-9-]/g, ""));
  return pieces.join("-").slice(0, 30);
}

// rows: the "Learning areas" sheet, header row first.
export function parseAcara(rows: Cell[][]): AcaraCurriculum[] | { error: string } {
  const header = (rows[0] ?? []).map((h) => text(h).toLowerCase());
  const col = (name: string) => header.indexOf(name);
  const c = {
    area: col("learning area"),
    subject: col("subject"),
    level: col("level"),
    code: col("code"),
    pathway: col("pathway"),
    sequence: col("sequence"),
    content: col("content description"),
  };
  if (Object.values(c).some((i) => i < 0)) {
    return {
      error:
        "This doesn't look like ACARA's curriculum file. Use the \"Download entire curriculum\" Excel file from australiancurriculum.edu.au/downloads.",
    };
  }

  const found = new Map<string, AcaraCurriculum>();
  const usedCodes = new Set<string>();
  for (const row of rows.slice(1)) {
    const description = plain(row[c.content]);
    if (!description) continue;
    const subject = text(row[c.subject]);
    const level = text(row[c.level]);
    if (!subject || !level) continue;
    const pathway = text(row[c.pathway]);
    const sequence = text(row[c.sequence]);
    const key = [subject, pathway, sequence].join("|");

    let cur = found.get(key);
    if (!cur) {
      let code = shortCode(subject, pathway, sequence);
      for (let n = 2; usedCodes.has(code); n++) code = `${code.slice(0, 27)}-${n}`;
      usedCodes.add(code);
      const extra = [pathway, sequence].filter(Boolean).join(", ");
      const shownSubject = extra ? `${subject} (${extra})` : subject;
      cur = {
        key,
        learningArea: text(row[c.area]),
        subject: shownSubject.slice(0, 100),
        code,
        name: `Australian Curriculum v9: ${shownSubject}`.slice(0, 200),
        skills: [],
      };
      found.set(key, cur);
    }
    cur.skills.push({
      code: text(row[c.code]).slice(0, 40),
      level_band: levelName(level).slice(0, 60),
      description: description.slice(0, 2000),
    });
  }
  if (found.size === 0) return { error: "No skills were found in that file." };
  return [...found.values()];
}
