// Summary: reads a curriculum from a spreadsheet (Excel or CSV) in CLG's own
// simple layout, so any curriculum can be loaded: SACE for Years 11 and 12,
// other states, or other countries. One row per skill. The first row names
// the columns; see public/templates/curriculum-template.csv.

// The shape of one skill read from the file.
export type FileSkill = {
  code: string; // The skill's code (may be blank).
  subject: string; // The subject it belongs to.
  level_band: string; // The year or level it's for.
  description: string; // The official wording.
  plain_description: string; // Plain wording for parents (may be blank).
}; // End of the skill shape.

// One spreadsheet cell, which could hold anything (text, number, date, blank).
type Cell = unknown;
// Turns a cell into tidy text: blank for empty cells, single spaces, no spaces at the ends.
const text = (v: Cell) => (v == null ? "" : String(v)).replace(/\s+/g, " ").trim();

// Accepted column names (lower case), so small wording differences still work.
const COLUMNS = {
  code: ["code", "skill code"], // Names accepted for the code column.
  subject: ["subject"], // Names accepted for the subject column.
  level: ["year or level", "year", "level", "year level", "stage"], // Names accepted for the level column.
  description: ["skill", "official wording", "wording", "description", "content description"], // Names accepted for the skill column.
  plain: ["plain wording", "plain wording for parents", "plain description"], // Names accepted for the plain wording column.
} as const; // "as const" keeps these lists fixed.

// Turns the spreadsheet's rows into a list of skills, or a plain error message.
export function parseCurriculumRows(rows: Cell[][]): FileSkill[] | { error: string } {
  const header = (rows[0] ?? []).map((h) => text(h).toLowerCase()); // The first row's column names, in lower case.
  const find = (names: readonly string[]) => header.findIndex((h) => names.includes(h)); // Finds which column has one of these names (-1 if none).
  const c = { // The position of each column we need:
    code: find(COLUMNS.code), // the code column,
    subject: find(COLUMNS.subject), // the subject column,
    level: find(COLUMNS.level), // the level column,
    description: find(COLUMNS.description), // the skill column,
    plain: find(COLUMNS.plain), // and the plain wording column.
  }; // End of the column positions.
  if (c.subject < 0 || c.level < 0 || c.description < 0) { // A must-have column is missing:
    return { // Hands back a plain explanation.
      error: // The message:
        'The first row must name the columns, including "Subject", "Year or level" and "Skill". Download the template to see the layout.',
    }; // End of the error.
  } // End of the missing-column check.

  const skills: FileSkill[] = []; // The skills found so far.
  for (const [i, row] of rows.slice(1).entries()) { // Goes through every row after the heading row (i counts from 0).
    const description = text(row[c.description]); // The skill wording in this row.
    const subject = text(row[c.subject]); // The subject in this row.
    const level = text(row[c.level]); // The level in this row.
    if (!description && !subject && !level) continue; // blank row, so it's skipped.
    if (!description || !subject || !level) { // Part-filled row:
      return { error: `Row ${i + 2} needs a subject, a year or level, and the skill.` }; // Names the spreadsheet row number to fix.
    } // End of the part-filled check.
    skills.push({ // Adds this row's skill, trimmed to safe lengths:
      code: c.code >= 0 ? text(row[c.code]).slice(0, 40) : "", // code up to 40 letters (blank if no code column),
      subject: subject.slice(0, 100), // subject up to 100 letters,
      level_band: level.slice(0, 60), // level up to 60 letters,
      description: description.slice(0, 2000), // wording up to 2,000 letters,
      plain_description: c.plain >= 0 ? text(row[c.plain]).slice(0, 500) : "", // plain wording up to 500 letters.
    }); // End of this skill.
  } // End of the loop over rows.
  if (skills.length === 0) return { error: "No skills were found in that file." }; // Empty file.
  return skills; // Hands back every skill found.
} // End of parseCurriculumRows.
