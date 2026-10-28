import { cronSecret } from "@/lib/billing/config";
import { runTeamsSync } from "@/lib/teams/sync";

// The daily Teams links run, called by Vercel's scheduler (see vercel.json).
// The job also runs after bookings, cancellations and schedule page visits;
// this makes sure it runs at least once a day.
export async function GET(request: Request) {
  const secret = cronSecret();
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response("Not allowed", { status: 401 });
  }
  const summary = await runTeamsSync({ force: true });
  if (summary.problems.length) console.error("Teams links problems:", summary.problems);
  return Response.json(summary);
}
