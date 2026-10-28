import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { stampMaterial } from "@/lib/materials-stamp";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

// Opens a material: a copy with the viewer's name, email and the date on
// every page. The database decides who may open it, logs the open and
// applies the daily limit (public.open_material). Only then does the server
// read the file with its own key; tutors have no direct access to the file
// store, so they can't get the original without the stamp.
export async function GET(_request: NextRequest, ctx: RouteContext<"/materials/[id]/file">) {
  const { id } = await ctx.params;
  const message = (text: string, status: number) =>
    new NextResponse(text, {
      status,
      headers: { "Cache-Control": "no-store", "Content-Type": "text/plain; charset=utf-8" },
    });
  if (!z.uuid().safeParse(id).success) return message("This material isn't available to you.", 404);

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("open_material", { p_material: id });
  if (error) {
    if (error.code === "54000") return message(`${error.message}.`, 429);
    return message(
      "This material isn't available to you. You need to be signed in with two-step login, and teach this subject at these year levels.",
      403,
    );
  }
  const row = (data as { file_path: string; file_type: string; title: string; viewer_name: string; viewer_email: string | null }[])?.[0];
  if (!row) return message("This material isn't available to you.", 404);

  const { data: blob, error: readError } = await createAdminClient().storage.from("materials").download(row.file_path);
  if (readError || !blob) return message("Couldn't open this material just now. Please try again.", 502);

  let stamped: Uint8Array;
  try {
    stamped = await stampMaterial(new Uint8Array(await blob.arrayBuffer()), row.file_type, row.title, {
      name: row.viewer_name,
      email: row.viewer_email ?? "",
      openedAt: new Date(),
    });
  } catch {
    return message("This material couldn't be prepared. Please let CLG know so it can be fixed.", 500);
  }

  const safeName = row.title.replace(/[^A-Za-z0-9 ._-]/g, "").trim().slice(0, 80) || "CLG material";
  return new NextResponse(Buffer.from(stamped), {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `inline; filename="${safeName} - CLG.pdf"`,
      "Cache-Control": "private, no-store",
      "X-Robots-Tag": "noindex, nofollow",
    },
  });
}
