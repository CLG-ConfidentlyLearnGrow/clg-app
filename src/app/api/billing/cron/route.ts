// Summary: the web address the scheduler calls each day to run billing.
//
import { isCronRequest } from "@/lib/cron-auth"; // Checks the call really comes from the scheduler.
import { runBilling } from "@/lib/billing/run"; // The billing run itself.

// The daily billing run, called by Vercel's scheduler (see vercel.json).
// Vercel sends "Authorization: Bearer <CRON_SECRET>"; anything else is refused.
export async function GET(request: Request) { // Runs when the scheduler calls this address.
  if (!isCronRequest(request)) { // Not from the scheduler:
    return new Response("Not allowed", { status: 401 }); // refuses it.
  } // End of the check.
  const summary = await runBilling(); // Runs billing and keeps its summary.
  if (summary.problems.length) console.error("Billing run problems:", summary.problems); // Notes any problems in the server log.
  return Response.json(summary); // Replies with the summary.
} // End of GET.
