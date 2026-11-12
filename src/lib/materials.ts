// Summary: shared lists and checks for the materials library (kinds of
// material, statuses, file size limits, accepted file types, tidy titles and
// year-level matching).
//
// Shared lists and checks for the materials library. Safe to use in the
// browser and on the server. The stamping code is in materials-stamp.ts.

// Every kind of material CLG can hold (the codes the database uses).
export const MATERIAL_KINDS = [
  "booklet", // A booklet.
  "worksheet", // A worksheet.
  "lesson_plan", // A lesson plan.
  "activity", // An activity.
  "assessment", // A test or check-in.
  "answers", // An answer sheet.
  "slides", // A slide deck.
  "reference", // A reference sheet.
  "game", // A game.
] as const; // "as const" keeps the exact codes for type checking.
export type MaterialKind = (typeof MATERIAL_KINDS)[number]; // The allowed kind codes, for type checking.

// The plain name of each kind, shown to people.
export const MATERIAL_KIND_NAMES: Record<MaterialKind, string> = {
  booklet: "Booklet", // Shown name for booklet.
  worksheet: "Worksheet", // Shown name for worksheet.
  lesson_plan: "Lesson plan", // Shown name for lesson_plan.
  activity: "Activity", // Shown name for activity.
  assessment: "Test or check-in", // Shown name for assessment.
  answers: "Answers", // Shown name for answers.
  slides: "Slides", // Shown name for slides.
  reference: "Reference sheet", // Shown name for reference.
  game: "Game", // Shown name for game.
}; // End of the kind names.

// The plain name of each material stage.
export const MATERIAL_STATUS_NAMES: Record<string, string> = {
  draft: "Draft (tutors can't see it)", // Not ready yet.
  published: "Published", // Ready and visible to tutors.
  retired: "Retired (hidden from tutors)", // No longer used.
}; // End of the stage names.

// The file tutors open must be under 4 MB, because the stamped copy is sent
// through the app's server and Vercel caps what it can send at 4.5 MB.
export const MAX_VIEW_BYTES = 4 * 1024 * 1024; // 4 MB in bytes.
// The editable original (admins only) goes straight to the file store.
export const MAX_SOURCE_BYTES = 50 * 1024 * 1024; // 50 MB in bytes.

// The file types tutors can open, by file ending.
export const VIEW_TYPES = {
  pdf: "application/pdf", // PDF files.
  jpg: "image/jpeg", // JPEG photos.
  png: "image/png", // PNG images.
} as const; // "as const" keeps these fixed.

// The file types allowed for the editable original, by file ending.
export const SOURCE_TYPES: Record<string, string> = {
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", // Word document.
  pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation", // PowerPoint slides.
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", // Excel spreadsheet.
  doc: "application/msword", // Older Word document.
  ppt: "application/vnd.ms-powerpoint", // Older PowerPoint slides.
  xls: "application/vnd.ms-excel", // Older Excel spreadsheet.
  pdf: "application/pdf", // PDF.
}; // End of the original file types.

// Works out a view file's type from its first bytes, not from its name.
export function viewFileType(bytes: Uint8Array): keyof typeof VIEW_TYPES | null {
  const starts = (...sig: number[]) => sig.every((b, i) => bytes[i] === b); // Helper: true if the file starts with exactly these bytes.
  if (starts(0x25, 0x50, 0x44, 0x46)) return "pdf"; // "%PDF" marks a PDF.
  if (starts(0xff, 0xd8, 0xff)) return "jpg"; // These bytes mark a JPEG photo.
  if (starts(0x89, 0x50, 0x4e, 0x47)) return "png"; // "‰PNG" marks a PNG image.
  return null; // Anything else isn't allowed.
} // End of viewFileType.

// A tidy title from a file name: "fraction_walls-yr5.pdf" -> "Fraction walls yr5".
export function titleFromFileName(name: string): string {
  const base = name.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim(); // Drops the file ending, turns _ and - into spaces, and tidies spaces.
  const title = base.charAt(0).toUpperCase() + base.slice(1); // Capitalises the first letter.
  return title.slice(0, 200) || "Untitled material"; // Cuts to 200 letters, or uses "Untitled material" if nothing's left.
} // End of titleFromFileName.

// A year range in words, e.g. "Year 5 to Year 7", or one year if both match.
export function yearRange(from: string, to: string): string {
  return from === to ? from : `${from} to ${to}`; // One year if the same, otherwise "from to to".
} // End of yearRange.

// Where a curriculum level ("Year 7", "Years 3 and 4", "Year 11 (Stage 1)",
// "Foundation") sits as positions in YEAR_LEVELS, or null when it can't be
// read. Same rule as private.level_band_ranks in the database.
export function bandRanks(band: string): [number, number] | null {
  const b = band.toLowerCase().replace(/\(.*\)/g, ""); // Lower case, with anything in brackets removed.
  const nums = [...b.matchAll(/\d+/g)].map((m) => Number(m[0])).filter((n) => n >= 0 && n <= 12); // Every number from 0 to 12 in the text.
  if (/^\s*(foundation|reception|prep)/.test(b)) nums.push(0); // Foundation, Reception and Prep count as 0.
  if (nums.length === 0) return null; // No numbers found: can't be read.
  return [Math.min(...nums), Math.max(...nums)]; // The lowest and highest numbers found.
} // End of bandRanks.

// Does a curriculum level include this year level (for example "Year 5")?
// Levels that can't be read are kept, so nothing is hidden by mistake.
export function bandCoversYear(band: string, yearIndex: number): boolean {
  const r = bandRanks(band); // Reads the level's range.
  return !r || (yearIndex >= r[0] && yearIndex <= r[1]); // Kept if unreadable, or if the year falls inside the range.
} // End of bandCoversYear.
