// Summary: who is signed in, what roles they hold, and the guards that keep
// pages for staff and admins away from everyone else. Identity always comes
// from the verified login, never from anything the browser claims.

// Stops this file ever being sent to the browser.
import "server-only";
// Lets a lookup run once per page request and be reused.
import { cache } from "react";
// Lets the code send someone to another page.
import { redirect } from "next/navigation";
// Connects to the database as the signed-in person.
import { createClient } from "@/lib/supabase/server";

// The four roles a person can hold (any mix of them).
export type Role = "admin" | "tutor" | "parent" | "student";

// What the app knows about the signed-in person.
export type Viewer = {
  id: string; // Their account id.
  email: string; // Their email address.
  fullName: string; // Their full name.
  roles: Role[]; // Every role they hold.
  aal: "aal1" | "aal2"; // aal2 means they've done two-step login this time; aal1 means password only.
}; // End of the person shape.

// The signed-in person, read once per request. Identity comes from the
// verified token (getClaims), never from anything the browser sends.
export const getViewer = cache(async (): Promise<Viewer | null> => {
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.auth.getClaims(); // Reads and checks the login token.
  const claims = data?.claims; // The details inside the token.
  if (!claims?.sub) return null; // Nobody signed in.

  const [roles, account] = await Promise.all([ // Asks two things at once:
    supabase.rpc("my_roles"), // which roles this person holds,
    supabase.from("accounts").select("full_name").eq("id", claims.sub).maybeSingle(), // and their full name.
  ]); // End of the two questions.

  return { // Hands back the person's details:
    id: claims.sub, // account id from the token,
    email: String(claims.email ?? ""), // email from the token (blank if none),
    fullName: account.data?.full_name ?? "", // name from their account (blank if none),
    roles: (roles.data ?? []) as Role[], // their roles (none if the lookup failed),
    aal: claims.aal === "aal2" ? "aal2" : "aal1", // and whether two-step login was done.
  }; // End of the details.
}); // End of getViewer.

// The signed-in person, or a trip to the login page if nobody is signed in.
export async function requireViewer(): Promise<Viewer> {
  const viewer = await getViewer(); // Looks up who's signed in.
  if (!viewer) redirect("/login"); // Nobody: go and sign in.
  return viewer; // Hands back the person.
} // End of requireViewer.

// Admins and tutors must use two-step login. The database enforces this too:
// without it their extra access simply does not apply.
export function needsTwoStep(viewer: Viewer): boolean {
  const isStaff = viewer.roles.includes("admin") || viewer.roles.includes("tutor"); // True for admins and tutors.
  return isStaff && viewer.aal !== "aal2"; // Staff who haven't done two-step login this time.
} // End of needsTwoStep.

// Admin levels (see docs/features/admin-levels.md). The database decides
// each person's level; the app only uses it to choose what to show.
export type AdminLevel = "owner" | "operations" | "support" | "finance";

// The plain name of each admin level.
export const ADMIN_LEVEL_NAMES: Record<AdminLevel, string> = {
  owner: "Owner", // Full control, including owner-only settings.
  operations: "Operations", // Runs day-to-day admin.
  support: "Support", // Front desk help.
  finance: "Finance", // Billing and pay.
}; // End of the level names.

// Who may use which part of the admin area. Same groups as the database.
export const FULL_ADMIN: AdminLevel[] = ["owner", "operations"]; // The full admin tools.
export const FRONT_DESK: AdminLevel[] = ["owner", "operations", "support"]; // Family and booking help.
export const FINANCE: AdminLevel[] = ["owner", "operations", "finance"]; // Billing pages.
export const PAY: AdminLevel[] = ["owner", "finance"]; // Staff pay.
export const ANY_ADMIN: AdminLevel[] = ["owner", "operations", "support", "finance"]; // Every admin.

// The level the signed-in admin is acting at (owner while emergency owner
// access is running), or null.
export const getAdminLevel = cache(async (): Promise<AdminLevel | null> => {
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("my_admin_level"); // Asks the database for this person's level.
  return typeof data === "string" && data in ADMIN_LEVEL_NAMES ? (data as AdminLevel) : null; // Uses it only if it's a known level.
}); // End of getAdminLevel.

// Signed-in admin with two-step login at one of these levels. Anyone else
// goes to their dashboard (or the admin page that suits their level).
export async function requireAdminLevel(levels: AdminLevel[]): Promise<Viewer & { level: AdminLevel }> {
  const viewer = await requireViewer(); // Must be signed in.
  if (!viewer.roles.includes("admin")) redirect("/dashboard"); // Not an admin: back to their dashboard.
  if (viewer.aal !== "aal2") redirect("/mfa"); // No two-step login yet: do it first.
  const level = await getAdminLevel(); // Looks up their admin level.
  if (!level) redirect("/dashboard"); // No level found: back to their dashboard.
  if (!levels.includes(level)) redirect(level === "finance" ? "/admin/billing" : "/admin"); // Wrong level: to the admin page that suits them.
  return { ...viewer, level }; // Allowed: hands back the person with their level.
} // End of requireAdminLevel.

// The full admin tools: owner or operations.
export async function requireAdmin(): Promise<Viewer & { level: AdminLevel }> {
  return requireAdminLevel(FULL_ADMIN); // Same guard, limited to owner and operations.
} // End of requireAdmin.
