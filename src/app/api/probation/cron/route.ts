// Summary: the daily job for staff probation (Carla, 20 Nov 2026). Each
// morning it sets up probation records for new tutors and admin staff, and
// sends the owner an app notice when someone is due for their probation
// review. The database does the work. See docs/features/staff-probation.md.
//
import { isCronRequest } from "@/lib/cron-auth"; // Checks the request really comes from the scheduler.
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).

// The daily run, called by Vercel's scheduler (see vercel.json).
export async function GET(request: Request) { // Handles the scheduler's request.
  if (!isCronRequest(request)) { // Not from the scheduler:
    return new Response("Not allowed", { status: 401 }); // refuses it.
  } // End of the check.
  const supabase = createAdminClient(); // Connects with full access.
  const { data, error } = await supabase.rpc("staff_probation_daily"); // Sets up new records and sends reminders.
  if (error) { // It failed:
    console.error("Staff probation daily run:", error.message); // notes why in the server log,
    return Response.json({ reminders: 0, problem: "Could not run the probation check" }, { status: 500 }); // and reports the problem.
  } // End of the failure case.
  return Response.json({ reminders: data ?? 0 }); // Reports how many reminders were sent.
} // End of GET.
