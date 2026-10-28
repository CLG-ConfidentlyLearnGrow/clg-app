// Shared lists and checks for the materials library. Safe to use in the
// browser and on the server. The stamping code is in materials-stamp.ts.

export const MATERIAL_KINDS = [
  "booklet",
  "worksheet",
  "lesson_plan",
  "activity",
  "assessment",
  "answers",
  "slides",
  "reference",
  "game",
] as const;
export type MaterialKind = (typeof MATERIAL_KINDS)[number];

export const MATERIAL_KIND_NAMES: Record<MaterialKind, string> = {
  booklet: "Booklet",
  worksheet: "Worksheet",
  lesson_plan: "Lesson plan",
  activity: "Activity",
  assessment: "Test or check-in",
  answers: "Answers",
  slides: "Slides",
  reference: "Reference sheet",
  game: "Game",
};

export const MATERIAL_STATUS_NAMES: Record<string, string> = {
  draft: "Draft (tutors can't see it)",
  published: "Published",
  retired: "Retired (hidden from tutors)",
};

// The file tutors open must be under 4 MB, because the stamped copy is sent
// through the app's server and Vercel caps what it can send at 4.5 MB.
export const MAX_VIEW_BYTES = 4 * 1024 * 1024;
// The editable original (admins only) goes straight to the file store.
export const MAX_SOURCE_BYTES = 50 * 1024 * 1024;

export const VIEW_TYPES = {
  pdf: "application/pdf",
  jpg: "image/jpeg",
  png: "image/png",
} as const;

export const SOURCE_TYPES: Record<string, string> = {
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  doc: "application/msword",
  ppt: "application/vnd.ms-powerpoint",
  xls: "application/vnd.ms-excel",
  pdf: "application/pdf",
};

// Works out a view file's type from its first bytes, not from its name.
export function viewFileType(bytes: Uint8Array): keyof typeof VIEW_TYPES | null {
  const starts = (...sig: number[]) => sig.every((b, i) => bytes[i] === b);
  if (starts(0x25, 0x50, 0x44, 0x46)) return "pdf";
  if (starts(0xff, 0xd8, 0xff)) return "jpg";
  if (starts(0x89, 0x50, 0x4e, 0x47)) return "png";
  return null;
}

// A tidy title from a file name: "fraction_walls-yr5.pdf" -> "Fraction walls yr5".
export function titleFromFileName(name: string): string {
  const base = name.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim();
  const title = base.charAt(0).toUpperCase() + base.slice(1);
  return title.slice(0, 200) || "Untitled material";
}

export function yearRange(from: string, to: string): string {
  return from === to ? from : `${from} to ${to}`;
}

// Where a curriculum level ("Year 7", "Years 3 and 4", "Year 11 (Stage 1)",
// "Foundation") sits as positions in YEAR_LEVELS, or null when it can't be
// read. Same rule as private.level_band_ranks in the database.
export function bandRanks(band: string): [number, number] | null {
  const b = band.toLowerCase().replace(/\(.*\)/g, "");
  const nums = [...b.matchAll(/\d+/g)].map((m) => Number(m[0])).filter((n) => n >= 0 && n <= 12);
  if (/^\s*(foundation|reception|prep)/.test(b)) nums.push(0);
  if (nums.length === 0) return null;
  return [Math.min(...nums), Math.max(...nums)];
}

// Does a curriculum level include this year level (for example "Year 5")?
// Levels that can't be read are kept, so nothing is hidden by mistake.
export function bandCoversYear(band: string, yearIndex: number): boolean {
  const r = bandRanks(band);
  return !r || (yearIndex >= r[0] && yearIndex <= r[1]);
}
