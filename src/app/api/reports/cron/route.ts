// Summary: the daily job that makes the owner's monthly, quarterly and
// financial year reports when each period finishes.
//
import { isCronRequest } from "@/lib/cron-auth"; // Checks the request really comes from the scheduler.
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).

// Called each morning by Vercel's scheduler (see vercel.json). The database
// works out which reports are due and only makes each one once, so running
// it more than once a day is harmless, and a missed day catches up next time.
export async function GET(request: Request) {
  if (!isCronRequest(request)) { // Not from the scheduler:
    return new Response("Not allowed", { status: 401 }); // refuses it.
  } // End of the check.
  const supabase = createAdminClient(); // Connects with full access.
  const { data, error } = await supabase.rpc("reports_make_due"); // Asks the database to make any reports that are due.
  if (error) { // It failed:
    console.error("Reports:", error.message); // notes why in the server log,
    return Response.json({ made: 0, problem: "Couldn't make the reports" }, { status: 500 }); // and reports the problem.
  } // End of the failure case.
  return Response.json({ made: data ?? 0 }); // Reports how many were made.
} // End of GET.
