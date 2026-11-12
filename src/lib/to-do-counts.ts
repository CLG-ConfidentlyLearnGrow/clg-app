import { cache } from "react";
import type { Role } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

// Numbers on menus and dashboard tabs where something needs doing, e.g.
// "Matching 4" (Carla, 11 Nov 2026). The database works them all out in one
// call (to_do_counts), so the side menu, the dashboard tabs and the top bar
// always show the same numbers. See docs/features/to-do-counts.md.

export type ToDoArea = "admin" | "billing" | "privacy" | "tutor" | "parent" | "student" | "family" | "sessions";

export type ToDoCounts = {
  // The number for one menu item, or undefined when there's nothing to do
  // (so no number is shown).
  get: (area: ToDoArea, section: string) => number | undefined;
  // The total for a dashboard tab at the top of the page.
  forRole: (role: Role) => number | undefined;
  // The total for the Sessions page in the top bar.
  sessions: number | undefined;
};

// What adds up to each dashboard tab. Family billing belongs to the parent
// tab, or to the student tab for an adult learner who pays for themselves.
function areasFor(role: Role, roles: Role[]): ToDoArea[] {
  if (role === "admin") return ["admin", "billing"];
  if (role === "tutor") return ["tutor"];
  if (role === "parent") return ["parent", "family"];
  return roles.includes("parent") ? ["student"] : ["student", "family"];
}

const shown = (n: number) => (n > 0 ? n : undefined);

type Row = { area: ToDoArea; section: string; n: number };

// Loaded once per page, however many places use it.
const loadRows = cache(async (): Promise<Row[]> => {
  const supabase = await createClient();
  const { data } = await supabase.rpc("to_do_counts");
  return (data ?? []) as Row[];
});

export async function getToDoCounts(roles: Role[]): Promise<ToDoCounts> {
  const rows = await loadRows();
  const sum = (areas: ToDoArea[]) => rows.filter((r) => areas.includes(r.area)).reduce((t, r) => t + r.n, 0);
  return {
    get: (area, section) => shown(rows.find((r) => r.area === area && r.section === section)?.n ?? 0),
    forRole: (role) => shown(sum(areasFor(role, roles))),
    sessions: shown(sum(["sessions"])),
  };
}
