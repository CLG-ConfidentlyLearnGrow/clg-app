import { isCronRequest } from "@/lib/cron-auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { emailIsSetUp, sendEmails, type OutgoingEmail } from "@/lib/email/send";

// Sends security emails. The database calls this every 5 minutes while an
// email is waiting (see the email_sender migration). Each source hands
// over its due emails and marks them sent; if Resend refuses them, they are
// put back to try again next time.
//
// Since 2 Nov 2026 day-to-day notices (sessions, bookings, progress,
// pauses) are app notices only, so people don't learn to ignore CLG emails.
// The scheduling, progress and billing claim functions still exist in the
// database; add them back here to turn those emails on again.
const SOURCES = [
  { claim: "emergency_access_emails_claim", release: "emergency_access_emails_release" },
  { claim: "security_alert_emails_claim", release: "security_alert_emails_release" },
] as const;

async function run(request: Request) {
  if (!isCronRequest(request)) {
    return new Response("Not allowed", { status: 401 });
  }
  if (!emailIsSetUp()) {
    // Leave everything waiting; notices still show in the app.
    return Response.json({ sent: 0, problem: "Email isn't set up yet (RESEND_API_KEY is missing)." });
  }

  const supabase = createAdminClient();
  let sent = 0;
  const problems: string[] = [];
  for (const source of SOURCES) {
    const claimed = await supabase.rpc(source.claim, { p_limit: 50 });
    if (claimed.error) {
      problems.push(`${source.claim}: ${claimed.error.message}`);
      continue;
    }
    const emails = (claimed.data ?? []) as OutgoingEmail[];
    if (emails.length === 0) continue;
    const problem = await sendEmails(emails);
    if (problem) {
      problems.push(problem);
      await supabase.rpc(source.release, { p_ids: emails.map((e) => e.id) });
    } else {
      sent += emails.length;
    }
  }
  if (problems.length > 0) console.error("Sending emails:", problems.join(" | "));
  return Response.json(
    { sent, ...(problems.length ? { problem: problems.join(" | ") } : {}) },
    { status: problems.length ? 500 : 200 },
  );
}

export const GET = run;
export const POST = run;
