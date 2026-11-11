// Summary: downloads one file with everything the app holds about the person.
//
import { NextResponse } from "next/server"; // The reply tool for sending files.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// "Download my information": one file with everything the app holds about
// the signed-in person and the children they look after (access and
// portability rights). The database works out what is included, using the
// person's own access rules, and logs that a download happened.
export async function GET() {
  const supabase = await createClient(); // Connects to the database.
  const { data: claims } = await supabase.auth.getClaims(); // Reads who is signed in.
  if (!claims?.claims?.sub) { // Nobody signed in:
    return new NextResponse("Please sign in first.", { status: 401, headers: { "Cache-Control": "no-store" } }); // asks them to sign in, never saved by the browser.
  } // End of the check.
  const { data, error } = await supabase.rpc("my_data_export"); // Asks the database for their information.
  if (error || !data) { // Couldn't make it:
    return new NextResponse("We couldn't make your download. Please try again, or send CLG a privacy request.", { // a plain message:
      status: 500, // (server error)
      headers: { "Cache-Control": "no-store" }, // never saved by the browser.
    }); // (end of the reply)
  } // End of the failure case.
  await supabase.rpc("log_my_data_export"); // Logs that a download happened.
  const day = new Date().toISOString().slice(0, 10); // Today's date, for the file name.
  return new NextResponse(JSON.stringify(data, null, 2), { // Sends the information as a tidy file:
    headers: { // (the file's details:)
      "Content-Type": "application/json; charset=utf-8", // it's a data file,
      "Content-Disposition": `attachment; filename="clg-my-information-${day}.json"`, // download it with a name like clg-my-information-2026-11-11.json,
      "Cache-Control": "no-store", // and never save it in the browser.
    }, // (end of the details)
  }); // End of the reply.
} // End of GET.
