import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type Role = "admin" | "tutor" | "parent" | "student";

export type Viewer = {
  id: string;
  email: string;
  fullName: string;
  roles: Role[];
  aal: "aal1" | "aal2";
};

// The signed-in person, read once per request. Identity comes from the
// verified token (getClaims), never from anything the browser sends.
export const getViewer = cache(async (): Promise<Viewer | null> => {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!claims?.sub) return null;

  const [roles, account] = await Promise.all([
    supabase.rpc("my_roles"),
    supabase.from("accounts").select("full_name").eq("id", claims.sub).maybeSingle(),
  ]);

  return {
    id: claims.sub,
    email: String(claims.email ?? ""),
    fullName: account.data?.full_name ?? "",
    roles: (roles.data ?? []) as Role[],
    aal: claims.aal === "aal2" ? "aal2" : "aal1",
  };
});

export async function requireViewer(): Promise<Viewer> {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  return viewer;
}

// Admins and tutors must use two-step login. The database enforces this too:
// without it their extra access simply does not apply.
export function needsTwoStep(viewer: Viewer): boolean {
  const isStaff = viewer.roles.includes("admin") || viewer.roles.includes("tutor");
  return isStaff && viewer.aal !== "aal2";
}

// Admin levels (see docs/features/admin-levels.md). The database decides
// each person's level; the app only uses it to choose what to show.
export type AdminLevel = "owner" | "operations" | "support" | "finance";

export const ADMIN_LEVEL_NAMES: Record<AdminLevel, string> = {
  owner: "Owner",
  operations: "Operations",
  support: "Support",
  finance: "Finance",
};

// Who may use which part of the admin area. Same groups as the database.
export const FULL_ADMIN: AdminLevel[] = ["owner", "operations"];
export const FRONT_DESK: AdminLevel[] = ["owner", "operations", "support"];
export const FINANCE: AdminLevel[] = ["owner", "operations", "finance"];
export const PAY: AdminLevel[] = ["owner", "finance"];
export const ANY_ADMIN: AdminLevel[] = ["owner", "operations", "support", "finance"];

// The level the signed-in admin is acting at (owner while emergency owner
// access is running), or null.
export const getAdminLevel = cache(async (): Promise<AdminLevel | null> => {
  const supabase = await createClient();
  const { data } = await supabase.rpc("my_admin_level");
  return typeof data === "string" && data in ADMIN_LEVEL_NAMES ? (data as AdminLevel) : null;
});

// Signed-in admin with two-step login at one of these levels. Anyone else
// goes to their dashboard (or the admin page that suits their level).
export async function requireAdminLevel(levels: AdminLevel[]): Promise<Viewer & { level: AdminLevel }> {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("admin")) redirect("/dashboard");
  if (viewer.aal !== "aal2") redirect("/mfa");
  const level = await getAdminLevel();
  if (!level) redirect("/dashboard");
  if (!levels.includes(level)) redirect(level === "finance" ? "/admin/billing" : "/admin");
  return { ...viewer, level };
}

// The full admin tools: owner or operations.
export async function requireAdmin(): Promise<Viewer & { level: AdminLevel }> {
  return requireAdminLevel(FULL_ADMIN);
}
