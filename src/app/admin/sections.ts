// Summary: the list of admin sections, and a helper to pick one safely.
//
// The admin area is split into these sections, shown one at a time.
export const ADMIN_SECTIONS = [ // Each section's id and its name on screen:
  { id: "families", label: "Families" }, // families,
  { id: "matching", label: "Matching" }, // matching,
  { id: "tutors", label: "Tutors and checks" }, // tutors and checks,
  { id: "progress", label: "Progress" }, // progress,
  { id: "curriculum", label: "Curriculum" }, // curriculum,
  { id: "staff", label: "Staff and accounts" }, // staff and accounts,
  { id: "leaving", label: "Leaving" }, // leaving,
  { id: "records", label: "Privacy and records" }, // privacy and records.
] as const; // End of the list (fixed, so the ids are known exactly).

export type AdminSectionId = (typeof ADMIN_SECTIONS)[number]["id"]; // The type for a section id.

// Gives back the section asked for, or "families" if it isn't known.
export function sectionFrom(value: unknown): AdminSectionId {
  const found = ADMIN_SECTIONS.find((s) => s.id === value); // Looks for a section with that id.
  return found ? found.id : "families"; // Found: its id; otherwise families.
} // End of sectionFrom.
