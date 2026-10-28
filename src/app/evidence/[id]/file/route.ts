import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

// Opens an uploaded report or piece of work. The database decides who may
// see it (the family, the student's current tutors with two-step login, and
// admins). The link it hands out works for one minute only.
export async function GET(request: NextRequest, ctx: RouteContext<"/evidence/[id]/file">) {
  const { id } = await ctx.params;
  const notFound = () =>
    new NextResponse("This file isn't available to you.", { status: 404, headers: { "Cache-Control": "no-store" } });
  if (!z.uuid().safeParse(id).success) return notFound();

  const supabase = await createClient();
  const { data: item } = await supabase.from("learning_evidence").select("file_path").eq("id", id).maybeSingle();
  if (!item?.file_path) return notFound();

  const { data: signed } = await supabase.storage.from("learning-evidence").createSignedUrl(item.file_path, 60);
  if (!signed?.signedUrl) return notFound();

  const res = NextResponse.redirect(signed.signedUrl);
  res.headers.set("Cache-Control", "no-store");
  return res;
}
