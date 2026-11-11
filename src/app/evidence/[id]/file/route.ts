// Summary: opens an uploaded report or piece of work, for those allowed to see it.
//
import { NextResponse, type NextRequest } from "next/server"; // The reply tools for pages that send back files or redirects.
import { z } from "zod"; // The form-checking library (used to check the id).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Opens an uploaded report or piece of work. The database decides who may
// see it (the family, the student's current tutors with two-step login, and
// admins). The link it hands out works for one minute only.
export async function GET(request: NextRequest, ctx: RouteContext<"/evidence/[id]/file">) {
  const { id } = await ctx.params; // The id from the address.
  const notFound = () => // A "not available" reply:
    new NextResponse("This file isn't available to you.", { status: 404, headers: { "Cache-Control": "no-store" } }); // the same plain message for missing or not allowed, never saved by the browser.
  if (!z.uuid().safeParse(id).success) return notFound(); // Odd id: not available.

  const supabase = await createClient(); // Connects to the database.
  const { data: item } = await supabase.from("learning_evidence").select("file_path").eq("id", id).maybeSingle(); // Reads where the file is kept (only if this person may see it).
  if (!item?.file_path) return notFound(); // No record or no file: not available.

  const { data: signed } = await supabase.storage.from("learning-evidence").createSignedUrl(item.file_path, 60); // Makes a link to the file that works for one minute.
  if (!signed?.signedUrl) return notFound(); // No link: not available.

  const res = NextResponse.redirect(signed.signedUrl); // Sends the browser to the one-minute link.
  res.headers.set("Cache-Control", "no-store"); // Tells the browser not to save it.
  return res; // Sends the reply.
} // End of GET.
