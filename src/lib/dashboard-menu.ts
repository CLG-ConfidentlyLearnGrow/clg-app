// Summary: the side menu for each dashboard (admin, tutor, parent, student).
// Every page that belongs to a dashboard shows the same menu, so Sessions,
// Matching, Billing, Teams links, Materials and My pay sit with the other
// tabs instead of in the top bar or a line of links (Carla, 12 Nov 2026).
//
import { cache } from "react"; // Remembers a result for the rest of one page load.
import type { Section } from "@/components/section-shell"; // The shape of one menu item (for type checking only).
import { ADMIN_SECTIONS } from "@/app/admin/sections"; // The admin page's own sections.
import { FINANCE, FRONT_DESK, FULL_ADMIN, getAdminLevel, type Role } from "@/lib/auth"; // Admin level groups, the level reader, and the role type.
import { getToDoCounts } from "@/lib/to-do-counts"; // Reads the to-do numbers.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person (for the problem reports number).
import { BILLING_TABS, MATERIALS_TABS, PRIVACY_TABS, REPORTS_TABS, TEAMS_TABS, TRAINING_SETUP_TABS, problemTabs, sessionTabs } from "@/lib/menu-sub-tabs"; // The sub-tabs under some headings, so the menu can open them from any page (Carla, 20 Nov 2026).

// Turns a fixed list of sub-tabs into menu items with their addresses, e.g.
// Billing's "Invoices" becomes a link to /admin/billing?section=invoices.
// "count" gives a sub-tab its number, where one is known without extra
// database reads (otherwise no number).
function subTabs(list: readonly { id: string; label: string }[], path: string, count?: (id: string) => number | undefined): Section[] { // Takes the list, the page's address, and the optional number reader.
  return list.map((t) => ({ id: t.id, label: t.label, href: `${path}?section=${t.id}`, count: count?.(t.id) })); // Each sub-tab with its address and number.
} // End of subTabs.

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

// How many training modules the signed-in person needs to do now
// (compulsory and not done, overdue, or due to redo soon). Shown on the
// Training tab. None (or a problem reading it) shows no number.
async function trainingToDo(): Promise<number | undefined> { // No inputs: it's for the signed-in person.
  const { data } = await (await createClient()).rpc("training_my_modules"); // Their modules and where they're up to.
  const n = ((data ?? []) as { state: string }[]).filter((m) => m.state === "to_do" || m.state === "overdue" || m.state === "renew_soon").length; // Counts the ones needing attention.
  return n || undefined; // The number, or nothing when zero.
} // End of trainingToDo.

// Whether the person pays for a family (Carla, 16 Nov 2026: only the
// people paying see billing). True for a family's bill payer or extra
// payer, or someone who may start a family's payments because nobody pays
// yet. Decides the Billing tab on the Parent and Student dashboards.
async function paysForFamily(): Promise<boolean> { // No inputs: it's about the signed-in person.
  const { data } = await (await createClient()).rpc("billing_i_pay"); // Asks the database whether they pay (or may start paying).
  return data === true; // Yes only when the database says so.
} // End of paysForFamily.

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

// How many tutor applications are new (not yet looked at), for the menu
// number. The database only lets the owner and Operations admins count them;
// anyone else (or a problem) gets no number.
async function newApplications(): Promise<number | undefined> {
  const { count, error } = await (await createClient()).from("tutor_applications").select("id", { count: "exact", head: true }).eq("status", "new"); // Counts the new ones without reading them.
  return error || !count ? undefined : count; // No number if none, or if it couldn't be counted.
} // End of newApplications.

// How many check-in answers need follow-up (a low rating, "not a good fit",
// or a request for contact), for the menu number. The database only lets the
// owner and operations admins count them; anyone else (or a problem) gets no
// number.
async function checkInsToFollowUp(): Promise<number | undefined> { // No inputs: it counts for the signed-in admin.
  const { count, error } = await (await createClient()).from("match_check_ins").select("id", { count: "exact", head: true }).eq("follow_up", "open"); // Counts the flagged ones without reading them.
  return error || !count ? undefined : count; // No number if none, or if it could not be counted.
} // End of checkInsToFollowUp.

// How many tutor late starts are waiting for review, for the menu number
// (Carla, 18 Nov 2026). The database only lets the owner and operations
// admins read them; anyone else (or a problem) gets no number.
async function latenessToReview(): Promise<number | undefined> { // No inputs: it counts for the signed-in admin.
  const { count, error } = await (await createClient()).from("session_lateness").select("id", { count: "exact", head: true }).eq("review_status", "open"); // Counts the open ones without reading them.
  return error || !count ? undefined : count; // No number if none, or if it could not be counted.
} // End of latenessToReview.

// How many staff probations are due for review now (owner only; Carla,
// 20 Nov 2026). Shown on the Staff probation tab. None (or a problem
// reading it) shows no number.
async function probationsDue(): Promise<number | undefined> { // No inputs: it counts for the signed-in owner.
  const { data, error } = await (await createClient()).rpc("staff_probation_due_count"); // Asks the database how many are due.
  return error || !data ? undefined : (data as number); // No number if none, or if it could not be counted.
} // End of probationsDue.

// The signed-in staff member's own contracts: whether they have any (so the
// "My contract" tab only shows once CLG has sent one), and how many are
// waiting for them to sign or finish (Carla, 17 Nov 2026). A problem reading
// them shows no tab.
async function myContracts(): Promise<{ any: boolean; waiting?: number }> { // No inputs: it is about the signed-in person.
  const supabase = await createClient(); // Connects to the database.
  const { data: me } = await supabase.auth.getUser(); // Who is signed in.
  if (!me.user) return { any: false }; // Nobody: no tab.
  const { data, error } = await supabase.from("employment_contracts").select("status").eq("account_id", me.user.id); // The statuses of their own contracts.
  if (error || !data?.length) return { any: false }; // None (or a problem): no tab.
  const waiting = data.filter((c) => c.status === "sent" || c.status === "signed").length; // How many need them.
  return { any: true, waiting: waiting || undefined }; // A tab, with the number (none when zero).
} // End of myContracts.

// How many signed contracts still need the Xero self-setup invite, for the
// Contracts tab number. Only admins who can see contracts get a number.
async function contractsXeroToDo(): Promise<number | undefined> { // No inputs: it counts for the signed-in admin.
  const { count, error } = await (await createClient()).from("employment_contracts").select("id", { count: "exact", head: true }).in("status", ["signed", "complete"]).is("xero_invite_at", null); // Counts them without reading them.
  return error || !count ? undefined : count; // No number if none, or if it could not be counted.
} // End of contractsXeroToDo.

// The Overview item that starts every dashboard's side menu: a quick look at
// everything that needs the person in that role (Carla, 20 Nov 2026).
function overviewItem(role: Role): Section { // Takes the dashboard.
  return { id: "overview", label: "Overview", href: `/home?as=${role}` }; // Its id, words and address.
} // End of overviewItem.

// Builds one dashboard's side menu, with to-do numbers. Each item knows its
// own address, so the menu works the same on every page that shows it.
// The menu is built once per page load and shared (the page frame and the
// Overview both use it), so its database reads are not repeated.
export async function getDashboardMenu(role: Role, roles: Role[]): Promise<Section[]> { // Takes the dashboard and all of the person's roles.
  return menuOnce(role, roles.join(",")); // Builds it (or reuses it), keyed by the dashboard and the roles as text.
} // End of getDashboardMenu.

// Remembers each built menu for the rest of one page load. The roles are
// passed as text, because remembering works on plain values, not lists.
const menuOnce = cache(async (role: Role, rolesKey: string): Promise<Section[]> => { // Takes the dashboard and the roles as text.
  const roles = rolesKey.split(",").filter(Boolean) as Role[]; // Turns the text back into a list of roles.
  return [overviewItem(role), ...(await buildDashboardMenu(role, roles))]; // The Overview first, then the rest of the menu.
}); // End of menuOnce.

// Builds the rest of one dashboard's side menu (everything after Overview).
async function buildDashboardMenu(role: Role, roles: Role[]): Promise<Section[]> { // Takes the dashboard and all of the person's roles.
  const todo = await getToDoCounts(roles); // The to-do numbers.
  const sessionLevel = role === "admin" ? await getAdminLevel() : null; // The admin's level (only matters on the admin dashboard), which decides the Sessions sub-tabs.
  const sessions: Section[] = (await hasSessions(role)) // The Sessions tab, if this dashboard has one:
    ? [{ // its details:
        id: "sessions", // its id,
        label: "Sessions", // its words,
        href: sessionsHref(role), // its address,
        count: todo.sessionsFor(role), // its number,
        // its sub-tabs (Overview, Bookings, Notices and the rest), each with
        // its own address and number, so the arrow can open them from any
        // page; their numbers add up to the Sessions number.
        items: sessionTabs(role, sessionLevel).map((t) => ({ ...t, href: sessionsHref(role, t.id), count: todo.sessionTab(role, t.id) })), // (the sub-tabs)
        countsInside: true, // and its sub-tabs carry all of its numbers.
      }] // End of the Sessions tab.
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
      count: todo.get("admin", s.id), // its number,
      items: s.id === "records" ? subTabs(PRIVACY_TABS, "/admin/privacy") : undefined, // and, for Privacy and records, its sub-tabs (privacy requests and the breach register).
    })); // End of the admin sections.
    items.splice(Math.min(1, items.length), 0, ...sessions); // Sessions goes second, after Families (one of an admin's main jobs).
    const billingToDo = ["families", "invoices", "pay"].reduce((t, id) => t + (todo.get("billing", id) ?? 0), 0); // Billing's total: families, invoices and pay.
    const billingCount = (id: string) => (["families", "invoices", "pay"].includes(id) ? todo.get("billing", id) : undefined); // A Billing sub-tab's number (the same three that make up Billing's total).
    if (isFinance) items.push({ id: "billing", label: "Billing", href: "/admin/billing", count: billingToDo || undefined, items: subTabs(BILLING_TABS, "/admin/billing", billingCount), countsInside: true }); // Billing (owner, operations and finance), with its sub-tabs and their numbers,
    if (isFinance) items.push({ id: "contracts", label: "Contracts", href: "/admin/contracts", count: await contractsXeroToDo() }); // staff employment contracts (owner, operations and finance; Carla, 17 Nov 2026), with Xero invites still to send counted,
    if (isDesk || isFinance) items.push({ id: "help", label: "Help chats", href: "/admin/help", count: todo.get("admin", "help") }); // the help desk: questions from families, students, tutors and staff (Carla, 16 Nov 2026), with chats waiting for CLG counted,
    const reportsCount = todo.get("admin", "reports"); // How many new reports are waiting (shown on Reports, and on its "All reports" sub-tab).
    if (level === "owner") items.push({ id: "reports", label: "Reports", href: "/admin/reports", count: reportsCount, items: subTabs(REPORTS_TABS, "/admin/reports", (id) => (id === "reports" ? reportsCount : undefined)), countsInside: true }); // Reports for the owner (everything, including pay and profit), with new reports counted, and its sub-tabs,
    if (level === "operations") items.push({ id: "reports", label: "Reports", href: "/admin/reports", items: subTabs(REPORTS_TABS.filter((t) => t.id === "reports" || t.id === "goals"), "/admin/reports") }); // Reports for Operations admins (Carla, 20 Nov 2026): reports without money, and goals; no "new" number, which is the owner's,
    const { data: me } = await (await createClient()).auth.getUser(); // Who is signed in (for the reviewer list check).
    const problems = me.user ? await problemReportsTab(level === "owner", me.user.id) : null; // The problem reports tab, if they check reports.
    if (problems) items.push({ id: "problems", label: "App issues", href: "/admin/problems", count: problems.count, items: problemTabs(level === "owner").map((t) => ({ ...t, count: t.id === "queue" ? problems.count : undefined })), countsInside: true }); // App issues (problem reports; owner and chosen reviewers), with new reports counted, and its sub-tabs,
    if (isFull) items.push({ id: "applications", label: "Tutor applications", href: "/admin/applications", count: await newApplications() }); // tutor applications from the public Apply to tutor page (full admins, Carla 16 Nov 2026), with new ones counted,
    if (isFull) items.push({ id: "check-ins", label: "Check-ins", href: "/admin/check-ins", count: await checkInsToFollowUp() }); // answers to the check-ins after a new match (full admins, Carla 16 Nov 2026), with ones needing follow-up counted,
    if (isFull) items.push({ id: "lateness", label: "Tutor lateness", href: "/admin/lateness", count: await latenessToReview() }); // late starts by tutors to review (full admins, Carla 18 Nov 2026), with open ones counted,
    if (level === "owner") items.push({ id: "probation", label: "Staff probation", href: "/admin/probation", count: await probationsDue() }); // staff probation reviews (owner only, Carla 20 Nov 2026), with ones due for review counted,
    if (isFull) items.push({ id: "feedback", label: "Feedback", href: "/admin/feedback" }); // the feedback overview, grouped by area (full admins),
    if (isFull) items.push({ id: "whats-new", label: "What is new", href: "/admin/whats-new" }); // writing the "What's new" pop-ups for each dashboard (full admins, Carla 15 Nov 2026),
    if (isFull) items.push({ id: "teams", label: "Teams links", href: "/admin/teams", items: subTabs(TEAMS_TABS, "/admin/teams") }); // Teams links for online sessions (full admins), with its sub-tabs,
    if (isFull) items.push({ id: "travel-map", label: "Travel map", href: "/admin/travel-map" }); // the map of libraries and tutor and family travel areas (full admins, Carla 16 Nov 2026),
    if (isFull) items.push({ id: "materials", label: "Materials library", href: "/admin/materials", items: subTabs(MATERIALS_TABS, "/admin/materials") }); // the materials library (full admins), with its sub-tabs,
    if (isFull) items.push({ id: "training-admin", label: "Training setup", href: "/admin/training", items: subTabs(TRAINING_SETUP_TABS, "/admin/training") }); // writing training modules, the handbook and progress (full admins), with its sub-tabs,
    items.push({ id: "guide", label: "App guide", href: "/guide?as=admin" }); // the step-by-step guide to the app for their admin level (Carla, 16 Nov 2026),
    items.push({ id: "training", label: "Training", href: "/training?as=admin", count: await trainingToDo() }); // their own training (every admin), with modules to do counted,
    items.push({ id: "handbook", label: "Handbooks", href: "/handbook?as=admin" }); // the handbook,
    const mine = await myContracts(); // Their own contracts, if any.
    if (mine.any) items.push({ id: "contract", label: "My contract", href: "/contract?as=admin", count: mine.waiting }); // their own employment contract, once one has been sent (Carla, 17 Nov 2026),
    items.push({ id: "pay", label: "My pay", href: "/pay?as=admin" }); // and their own pay (office admin hours).
    return items; // Hands back the admin menu.
  } // End of the admin menu.

  if (role === "tutor") { // The tutor menu:
    const mine = await myContracts(); // their own contracts, if any,
    const [first, ...rest] = TUTOR_SECTIONS.map((s) => ({ ...s, href: `/dashboard/tutor?section=${s.id}`, count: todo.get("tutor", s.id) })); // their sections, each with its address and number,
    return [ // hands back:
      first, // Your students,
      ...sessions, // Sessions,
      { id: "calendar", label: "Weekly calendar", href: "/dashboard/tutor/calendar" }, // their week at a glance, and the link for their own calendar (Carla, 12 Nov 2026),
      ...rest, // the other tutor sections,
      { id: "materials", label: "CLG materials", href: "/materials" }, // CLG materials,
      { id: "training", label: "Training", href: "/training?as=tutor", count: await trainingToDo() }, // their training (Carla, 16 Nov 2026), with modules to do counted,
      { id: "handbook", label: "Handbooks", href: "/handbook?as=tutor" }, // the tutor handbook,
      { id: "guide", label: "App guide", href: "/guide?as=tutor" }, // the step-by-step guide to the app for tutors (Carla, 16 Nov 2026),
      ...(mine.any ? [{ id: "contract", label: "My contract", href: "/contract?as=tutor", count: mine.waiting }] : []), // their employment contract, once one has been sent (Carla, 17 Nov 2026),
      { id: "pay", label: "My pay", href: "/pay?as=tutor" }, // and their pay.
    ]; // End of the tutor menu.
  } // End of the tutor menu.

  if (role === "parent") { // The parent menu:
    return [ // hands back:
      { id: "children", label: "Your children", href: "/dashboard/parent?section=children", count: todo.get("parent", "children") }, // Your children (with details to finish),
      ...sessions, // Sessions,
      { id: "calendar", label: "Weekly calendar", href: "/dashboard/calendar?as=parent" }, // the family's week at a glance, and the link for their own calendar (Carla, 15 Nov 2026),
      { id: "add", label: "Add a child", href: "/dashboard/parent?section=add" }, // Add a child,
      ...((await paysForFamily()) ? [{ id: "billing", label: "Billing", href: "/billing", count: todo.get("family", "billing") }] : []), // Billing, only for a parent who pays (Carla, 16 Nov 2026), with anything to set up,
      { id: "guide", label: "App guide", href: "/guide?as=parent" }, // and the step-by-step guide to the app for parents (Carla, 16 Nov 2026).
    ]; // End of the parent menu.
  } // End of the parent menu.

  // The student menu. Billing shows for an adult learner who pays for
  // themselves; someone who also has a Family profile sees Billing on the Family menu.
  return [ // Hands back:
    { id: "learning", label: "Your learning", href: "/dashboard/student", count: todo.get("student", "learning") }, // Your learning (with steps overdue),
    ...sessions, // Sessions,
    { id: "calendar", label: "Weekly calendar", href: "/dashboard/calendar?as=student" }, // their week at a glance, and the link for their own calendar (Carla, 15 Nov 2026),
    ...(!roles.includes("parent") && (await paysForFamily()) ? [{ id: "billing", label: "Billing", href: "/billing", count: todo.get("family", "billing") }] : []), // Billing, only for students who pay (Carla, 16 Nov 2026); someone who also has a Family profile sees it on their Family tab,
    { id: "guide", label: "App guide", href: "/guide?as=student" }, // and the step-by-step guide to the app for students (Carla, 16 Nov 2026).
  ]; // End of the student menu.
} // End of buildDashboardMenu.
