// Summary: reads ACARA's Australian Curriculum v9 spreadsheet into
// curriculums and skills the app can load.
//
// Reads the Australian Curriculum v9 Excel file ("Download entire
// curriculum" from australiancurriculum.edu.au/downloads). Each subject (and
// each language pathway) becomes one curriculum, and each content
// description becomes one skill. Elaborations (examples) are left out.
// Runs in the browser, so the large file never has to be uploaded whole.

export const ACARA_SHEET = "Learning areas"; // The sheet in ACARA's file that holds the content.
export const ACARA_VERSION = "9.0"; // The curriculum version loaded.

export type AcaraSkill = { code: string; level_band: string; description: string }; // One skill: its code, year or level, and wording.
// One curriculum found in the file.
export type AcaraCurriculum = {
  key: string; // A unique key (subject, pathway and sequence).
  learningArea: string; // ACARA's learning area, e.g. "Mathematics".
  subject: string; // The subject name shown in the app.
  code: string; // A short code, e.g. AC9-MATHEMATICS.
  name: string; // The full name shown in the app.
  skills: AcaraSkill[]; // Its skills.
}; // End of the curriculum shape.

// The licence credit ACARA asks for (CC BY 4.0).
export function acaraSource(accessed: string) {
  return ( // Builds the credit text:
    "© Australian Curriculum, Assessment and Reporting Authority (ACARA) 2010 to present, unless otherwise indicated. " + // the copyright line,
    `This material was downloaded from the Australian Curriculum website (accessed ${accessed}) and was not modified. ` + // where and when it was downloaded,
    "The material is licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)." // and the licence.
  ); // End of the text.
} // End of acaraSource.

type Cell = unknown; // One spreadsheet cell (could be anything).

const text = (v: Cell) => (v == null ? "" : String(v)).trim(); // Turns a cell into text without spaces at the ends (blank if empty).

// Content descriptions are plain text, but strip any HTML to be safe.
function plain(v: Cell) {
  return text(v) // Starting from the cell's text,
    .replace(/<[^>]*>/g, " ") // removes any HTML tags,
    .replace(/&nbsp;/g, " ") // turns non-breaking spaces into spaces,
    .replace(/&amp;/g, "&") // turns &amp; back into &,
    .replace(/&lt;/g, "<") // turns &lt; back into <,
    .replace(/&gt;/g, ">") // turns &gt; back into >,
    .replace(/&quot;/g, '"') // turns &quot; back into ",
    .replace(/&#39;|&rsquo;|&lsquo;/g, "'") // turns apostrophe codes back into ',
    .replace(/\s+/g, " ") // collapses runs of spaces,
    .trim(); // and trims the ends.
} // End of plain.

// ACARA's level name as shown in the app.
function levelName(level: string) {
  return level === "Foundation Year" ? "Foundation" : level; // "Foundation Year" becomes "Foundation"; other names stay.
} // End of levelName.

// A short code for the curriculum, for example AC9-MATHEMATICS or
// AC9-FRENCH-7-10. Long names use their initials.
function shortCode(subject: string, pathway: string, sequence: string) {
  const part = (s: string, max: number) => { // Shortens one part of the name to at most "max" letters:
    const words = s.replace(/[^A-Za-z0-9 -]/g, "").split(/[\s]+/).filter(Boolean); // splits it into words (letters, numbers and dashes only),
    const joined = words.join("").toUpperCase(); // joins them in capitals,
    if (joined.length <= max) return joined; // uses that if it fits,
    return words // otherwise uses initials:
      .map((w) => (/^\d/.test(w) ? w : w[0])) // the first letter of each word (numbers kept whole),
      .join("") // joined,
      .toUpperCase() // in capitals,
      .slice(0, max); // cut to fit.
  }; // End of the part helper.
  const pieces = ["AC9", part(subject, 14)]; // Starts with "AC9" and the subject.
  if (pathway) pieces.push(part(pathway.replace(/ ?Pathway.*$/i, ""), 5)); // Adds the language pathway, if any.
  if (sequence) pieces.push(sequence.replace(/ ?Sequence$/i, "").replace(/[^A-Za-z0-9-]/g, "")); // Adds the year sequence, if any.
  return pieces.join("-").slice(0, 30); // Joins with dashes, at most 30 letters.
} // End of shortCode.

// rows: the "Learning areas" sheet, header row first.
export function parseAcara(rows: Cell[][]): AcaraCurriculum[] | { error: string } {
  const header = (rows[0] ?? []).map((h) => text(h).toLowerCase()); // The heading row, in lower case.
  const col = (name: string) => header.indexOf(name); // Finds a column by its heading.
  const c = { // The position of each column needed:
    area: col("learning area"), // learning area,
    subject: col("subject"), // subject,
    level: col("level"), // level,
    code: col("code"), // skill code,
    pathway: col("pathway"), // language pathway,
    sequence: col("sequence"), // year sequence,
    content: col("content description"), // and content description.
  }; // End of the columns.
  if (Object.values(c).some((i) => i < 0)) { // Any column missing:
    return { // hands back a plain message.
      error: // The message:
        "This doesn't look like ACARA's curriculum file. Use the \"Download entire curriculum\" Excel file from australiancurriculum.edu.au/downloads.",
    }; // End of the message.
  } // End of the missing-column check.

  const found = new Map<string, AcaraCurriculum>(); // Curriculums found, by key.
  const usedCodes = new Set<string>(); // Short codes already used, to keep them unique.
  for (const row of rows.slice(1)) { // Goes through every row after the heading.
    const description = plain(row[c.content]); // The skill wording.
    if (!description) continue; // Blank: skips the row.
    const subject = text(row[c.subject]); // The subject.
    const level = text(row[c.level]); // The level.
    if (!subject || !level) continue; // Either missing: skips the row.
    const pathway = text(row[c.pathway]); // The language pathway (if any).
    const sequence = text(row[c.sequence]); // The year sequence (if any).
    const key = [subject, pathway, sequence].join("|"); // The curriculum this row belongs to.

    let cur = found.get(key); // Looks it up.
    if (!cur) { // Not seen yet: makes it.
      let code = shortCode(subject, pathway, sequence); // Its short code.
      for (let n = 2; usedCodes.has(code); n++) code = `${code.slice(0, 27)}-${n}`; // If the code is taken, adds -2, -3 and so on until free.
      usedCodes.add(code); // Marks the code as used.
      const extra = [pathway, sequence].filter(Boolean).join(", "); // Pathway and sequence, joined by a comma.
      const shownSubject = extra ? `${subject} (${extra})` : subject; // The subject name, with those in brackets if present.
      cur = { // The new curriculum:
        key, // its key,
        learningArea: text(row[c.area]), // its learning area,
        subject: shownSubject.slice(0, 100), // its shown subject (up to 100 letters),
        code, // its short code,
        name: `Australian Curriculum v9: ${shownSubject}`.slice(0, 200), // its full name (up to 200 letters),
        skills: [], // and no skills yet.
      }; // End of the new curriculum.
      found.set(key, cur); // Remembers it.
    } // End of making it.
    cur.skills.push({ // Adds this row's skill:
      code: text(row[c.code]).slice(0, 40), // its code (up to 40 letters),
      level_band: levelName(level).slice(0, 60), // its level (up to 60 letters),
      description: description.slice(0, 2000), // its wording (up to 2,000 letters).
    }); // End of the skill.
  } // End of the rows loop.
  if (found.size === 0) return { error: "No skills were found in that file." }; // Nothing found: plain message.
  return [...found.values()]; // Hands back every curriculum found.
} // End of parseAcara.
