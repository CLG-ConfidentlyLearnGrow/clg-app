// Summary: opens a teaching material with the viewer's name, email and date stamped on every page.
//
import { NextResponse, type NextRequest } from "next/server"; // The reply tools for sending files.
import { z } from "zod"; // The form-checking library (used to check the id).
import { stampMaterial } from "@/lib/materials-stamp"; // Adds the viewer's details to each page.
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Opens a material: a copy with the viewer's name, email and the date on
// every page. The database decides who may open it, logs the open and
// applies the daily limit (public.open_material). Only then does the server
// read the file with its own key; tutors have no direct access to the file
// store, so they can't get the original without the stamp.
export async function GET(_request: NextRequest, ctx: RouteContext<"/materials/[id]/file">) {
  const { id } = await ctx.params; // The id from the address.
  const message = (text: string, status: number) => // A plain-text reply:
    new NextResponse(text, { // (with the given words)
      status, // and status,
      headers: { "Cache-Control": "no-store", "Content-Type": "text/plain; charset=utf-8" }, // never saved by the browser.
    }); // (end of the reply)
  if (!z.uuid().safeParse(id).success) return message("This material isn't available to you.", 404); // Odd id: not available.

  const supabase = await createClient(); // Connects to the database as the viewer.
  const { data, error } = await supabase.rpc("open_material", { p_material: id }); // Asks the database to open it (it checks, logs and counts).
  if (error) { // Refused:
    if (error.code === "54000") return message(`${error.message}.`, 429); // over today's limit: says so,
    return message( // otherwise explains who can open materials.
      "This material isn't available to you. You need to be signed in with two-step login, and teach this subject at these year levels.", // (the words)
      403, // (not allowed)
    ); // (end of the reply)
  } // End of the refusal.
  const row = (data as { file_path: string; file_type: string; title: string; viewer_name: string; viewer_email: string | null }[])?.[0]; // The file's details and the viewer's name and email.
  if (!row) return message("This material isn't available to you.", 404); // Nothing: not available.

  const { data: blob, error: readError } = await createAdminClient().storage.from("materials").download(row.file_path); // Reads the file with full access.
  if (readError || !blob) return message("Couldn't open this material just now. Please try again.", 502); // Couldn't read it: asks them to try again.

  let stamped: Uint8Array; // The stamped copy.
  try { // Tries:
    stamped = await stampMaterial(new Uint8Array(await blob.arrayBuffer()), row.file_type, row.title, { // stamping the file:
      name: row.viewer_name, // the viewer's name,
      email: row.viewer_email ?? "", // their email (or blank),
      openedAt: new Date(), // and the time now.
    }); // (end of the stamp details)
  } catch { // If it couldn't be stamped:
    return message("This material couldn't be prepared. Please let CLG know so it can be fixed.", 500); // asks them to tell CLG.
  } // End of the try.

  const safeName = row.title.replace(/[^A-Za-z0-9 ._-]/g, "").trim().slice(0, 80) || "CLG material"; // A safe file name from the title (or "CLG material").
  return new NextResponse(Buffer.from(stamped), { // Sends the stamped copy:
    headers: { // (the file's details:)
      "Content-Type": "application/pdf", // it's a PDF,
      "Content-Disposition": `inline; filename="${safeName} - CLG.pdf"`, // open it in the browser, named after the material,
      "Cache-Control": "private, no-store", // never save it in any shared store,
      "X-Robots-Tag": "noindex, nofollow", // and keep it out of search engines.
    }, // (end of the details)
  }); // End of the reply.
} // End of GET.
