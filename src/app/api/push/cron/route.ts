// Summary: the job that sends waiting pop-up notifications to phones and
// computers (Carla, 18 Nov 2026). The database calls it every minute, but
// only while a pop-up is waiting (see the push_notifications migration).
//
import { isCronRequest } from "@/lib/cron-auth"; // Checks the request really comes from the database timer.
import { sendDuePopUps } from "@/lib/push"; // Collects and sends the pop-ups that are due.

// Sends every pop-up that is due now.
async function run(request: Request) { // Starts the steps.
  if (!isCronRequest(request)) { // Not from the database timer:
    return new Response("Not allowed", { status: 401 }); // refuses it.
  } // End of the check.
  const result = await sendDuePopUps(); // Sends what is due.
  if (result.problem) console.error("Sending pop-ups:", result.problem); // Notes any problem in the server log.
  return Response.json(result, { status: result.problem ? 500 : 200 }); // Reports how many were sent, with an error status if there was a problem.
} // End of run.

export const GET = run; // The timer may call with either kind of request,
export const POST = run; // so both run the same job.
