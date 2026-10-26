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

export async function requireAdmin(): Promise<Viewer> {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("admin")) redirect("/dashboard");
  if (viewer.aal !== "aal2") redirect("/mfa");
  return viewer;
}
