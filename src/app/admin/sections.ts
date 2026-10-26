// The admin area is split into these sections, shown one at a time.
export const ADMIN_SECTIONS = [
  { id: "families", label: "Families and matching" },
  { id: "tutors", label: "Tutors and checks" },
  { id: "curriculum", label: "Curriculum" },
  { id: "staff", label: "Staff and accounts" },
  { id: "records", label: "Privacy and records" },
] as const;

export type AdminSectionId = (typeof ADMIN_SECTIONS)[number]["id"];

export function sectionFrom(value: unknown): AdminSectionId {
  const found = ADMIN_SECTIONS.find((s) => s.id === value);
  return found ? found.id : "families";
}
