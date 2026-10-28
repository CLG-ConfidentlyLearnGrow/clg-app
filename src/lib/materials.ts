// Shared lists and checks for the materials library. Safe to use in the
// browser and on the server. The stamping code is in materials-stamp.ts.

export const MATERIAL_KINDS = [
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
