import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

// Opens the copy of a check certificate. The database decides who may see
// it (the tutor it belongs to, or an admin, both with two-step login). The
// link it hands out works for one minute only.
export async function GET(request: NextRequest, ctx: RouteContext<"/checks/[id]/document">) {
  const { id } = await ctx.params;
  const notFound = () =>
    new NextResponse("This file isn't available to you.", { status: 404, headers: { "Cache-Control": "no-store" } });
  if (!z.uuid().safeParse(id).success) return notFound();

  const supabase = await createClient();
  const { data: check } = await supabase.from("tutor_checks").select("document_path").eq("id", id).maybeSingle();
  if (!check?.document_path) return notFound();

  const { data: signed } = await supabase.storage.from("check-documents").createSignedUrl(check.document_path, 60);
  if (!signed?.signedUrl) return notFound();

  const res = NextResponse.redirect(signed.signedUrl);
  res.headers.set("Cache-Control", "no-store");
  return res;
}
