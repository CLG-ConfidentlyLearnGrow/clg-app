// Summary: the daily job that refreshes Teams meeting links.
//
import { isCronRequest } from "@/lib/cron-auth"; // Checks the request really comes from the scheduler.
import { runTeamsSync } from "@/lib/teams/sync"; // The job that makes and updates Teams links.

// The daily Teams links run, called by Vercel's scheduler (see vercel.json).
// The job also runs after bookings, cancellations and schedule page visits;
// this makes sure it runs at least once a day.
export async function GET(request: Request) {
  if (!isCronRequest(request)) { // Not from the scheduler:
    return new Response("Not allowed", { status: 401 }); // refuses it.
  } // End of the check.
  const summary = await runTeamsSync({ force: true }); // Runs the job, even if it ran recently.
  if (summary.problems.length) console.error("Teams links problems:", summary.problems); // Notes any problems in the server log.
  return Response.json(summary); // Sends back a summary of what was done.
} // End of GET.
