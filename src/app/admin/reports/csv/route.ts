// Summary: downloads one report as a spreadsheet file (CSV) for the owner.
//
import { getAdminLevel } from "@/lib/auth"; // Reads the signed-in admin's level.
import { reportCsv, type SavedReport } from "@/lib/reports"; // Turns a report into CSV text, and the report type.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Sends the report named in the address (?id=...) as a CSV file. Only the
// owner gets it: the page checks the level, and the database only lets the
// owner read reports anyway.
export async function GET(request: Request) {
  if ((await getAdminLevel()) !== "owner") return new Response("Only the owner can download reports.", { status: 403 }); // Not the owner: refuses.
  const id = new URL(request.url).searchParams.get("id") ?? ""; // The report's id from the address.
  if (!/^[0-9a-f-]{36}$/.test(id)) return new Response("Report not found.", { status: 404 }); // Not a real id: says not found.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.from("reports").select("id, kind, period_start, period_end, figures, made_at, read_at").eq("id", id).maybeSingle(); // Reads the report.
  if (!data) return new Response("Report not found.", { status: 404 }); // Not there: says not found.
  const report = data as SavedReport; // The report.
  const name = `CLG report ${report.period_start} to ${report.period_end}.csv`; // The file name, e.g. "CLG report 2026-11-01 to 2026-11-30.csv".
  return new Response("﻿" + reportCsv(report), { // Sends the file (the first mark helps Excel read it correctly):
    headers: { // with these details:
      "Content-Type": "text/csv; charset=utf-8", // it's a CSV file,
      "Content-Disposition": `attachment; filename="${name}"`, // download it with this name,
      "Cache-Control": "private, no-store", // and don't keep a copy anywhere (it has pay and profit figures).
    }, // (end of the details)
  }); // End of the reply.
} // End of GET.
