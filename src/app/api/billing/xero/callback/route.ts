// Summary: finishes connecting CLG's Xero account after the owner signs in at Xero.
//
import { cookies } from "next/headers"; // Reads and clears browser cookies.
import { redirect } from "next/navigation"; // Sends the person to another address.
import type { NextRequest } from "next/server"; // The type of an incoming request.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is an admin.
import { siteUrl } from "@/lib/env"; // The app's web address.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { finishXeroSignIn } from "@/lib/billing/xero"; // Swaps Xero's code for a lasting connection.

// Xero sends the owner back here after they sign in.
export async function GET(request: NextRequest) {
  const viewer = await requireAdmin(); // Makes sure the person is an admin, and gets who they are.
  const supabase = await createClient(); // Connects to the database.
  const me = await supabase.from("admin_profiles").select("level").eq("account_id", viewer.id).maybeSingle(); // Reads their admin level.
  if (me.data?.level !== "owner") redirect("/admin/billing?xero=owner-only"); // Not the owner: sends them back with a note.

  const jar = await cookies(); // The browser's cookies.
  const expected = jar.get("xero_state")?.value; // The one-off code saved when they left for Xero.
  jar.delete("xero_state"); // Clears it, so it can't be used again.
  const code = request.nextUrl.searchParams.get("code"); // The code Xero sent back.
  if (!code || !expected || request.nextUrl.searchParams.get("state") !== expected) { // Missing code, or the one-off code doesn't match:
    redirect("/admin/billing?xero=failed"); // sends them back with a failure note.
  } // End of the check.
  let ok = true; // Notes whether it worked.
  try { // Tries:
    await finishXeroSignIn(code, `${siteUrl()}/api/billing/xero/callback`, viewer.id); // finishing the connection.
  } catch (e) { // If it failed:
    console.error("Xero connect failed:", (e as Error).message); // notes why in the server log,
    ok = false; // and marks it as failed.
  } // End of the try.
  redirect(`/admin/billing?xero=${ok ? "connected" : "failed"}`); // Sends them back saying whether it connected.
} // End of GET.
