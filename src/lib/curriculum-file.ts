// Reads a curriculum from a spreadsheet (Excel or CSV) in CLG's own simple
// layout, so any curriculum can be loaded: SACE for Years 11 and 12, other
// states, or other countries. One row per skill. The first row names the
// columns; see public/templates/curriculum-template.csv.

export type FileSkill = {
  code: string;
  subject: string;
  level_band: string;
  description: string;
  plain_description: string;
};

type Cell = unknown;
const text = (v: Cell) => (v == null ? "" : String(v)).replace(/\s+/g, " ").trim();

// Accepted column names (lower case), so small wording differences still work.
const COLUMNS = {
  code: ["code", "skill code"],
  subject: ["subject"],
  level: ["year or level", "year", "level", "year level", "stage"],
  description: ["skill", "official wording", "wording", "description", "content description"],
  plain: ["plain wording", "plain wording for parents", "plain description"],
} as const;

export function parseCurriculumRows(rows: Cell[][]): FileSkill[] | { error: string } {
  const header = (rows[0] ?? []).map((h) => text(h).toLowerCase());
  const find = (names: readonly string[]) => header.findIndex((h) => names.includes(h));
  const c = {
    code: find(COLUMNS.code),
    subject: find(COLUMNS.subject),
    level: find(COLUMNS.level),
    description: find(COLUMNS.description),
    plain: find(COLUMNS.plain),
  };
  if (c.subject < 0 || c.level < 0 || c.description < 0) {
    return {
      error:
        'The first row must name the columns, including "Subject", "Year or level" and "Skill". Download the template to see the layout.',
    };
  }

  const skills: FileSkill[] = [];
  for (const [i, row] of rows.slice(1).entries()) {
    const description = text(row[c.description]);
    const subject = text(row[c.subject]);
    const level = text(row[c.level]);
    if (!description && !subject && !level) continue; // blank row
    if (!description || !subject || !level) {
      return { error: `Row ${i + 2} needs a subject, a year or level, and the skill.` };
    }
    skills.push({
      code: c.code >= 0 ? text(row[c.code]).slice(0, 40) : "",
      subject: subject.slice(0, 100),
      level_band: level.slice(0, 60),
      description: description.slice(0, 2000),
      plain_description: c.plain >= 0 ? text(row[c.plain]).slice(0, 500) : "",
    });
  }
  if (skills.length === 0) return { error: "No skills were found in that file." };
  return skills;
}
