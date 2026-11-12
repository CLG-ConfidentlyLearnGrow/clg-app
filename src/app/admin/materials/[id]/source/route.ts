// Summary: downloads a material's editable original file (admins only).
//
import { NextResponse, type NextRequest } from "next/server"; // The reply tools for pages that send back files or redirects.
import { z } from "zod"; // The form-checking library (used to check the id).
import { getViewer } from "@/lib/auth"; // Finds out who is signed in.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Downloads a material's editable original. Admins only: the file store
// refuses everyone else. The link it hands out works for one minute.
export async function GET(_request: NextRequest, ctx: RouteContext<"/admin/materials/[id]/source">) {
  const { id } = await ctx.params; // The id from the address.
  const notFound = () => // A "not available" reply:
    new NextResponse("This file isn't available to you.", { status: 404, headers: { "Cache-Control": "no-store" } }); // a plain message, never saved by the browser.
  const viewer = await getViewer(); // Who is signed in.
  if (!viewer?.roles.includes("admin") || !z.uuid().safeParse(id).success) return notFound(); // Not an admin, or an odd id: not available.

  const supabase = await createClient(); // Connects to the database.
  const { data: m } = await supabase.from("materials").select("source_path, source_name").eq("id", id).maybeSingle(); // Reads where the original is kept, and its file name.
  if (!m?.source_path) return notFound(); // No original: not available.
  const { data: signed } = await supabase.storage // Makes a link:
    .from("materials") // to the materials file store,
    .createSignedUrl(m.source_path, 60, { download: m.source_name ?? true }); // that works for one minute and downloads with its file name.
  if (!signed?.signedUrl) return notFound(); // No link: not available.

  const res = NextResponse.redirect(signed.signedUrl); // Sends the browser to the link.
  res.headers.set("Cache-Control", "no-store"); // Tells the browser not to save it.
  return res; // Sends the reply.
} // End of GET.
