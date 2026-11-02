import { isCronRequest } from "@/lib/cron-auth";
import { runBilling } from "@/lib/billing/run";

// The daily billing run, called by Vercel's scheduler (see vercel.json).
// Vercel sends "Authorization: Bearer <CRON_SECRET>"; anything else is refused.
export async function GET(request: Request) {
  if (!isCronRequest(request)) {
    return new Response("Not allowed", { status: 401 });
  }
  const summary = await runBilling();
  if (summary.problems.length) console.error("Billing run problems:", summary.problems);
  return Response.json(summary);
}
