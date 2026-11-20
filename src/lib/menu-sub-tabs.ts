// Summary: the smaller tabs (sub-tabs) that sit under some side menu
// headings, such as Sessions (Overview, Bookings, Notices and more) or
// Billing (Family billing, Invoices, Staff pay and more). They are kept here,
// in one place, so the side menu can show every heading's sub-tabs from any
// page (Carla, 20 Nov 2026: the arrow beside a heading opens its sub-tabs
// without leaving the page you are on), and each page reads the same list to
// know which of its sub-tabs is open. This file only lists names and
// addresses, so it costs nothing to load: no database reads happen here.
//
import { FRONT_DESK, FULL_ADMIN, type AdminLevel, type Role } from "@/lib/auth"; // Admin level groups, and the types for an admin level and a role.

// Billing's sub-tabs (admin dashboard, /admin/billing).
export const BILLING_TABS = [ // Each sub-tab's id and its name on screen:
  { id: "families", label: "Family billing" }, // family billing,
  { id: "invoices", label: "Invoices" }, // invoices,
  { id: "pay", label: "Staff pay" }, // staff pay,
  { id: "prices", label: "Prices and settings" }, // prices and settings,
  { id: "connections", label: "Stripe and Xero" }, // Stripe and Xero.
] as const; // End of the list (fixed, so the ids are known exactly).

// Teams links' sub-tabs (admin dashboard, /admin/teams).
export const TEAMS_TABS = [ // Each sub-tab's id and its name on screen:
  { id: "sessions", label: "Online sessions" }, // online sessions,
  { id: "settings", label: "Settings" }, // settings.
] as const; // End of the list (fixed).

// Materials library's sub-tabs (admin dashboard, /admin/materials).
export const MATERIALS_TABS = [ // Each sub-tab's id and its name on screen:
  { id: "add", label: "Add materials" }, // add materials,
  { id: "library", label: "Library" }, // the library,
  { id: "opens", label: "Who opened what" }, // who opened what.
] as const; // End of the list (fixed).

// Training setup's sub-tabs (admin dashboard, /admin/training).
export const TRAINING_SETUP_TABS = [ // Each sub-tab's id and its name on screen:
  { id: "modules", label: "Modules" }, // the modules,
  { id: "progress", label: "Progress" }, // everyone's progress,
  { id: "tasks", label: "Practice tasks" }, // practice tasks waiting to be checked,
  { id: "handbook", label: "Handbooks" }, // the handbook,
  { id: "settings", label: "Settings" }, // the settings.
] as const; // End of the list (fixed).

// Reports' sub-tabs (owner only, /admin/reports).
export const REPORTS_TABS = [ // Each sub-tab's id and its name on screen:
  { id: "reports", label: "All reports" }, // the list of reports,
  { id: "make", label: "Report for your dates" }, // make one for any dates,
  { id: "settings", label: "Settings" }, // super and other costs.
] as const; // End of the list (fixed).

// Privacy and records' sub-tabs (admin dashboard, /admin/privacy).
export const PRIVACY_TABS = [ // Each sub-tab's id and its name on screen:
  { id: "requests", label: "Privacy requests" }, // privacy requests,
  { id: "breaches", label: "Breach register" }, // breach register.
] as const; // End of the list (fixed).

// App issues' sub-tabs (/admin/problems). Only the owner sees the second one,
// because only the owner chooses who checks app issues.
export function problemTabs(isOwner: boolean) { // Takes whether the person is the owner.
  return [ // Hands back:
    { id: "queue", label: "Reports", href: "/admin/problems" }, // the queue,
    ...(isOwner ? [{ id: "reviewers", label: "Who checks app issues", href: "/admin/problems?section=reviewers" }] : []), // and the reviewer list (owner only).
  ]; // End of the list.
} // End of problemTabs.

// Sessions' sub-tabs for one dashboard. Which ones show depends on the
// dashboard and, for admins, their level: front-desk admins (owner,
// operations, support) can book, full admins (owner, operations) also look
// after places, times and libraries, tutors see where they teach, and
// families (parents, and students 16 and over) can book.
export function sessionTabs(role: Role, adminLevel: AdminLevel | null) { // Takes the dashboard and the admin's level (if any).
  const isAdmin = role === "admin" && adminLevel !== null && FULL_ADMIN.includes(adminLevel); // a full admin in the admin dashboard,
  const isDesk = role === "admin" && adminLevel !== null && FRONT_DESK.includes(adminLevel); // a front-desk admin in the admin dashboard,
  const isTutor = role === "tutor"; // the tutor dashboard,
  const canBook = isDesk || role === "parent" || role === "student"; // dashboards that can book (front desk and families; tutors cannot).
  return [ // The sub-tabs:
    { id: "sessions", label: "Overview" }, // the overview (upcoming sessions),
    { id: "bookings", label: "Bookings" }, // bookings,
    ...(isDesk ? [{ id: "book", label: "Book a session" }] : []), // book a session (front desk),
    // Admins set where each student can have sessions; families give
    // preferred times and study dates only (Carla, 2 Nov 2026).
    ...(canBook ? [{ id: "child-places", label: isAdmin ? "Session places" : "Preferred times" }] : []), // session places (admins) or preferred times (families),
    ...(canBook ? [{ id: "booking-length", label: "How long to book" }] : []), // how long to book (those who can book),
    { id: "away", label: "Away dates" }, // away dates,
    ...(canBook || isTutor ? [{ id: "requests", label: "Requests" }] : []), // requests (those who can book, and tutors),
    { id: "blocks", label: "Blocks" }, // blocks,
    { id: "notices", label: "Notices" }, // notices,
    ...(canBook ? [{ id: "next-term", label: "Book again" }] : []), // book again (those who can book),
    ...(isDesk ? [{ id: "waitlist", label: "Waitlist" }] : []), // waitlist (front desk),
    ...(isTutor ? [{ id: "places", label: "Where you teach" }] : []), // where you teach (tutors),
    ...(isAdmin ? [{ id: "times", label: "Times to check" }] : []), // times to check (admins),
    ...(isAdmin ? [{ id: "tutor-availability", label: "Tutor availability" }] : []), // tutor availability (admins),
    ...(isAdmin ? [{ id: "libraries", label: "Libraries" }] : []), // libraries (admins).
  ]; // End of the sub-tabs.
} // End of sessionTabs.
