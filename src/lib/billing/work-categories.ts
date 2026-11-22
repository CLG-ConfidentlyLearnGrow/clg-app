// Summary: the kinds of paid work outside sessions that staff log on their
// My Pay page (Carla, 18 Nov 2026), with the words shown for each. The
// database keeps the same list (see 20261120800200_work_outside_sessions.sql).

// One kind of work: its saved name, its words, a short help line, and
// whether it is tutoring work (tutor rate) or office admin (admin rate).
export type WorkCategory = { id: string; label: string; help: string; type: "tutoring" | "admin" }; // (the shape of each kind)

// Every kind of work, in the order shown in the drop-down.
export const WORK_CATEGORIES: WorkCategory[] = [ // The list:
  { id: "preparation", label: "Lesson preparation and planning", help: "Planning lessons beyond the 15 minutes already paid after each session.", type: "tutoring" }, // preparation,
  { id: "materials", label: "Making learning materials", help: "Worksheets, slides, practice tasks or resources for learners.", type: "tutoring" }, // materials,
  { id: "training", label: "Training CLG set", help: "Training CLG asked you to do that is not an app training module (those are added for you).", type: "tutoring" }, // training,
  { id: "set_work", label: "Other work CLG set", help: "Other tasks CLG asked you to do, such as marking or a project.", type: "tutoring" }, // other set work,
  { id: "no_show_time", label: "Work during a no-show or late cancel", help: "What you did in the time of a session that did not go ahead. That time is already paid with the session, so this records the work and is not paid again.", type: "tutoring" }, // no-show time,
  { id: "office_admin", label: "Office admin", help: "General CLG office work, such as enquiries, rostering or invoicing. Paid at your admin rate.", type: "admin" }, // office admin.
]; // End of the list.

// The words for a saved kind of work (or nothing for older entries).
export function workCategoryLabel(id: string | null | undefined): string | undefined { // Takes the saved name.
  return WORK_CATEGORIES.find((c) => c.id === id)?.label; // Finds its words (if any).
} // End of workCategoryLabel.
