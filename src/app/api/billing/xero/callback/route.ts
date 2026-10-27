import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import type { NextRequest } from "next/server";
import { requireAdmin } from "@/lib/auth";
import { siteUrl } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";
import { finishXeroSignIn } from "@/lib/billing/xero";

// Xero sends the owner back here after they sign in.
export async function GET(request: NextRequest) {
  const viewer = await requireAdmin();
  const supabase = await createClient();
  const me = await supabase.from("admin_profiles").select("level").eq("account_id", viewer.id).maybeSingle();
  if (me.data?.level !== "owner") redirect("/admin/billing?xero=owner-only");

  const jar = await cookies();
  const expected = jar.get("xero_state")?.value;
  jar.delete("xero_state");
  const code = request.nextUrl.searchParams.get("code");
  if (!code || !expected || request.nextUrl.searchParams.get("state") !== expected) {
    redirect("/admin/billing?xero=failed");
  }
  let ok = true;
  try {
    await finishXeroSignIn(code, `${siteUrl()}/api/billing/xero/callback`, viewer.id);
  } catch (e) {
    console.error("Xero connect failed:", (e as Error).message);
    ok = false;
  }
  redirect(`/admin/billing?xero=${ok ? "connected" : "failed"}`);
}
