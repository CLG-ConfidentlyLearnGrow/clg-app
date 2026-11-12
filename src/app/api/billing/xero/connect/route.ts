// Summary: starts connecting CLG's Xero account (owner only).
//
import { randomBytes } from "node:crypto"; // Makes random codes.
import { cookies } from "next/headers"; // Reads and sets browser cookies.
import { redirect } from "next/navigation"; // Sends the person to another address.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is an admin.
import { siteUrl } from "@/lib/env"; // The app's web address.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { xeroSignInUrl } from "@/lib/billing/xero"; // Builds the Xero sign-in address.

// Sends the owner to Xero to connect CLG's organisation.
export async function GET() {
  const viewer = await requireAdmin(); // Makes sure the person is an admin, and gets who they are.
  const supabase = await createClient(); // Connects to the database.
  const me = await supabase.from("admin_profiles").select("level").eq("account_id", viewer.id).maybeSingle(); // Reads their admin level.
  if (me.data?.level !== "owner") redirect("/admin/billing?xero=owner-only"); // Not the owner: sends them back with a note.

  const state = randomBytes(24).toString("hex"); // A random one-off code, to check the reply really comes from this request.
  (await cookies()).set("xero_state", state, { httpOnly: true, secure: true, sameSite: "lax", maxAge: 600, path: "/api/billing/xero" }); // Keeps the code in a private cookie for 10 minutes.
  redirect(xeroSignInUrl(`${siteUrl()}/api/billing/xero/callback`, state)); // Sends them to Xero, which comes back to the callback address.
} // End of GET.
