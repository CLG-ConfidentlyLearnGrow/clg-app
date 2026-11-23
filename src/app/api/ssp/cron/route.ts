// Summary: the hourly Student Success Program job (Carla, 22 Nov 2026). It
// sends the 48 hour deposit reminder, forfeits a place when the deposit is
// not paid within 72 hours, reminds payers 24 hours before each program
// payment, and warns about (then forfeits after) a missed payment. All the
// rules live in the database function public.ssp_run_deadlines.
import { isCronRequest } from "@/lib/cron-auth"; // Checks the request really comes from the scheduler.
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).

// Called every hour by Vercel's scheduler (see vercel.json).
export async function GET(request: Request) {
  if (!isCronRequest(request)) { // Not from the scheduler:
    return new Response("Not allowed", { status: 401 }); // refuses it.
  } // End of the check.
  const supabase = createAdminClient(); // Connects with full access (the database only lets the server run this job).
  const result = await supabase.rpc("ssp_run_deadlines"); // Runs the reminders, warnings and forfeits that are due.
  if (result.error) { // Something went wrong:
    console.error("Student Success Program deadlines:", result.error.message); // notes why in the server log,
    return Response.json({ problem: "Could not run the program deadlines" }, { status: 500 }); // and reports a failure.
  } // End of the failure case.
  return Response.json({ done: result.data ?? 0 }); // Reports how many reminders, warnings and forfeits were done.
} // End of GET.
