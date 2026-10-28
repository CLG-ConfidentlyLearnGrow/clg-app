import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { getViewer } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

// Downloads a material's editable original. Admins only: the file store
// refuses everyone else. The link it hands out works for one minute.
export async function GET(_request: NextRequest, ctx: RouteContext<"/admin/materials/[id]/source">) {
  const { id } = await ctx.params;
  const notFound = () =>
    new NextResponse("This file isn't available to you.", { status: 404, headers: { "Cache-Control": "no-store" } });
  const viewer = await getViewer();
  if (!viewer?.roles.includes("admin") || !z.uuid().safeParse(id).success) return notFound();

  const supabase = await createClient();
  const { data: m } = await supabase.from("materials").select("source_path, source_name").eq("id", id).maybeSingle();
  if (!m?.source_path) return notFound();
  const { data: signed } = await supabase.storage
    .from("materials")
    .createSignedUrl(m.source_path, 60, { download: m.source_name ?? true });
  if (!signed?.signedUrl) return notFound();

  const res = NextResponse.redirect(signed.signedUrl);
  res.headers.set("Cache-Control", "no-store");
  return res;
}
