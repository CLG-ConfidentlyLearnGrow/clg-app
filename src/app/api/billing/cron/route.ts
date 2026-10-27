import { cronSecret } from "@/lib/billing/config";
import { runBilling } from "@/lib/billing/run";

// The daily billing run, called by Vercel's scheduler (see vercel.json).
// Vercel sends "Authorization: Bearer <CRON_SECRET>"; anything else is refused.
export async function GET(request: Request) {
  const secret = cronSecret();
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response("Not allowed", { status: 401 });
  }
  const summary = await runBilling();
  if (summary.problems.length) console.error("Billing run problems:", summary.problems);
  return Response.json(summary);
}
