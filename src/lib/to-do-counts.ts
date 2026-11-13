// Summary: the to-do numbers shown on the side menus and the dashboard tabs.
//
import { cache } from "react"; // Remembers a result for the rest of one page load.
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { ROLE_ORDER } from "@/lib/roles"; // The order of the dashboards (for which one gets shared numbers).

// Numbers on menus and dashboard tabs where something needs doing, e.g.
// "Matching 4" (Carla, 11 Nov 2026). The database works them all out in one
// call (to_do_counts), so the side menus and the dashboard tabs
// always show the same numbers. See docs/features/to-do-counts.md.

export type ToDoArea = "admin" | "billing" | "privacy" | "tutor" | "parent" | "student" | "family" | "sessions" | "safety"; // The areas the numbers belong to ("safety" is new child safety concerns, shown in the top bar).

export type ToDoCounts = { // What the page code gets back:
  // The number for one menu item, or undefined when there's nothing to do
  // (so no number is shown).
  get: (area: ToDoArea, section: string) => number | undefined; // (a function: area and menu item in, number out)
  // The total for a dashboard tab at the top of the page (its own sections
  // plus its Sessions tab).
  forRole: (role: Role) => number | undefined; // (a function: role in, number out)
  // The number on one dashboard's Sessions tab in the side menu.
  sessionsFor: (role: Role) => number | undefined; // (a function: role in, number out)
}; // End of the shape.

// What adds up to each dashboard tab. Family billing belongs to the parent
// tab, or to the student tab for an adult learner who pays for themselves.
function areasFor(role: Role, roles: Role[]): ToDoArea[] { // Takes the tab's role and all of the person's roles:
  if (role === "admin") return ["admin", "billing"]; // admin tab: admin and billing numbers,
  if (role === "tutor") return ["tutor"]; // tutor tab: tutor numbers,
  if (role === "parent") return ["parent", "family"]; // parent tab: parent and family billing numbers,
  return roles.includes("parent") ? ["student"] : ["student", "family"]; // student tab: student numbers, plus family billing if they have no parent role.
} // End of areasFor.

// Which Sessions numbers belong on each dashboard's Sessions tab (Carla,
// 12 Nov 2026: Sessions moved from the top bar into each dashboard). Each
// number is counted on one dashboard only, so the tab totals never count the
// same job twice:
// - requests and offers to answer: the tutor tab for a tutor, otherwise the
//   parent tab (or student tab for an adult learner with no parent role);
// - unread notices: the person's first dashboard (admin, tutor, parent, student);
// - next term and how long to book: the admin tab for an admin, otherwise the
//   parent tab (or student tab);
// - libraries to check: the admin tab.
function sessionSectionsFor(role: Role, roles: Role[]): string[] { // Takes the tab's role and all of the person's roles:
  const isFamily = role === "parent" || (role === "student" && !roles.includes("parent")); // true for the family tab that gets family numbers,
  const first = ROLE_ORDER.find((r) => roles.includes(r)); // the person's first dashboard (for notices),
  const out: string[] = []; // the list being built.
  if (role === "tutor" || (isFamily && !roles.includes("tutor"))) out.push("bookings"); // requests and offers to answer,
  if (role === first) out.push("notices"); // unread notices,
  if (role === "admin" || (isFamily && !roles.includes("admin"))) out.push("next-term", "booking-length"); // next term and how long to book,
  if (role === "admin") out.push("libraries"); // libraries to check.
  return out; // Hands back the list.
} // End of sessionSectionsFor.

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
  const sessionsSum = (role: Role) => { // Adds up the Sessions numbers that belong on one dashboard:
    const mine = sessionSectionsFor(role, roles); // the Sessions menu items counted on this dashboard,
    return rows.filter((r) => r.area === "sessions" && mine.includes(r.section)).reduce((t, r) => t + r.n, 0); // their numbers added up.
  }; // End of sessionsSum.
  return { // Hands back:
    get: (area, section) => shown(rows.find((r) => r.area === area && r.section === section)?.n ?? 0), // one menu item's number,
    forRole: (role) => shown(sum(areasFor(role, roles)) + sessionsSum(role)), // a dashboard tab's total (its sections plus its Sessions tab),
    sessionsFor: (role) => shown(sessionsSum(role)), // and one dashboard's Sessions number.
  }; // (end)
} // End of getToDoCounts.
