import { randomBytes } from "node:crypto";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/auth";
import { siteUrl } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";
import { xeroSignInUrl } from "@/lib/billing/xero";

// Sends the owner to Xero to connect CLG's organisation.
export async function GET() {
  const viewer = await requireAdmin();
  const supabase = await createClient();
  const me = await supabase.from("admin_profiles").select("level").eq("account_id", viewer.id).maybeSingle();
  if (me.data?.level !== "owner") redirect("/admin/billing?xero=owner-only");

  const state = randomBytes(24).toString("hex");
  (await cookies()).set("xero_state", state, { httpOnly: true, secure: true, sameSite: "lax", maxAge: 600, path: "/api/billing/xero" });
  redirect(xeroSignInUrl(`${siteUrl()}/api/billing/xero/callback`, state));
}
