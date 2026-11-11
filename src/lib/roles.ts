// Summary: the order of the role tabs at the top of the page and where each
// tab goes. Each role (admin, tutor, parent, student) has its own dashboard.

// Brings in the list of role names, for type checking only.
import type { Role } from "@/lib/auth";

// Each role has its own dashboard. Someone with several roles moves between
// them with the tabs at the top of the page. This is the order the tabs appear in.
export const ROLE_ORDER: Role[] = ["admin", "tutor", "parent", "student"];

// The words shown on each role's tab and the page it opens.
export const ROLE_TABS: Record<Role, { label: string; href: string }> = {
  admin: { label: "Admin", href: "/admin" }, // Admin tab opens the admin area.
  tutor: { label: "Tutor", href: "/dashboard/tutor" }, // Tutor tab opens the tutor dashboard.
  parent: { label: "Parent", href: "/dashboard/parent" }, // Parent tab opens the parent dashboard.
  student: { label: "Student", href: "/dashboard/student" }, // Student tab opens the student dashboard.
}; // End of the tab list.
