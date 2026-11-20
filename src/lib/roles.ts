// Summary: the order of the role tabs at the top of the page and where each
// tab goes. Each role (admin, tutor, parent, student) has its own dashboard.

// Brings in the list of role names, for type checking only.
import type { Role } from "@/lib/auth";

// Each role has its own dashboard. Someone with several roles moves between
// them with the tabs at the top of the page. This is the order the tabs appear in.
export const ROLE_ORDER: Role[] = ["admin", "tutor", "parent", "student"];

// The words shown on each role's tab and the page it opens. Every tab (and
// Home) opens that dashboard's Overview: a quick look at everything that
// needs the person in that role (Carla, 20 Nov 2026).
export const ROLE_TABS: Record<Role, { label: string; href: string }> = {
  admin: { label: "Admin", href: "/home?as=admin" }, // Admin tab opens the admin Overview.
  tutor: { label: "Tutor", href: "/home?as=tutor" }, // Tutor tab opens the tutor Overview.
  parent: { label: "Parent", href: "/home?as=parent" }, // Parent tab opens the parent Overview.
  student: { label: "Student", href: "/home?as=student" }, // Student tab opens the student Overview.
}; // End of the tab list.

// Each dashboard's main working page (the page its own side-menu sections
// sit on, for example "/dashboard/parent?section=children"). Menu items that
// have no address of their own are opened as a section of this page.
export const ROLE_PAGES: Record<Role, string> = {
  admin: "/admin", // The admin sections page.
  tutor: "/dashboard/tutor", // The tutor sections page.
  parent: "/dashboard/parent", // The parent sections page.
  student: "/dashboard/student", // The student learning page.
}; // End of the page list.
