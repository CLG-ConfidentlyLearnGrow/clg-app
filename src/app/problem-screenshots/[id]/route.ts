// Summary: opens a screenshot attached to a problem report, for reviewers only.
//
import { NextResponse, type NextRequest } from "next/server"; // The reply tools for routes that send back files or redirects.
import { z } from "zod"; // The form-checking library (used to check the id).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Opens one screenshot. The database decides who may see it (the owner and
// the reviewer list, with two-step login). The link it hands out works for
// one minute only, and the browser is told not to keep a copy.
export async function GET(_request: NextRequest, ctx: RouteContext<"/problem-screenshots/[id]">) {
  const { id } = await ctx.params; // The screenshot's id from the address.
  const notFound = () => // A "not available" reply:
    new NextResponse("This screenshot isn't available to you.", { status: 404, headers: { "Cache-Control": "no-store" } }); // the same plain message for missing or not allowed, never saved by the browser.
  if (!z.uuid().safeParse(id).success) return notFound(); // Odd id: not available.

  const supabase = await createClient(); // Connects to the database.
  const { data: shot } = await supabase.from("problem_report_screenshots").select("file_path").eq("id", id).maybeSingle(); // Reads where it's kept (only if this person may see it).
  if (!shot?.file_path) return notFound(); // No record (or not allowed): not available.

  const { data: signed } = await supabase.storage.from("problem-screenshots").createSignedUrl(shot.file_path, 60); // Makes a link to the file that works for one minute.
  if (!signed?.signedUrl) return notFound(); // No link: not available.

  const res = NextResponse.redirect(signed.signedUrl); // Sends the browser to the one-minute link.
  res.headers.set("Cache-Control", "no-store"); // Tells the browser not to save it.
  return res; // Sends the reply.
} // End of GET.
