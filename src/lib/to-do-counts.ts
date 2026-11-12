// Summary: the to-do numbers shown on menus, dashboard tabs and the top bar.
//
import { cache } from "react"; // Remembers a result for the rest of one page load.
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Numbers on menus and dashboard tabs where something needs doing, e.g.
// "Matching 4" (Carla, 11 Nov 2026). The database works them all out in one
// call (to_do_counts), so the side menu, the dashboard tabs and the top bar
// always show the same numbers. See docs/features/to-do-counts.md.

export type ToDoArea = "admin" | "billing" | "privacy" | "tutor" | "parent" | "student" | "family" | "sessions"; // The areas the numbers belong to.

export type ToDoCounts = { // What the page code gets back:
  // The number for one menu item, or undefined when there's nothing to do
  // (so no number is shown).
  get: (area: ToDoArea, section: string) => number | undefined; // (a function: area and menu item in, number out)
  // The total for a dashboard tab at the top of the page.
  forRole: (role: Role) => number | undefined; // (a function: role in, number out)
  // The total for the Sessions page in the top bar.
  sessions: number | undefined; // (a number, or nothing)
}; // End of the shape.

// What adds up to each dashboard tab. Family billing belongs to the parent
// tab, or to the student tab for an adult learner who pays for themselves.
function areasFor(role: Role, roles: Role[]): ToDoArea[] { // Takes the tab's role and all of the person's roles:
  if (role === "admin") return ["admin", "billing"]; // admin tab: admin and billing numbers,
  if (role === "tutor") return ["tutor"]; // tutor tab: tutor numbers,
  if (role === "parent") return ["parent", "family"]; // parent tab: parent and family billing numbers,
  return roles.includes("parent") ? ["student"] : ["student", "family"]; // student tab: student numbers, plus family billing if they have no parent role.
} // End of areasFor.

const shown = (n: number) => (n > 0 ? n : undefined); // Hides zero (shows no number).

type Row = { area: ToDoArea; section: string; n: number }; // One row from the database: area, menu item and number.

// Loaded once per page, however many places use it.
const loadRows = cache(async (): Promise<Row[]> => { // Reads the rows (once per page):
  const supabase = await createClient(); // connects to the database,
  const { data } = await supabase.rpc("to_do_counts"); // asks for the to-do numbers,
  return (data ?? []) as Row[]; // hands back the rows.
}); // End of loadRows.

export async function getToDoCounts(roles: Role[]): Promise<ToDoCounts> { // Gets the numbers for this person's roles.
  const rows = await loadRows(); // The rows.
  const sum = (areas: ToDoArea[]) => rows.filter((r) => areas.includes(r.area)).reduce((t, r) => t + r.n, 0); // Adds up the numbers for some areas.
  return { // Hands back:
    get: (area, section) => shown(rows.find((r) => r.area === area && r.section === section)?.n ?? 0), // one menu item's number,
    forRole: (role) => shown(sum(areasFor(role, roles))), // a dashboard tab's total,
    sessions: shown(sum(["sessions"])), // and the Sessions total.
  }; // (end)
} // End of getToDoCounts.
