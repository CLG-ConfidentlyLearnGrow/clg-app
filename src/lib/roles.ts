import type { Role } from "@/lib/auth";

// Each role has its own dashboard. Someone with several roles moves between
// them with the tabs at the top of the page.
export const ROLE_ORDER: Role[] = ["admin", "tutor", "parent", "student"];

export const ROLE_TABS: Record<Role, { label: string; href: string }> = {
  admin: { label: "Admin", href: "/admin" },
  tutor: { label: "Tutor", href: "/dashboard/tutor" },
  parent: { label: "Parent", href: "/dashboard/parent" },
  student: { label: "Student", href: "/dashboard/student" },
};
