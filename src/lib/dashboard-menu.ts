// Summary: the side menu for each dashboard (admin, tutor, parent, student).
// Every page that belongs to a dashboard shows the same menu, so Sessions,
// Matching, Billing, Teams links, Materials and My pay sit with the other
// tabs instead of in the top bar or a line of links (Carla, 12 Nov 2026).
//
import type { Section } from "@/components/section-shell"; // The shape of one menu item (for type checking only).
import { ADMIN_SECTIONS } from "@/app/admin/sections"; // The admin page's own sections.
import { FINANCE, FRONT_DESK, FULL_ADMIN, getAdminLevel, type Role } from "@/lib/auth"; // Admin level groups, the level reader, and the role type.
import { getToDoCounts } from "@/lib/to-do-counts"; // Reads the to-do numbers.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person (for the problem reports number).

// Whether this admin checks problem reports (the owner, or on the reviewer
// list), and how many new reports are waiting. Gives back null for anyone
// else, so they don't see the tab.
async function problemReportsTab(isOwner: boolean, accountId: string): Promise<{ count?: number } | null> { // Takes whether they're the owner, and their id.
  const supabase = await createClient(); // Connects to the database.
  if (!isOwner) { // Not the owner:
    const { count } = await supabase.from("problem_reviewers").select("account_id", { count: "exact", head: true }).eq("account_id", accountId); // checks they're on the list (only reviewers can read it),
    if (!count) return null; // not on it: no tab.
  } // End of the list check.
  const { count } = await supabase.from("problem_reports").select("id", { count: "exact", head: true }).eq("status", "new"); // Counts new reports.
  return { count: count || undefined }; // Hands back the number (none when zero).
} // End of problemReportsTab.

// The tutor dashboard's own sections (the page reads these to know which is open).
export const TUTOR_SECTIONS = [ // Each section's id and its name on screen:
  { id: "students", label: "Your students" }, // their students,
  { id: "teaching", label: "What you teach" }, // what they teach,
  { id: "checks", label: "Child safety checks" }, // their checks,
  { id: "hours", label: "Hours and availability" }, // hours and availability.
] as const; // End of the list (fixed, so the ids are known exactly).

// The parent dashboard's own sections.
export const PARENT_SECTIONS = [ // Each section's id and its name on screen:
  { id: "children", label: "Your children" }, // the children list,
  { id: "add", label: "Add a child" }, // the add-a-child form.
] as const; // End of the list.

// The student dashboard's own section.
export const STUDENT_SECTIONS = [{ id: "learning", label: "Your learning" }] as const; // Just "Your learning".

// The address of a dashboard's Sessions tab, e.g. "/schedule?as=tutor".
// "as" tells the Sessions page which dashboard it belongs to, so a person
// who is both an admin and a tutor sees the right sessions in each.
export function sessionsHref(role: Role, section?: string) { // Takes the dashboard and, optionally, a Sessions section.
  return `/schedule?as=${role}${section ? `&section=${section}` : ""}`; // Builds the address (with the section when given).
} // End of sessionsHref.

// Whether a person can see Sessions in a dashboard. Every tutor, parent and
// student can; for admins, only the front desk (owner, operations, support),
// because finance admins work in Billing.
export async function hasSessions(role: Role): Promise<boolean> { // Takes the dashboard.
  if (role !== "admin") return true; // Tutors, parents and students: yes.
  const level = await getAdminLevel(); // The admin's level.
  return level !== null && FRONT_DESK.includes(level); // Front-desk admins: yes; others: no.
} // End of hasSessions.

// Builds one dashboard's side menu, with to-do numbers. Each item knows its
// own address, so the menu works the same on every page that shows it.
export async function getDashboardMenu(role: Role, roles: Role[]): Promise<Section[]> { // Takes the dashboard and all of the person's roles.
  const todo = await getToDoCounts(roles); // The to-do numbers.
  const sessions: Section[] = (await hasSessions(role)) // The Sessions tab, if this dashboard has one:
    ? [{ id: "sessions", label: "Sessions", href: sessionsHref(role), count: todo.sessionsFor(role) }] // its words, address and number,
    : []; // otherwise nothing.

  if (role === "admin") { // The admin menu:
    const level = await getAdminLevel(); // the admin's level,
    const isFull = level !== null && FULL_ADMIN.includes(level); // whether they're a full admin (owner or operations),
    const isDesk = level !== null && FRONT_DESK.includes(level); // whether they're front desk (full admins and support),
    const isFinance = level !== null && FINANCE.includes(level); // whether they can see billing,
    const own = isFull // the admin page's sections this admin sees:
      ? [...ADMIN_SECTIONS] // all of them for full admins,
      : isDesk // for support admins,
        ? ADMIN_SECTIONS.filter((s) => s.id === "families" || s.id === "matching") // just families and matching,
        : []; // and none for finance admins (they work in Billing).
    const items: Section[] = own.map((s) => ({ // each of those sections:
      id: s.id, // its id,
      label: s.label, // its words,
      href: s.id === "matching" ? "/matching" : `/admin?section=${s.id}`, // its address (Matching has its own page),
      count: todo.get("admin", s.id), // and its number.
    })); // End of the admin sections.
    items.splice(Math.min(1, items.length), 0, ...sessions); // Sessions goes second, after Families (one of an admin's main jobs).
    const billingToDo = ["families", "invoices", "pay"].reduce((t, id) => t + (todo.get("billing", id) ?? 0), 0); // Billing's total: families, invoices and pay.
    if (isFinance) items.push({ id: "billing", label: "Billing", href: "/admin/billing", count: billingToDo || undefined }); // Billing (owner, operations and finance),
    if (level === "owner") items.push({ id: "reports", label: "Reports", href: "/admin/reports", count: todo.get("admin", "reports") }); // Reports (owner only, because they include pay and profit), with new reports counted,
    const { data: me } = await (await createClient()).auth.getUser(); // Who is signed in (for the reviewer list check).
    const problems = me.user ? await problemReportsTab(level === "owner", me.user.id) : null; // The problem reports tab, if they check reports.
    if (problems) items.push({ id: "problems", label: "Problem reports", href: "/admin/problems", count: problems.count }); // Problem reports (owner and chosen reviewers), with new reports counted,
    if (isFull) items.push({ id: "teams", label: "Teams links", href: "/admin/teams" }); // Teams links for online sessions (full admins),
    if (isFull) items.push({ id: "materials", label: "Materials library", href: "/admin/materials" }); // the materials library (full admins),
    items.push({ id: "pay", label: "My pay", href: "/pay?as=admin" }); // and their own pay (office admin hours).
    return items; // Hands back the admin menu.
  } // End of the admin menu.

  if (role === "tutor") { // The tutor menu:
    const [first, ...rest] = TUTOR_SECTIONS.map((s) => ({ ...s, href: `/dashboard/tutor?section=${s.id}`, count: todo.get("tutor", s.id) })); // their sections, each with its address and number,
    return [ // hands back:
      first, // Your students,
      ...sessions, // Sessions,
      { id: "calendar", label: "Weekly calendar", href: "/dashboard/tutor/calendar" }, // their week at a glance, and the link for their own calendar (Carla, 12 Nov 2026),
      ...rest, // the other tutor sections,
      { id: "materials", label: "CLG materials", href: "/materials" }, // CLG materials,
      { id: "pay", label: "My pay", href: "/pay?as=tutor" }, // and their pay.
    ]; // End of the tutor menu.
  } // End of the tutor menu.

  if (role === "parent") { // The parent menu:
    return [ // hands back:
      { id: "children", label: "Your children", href: "/dashboard/parent?section=children", count: todo.get("parent", "children") }, // Your children (with details to finish),
      ...sessions, // Sessions,
      { id: "add", label: "Add a child", href: "/dashboard/parent?section=add" }, // Add a child,
      { id: "billing", label: "Billing", href: "/billing", count: todo.get("family", "billing") }, // and Billing (with anything to set up).
    ]; // End of the parent menu.
  } // End of the parent menu.

  // The student menu. Billing shows for an adult learner who pays for
  // themselves; someone who is also a parent sees Billing on the parent menu.
  return [ // Hands back:
    { id: "learning", label: "Your learning", href: "/dashboard/student", count: todo.get("student", "learning") }, // Your learning (with steps overdue),
    ...sessions, // Sessions,
    ...(roles.includes("parent") ? [] : [{ id: "billing", label: "Billing", href: "/billing", count: todo.get("family", "billing") }]), // and Billing (unless they're also a parent).
  ]; // End of the student menu.
} // End of getDashboardMenu.
