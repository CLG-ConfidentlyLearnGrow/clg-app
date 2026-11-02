import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

// "Download my information": one file with everything the app holds about
// the signed-in person and the children they look after (access and
// portability rights). The database works out what is included, using the
// person's own access rules, and logs that a download happened.
export async function GET() {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims?.sub) {
    return new NextResponse("Please sign in first.", { status: 401, headers: { "Cache-Control": "no-store" } });
  }
  const { data, error } = await supabase.rpc("my_data_export");
  if (error || !data) {
    return new NextResponse("We couldn't make your download. Please try again, or send CLG a privacy request.", {
      status: 500,
      headers: { "Cache-Control": "no-store" },
    });
  }
  await supabase.rpc("log_my_data_export");
  const day = new Date().toISOString().slice(0, 10);
  return new NextResponse(JSON.stringify(data, null, 2), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Disposition": `attachment; filename="clg-my-information-${day}.json"`,
      "Cache-Control": "no-store",
    },
  });
}
