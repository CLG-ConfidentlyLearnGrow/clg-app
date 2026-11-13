// Summary: the job that sends waiting security emails (owner access requests and security alerts)
// and child safety concern alerts.
//
import { isCronRequest } from "@/lib/cron-auth"; // Checks the request really comes from the scheduler.
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).
import { emailIsSetUp, sendEmails, type OutgoingEmail } from "@/lib/email/send"; // Checks email is set up, sends emails, and the type of an email.

// Sends security emails. The database calls this every 5 minutes while an
// email is waiting (see the email_sender migration). Each source hands
// over its due emails and marks them sent; if Resend refuses them, they are
// put back to try again next time.
//
// Since 2 Nov 2026 day-to-day notices (sessions, bookings, progress,
// pauses) are app notices only, so people don't learn to ignore CLG emails.
// The scheduling, progress and billing claim functions still exist in the
// database; add them back here to turn those emails on again.
const SOURCES = [ // Each kind of email: how to collect it, and how to put it back:
  { claim: "emergency_access_emails_claim", release: "emergency_access_emails_release" }, // emergency owner access emails,
  { claim: "security_alert_emails_claim", release: "security_alert_emails_release" }, // security alert emails,
  { claim: "safety_concern_emails_claim", release: "safety_concern_emails_release" }, // child safety concern alerts (no details, just "open the app").
] as const; // End of the list (fixed).

// Collects each kind of waiting email and sends it.
async function run(request: Request) {
  if (!isCronRequest(request)) { // Not from the scheduler:
    return new Response("Not allowed", { status: 401 }); // refuses it.
  } // End of the check.
  if (!emailIsSetUp()) { // Email not set up:
    // Leave everything waiting; notices still show in the app.
    return Response.json({ sent: 0, problem: "Email isn't set up yet (RESEND_API_KEY is missing)." }); // says so and sends nothing.
  } // End of that check.

  const supabase = createAdminClient(); // Connects with full access.
  let sent = 0; // How many were sent.
  const problems: string[] = []; // Any problems.
  for (const source of SOURCES) { // For each kind:
    const claimed = await supabase.rpc(source.claim, { p_limit: 50 }); // collects up to 50 waiting emails.
    if (claimed.error) { // Couldn't collect them:
      problems.push(`${source.claim}: ${claimed.error.message}`); // notes the problem,
      continue; // and moves on.
    } // End of the failure case.
    const emails = (claimed.data ?? []) as OutgoingEmail[]; // The emails.
    if (emails.length === 0) continue; // None: moves on.
    const problem = await sendEmails(emails); // Sends them.
    if (problem) { // A problem:
      problems.push(problem); // notes it,
      await supabase.rpc(source.release, { p_ids: emails.map((e) => e.id) }); // and puts them back to try again next time.
    } else { // Otherwise:
      sent += emails.length; // adds them to the count.
    } // End of the choice.
  } // End of the loop.
  if (problems.length > 0) console.error("Sending emails:", problems.join(" | ")); // Notes any problems in the server log.
  return Response.json( // Reports back:
    { sent, ...(problems.length ? { problem: problems.join(" | ") } : {}) }, // how many were sent, and any problems,
    { status: problems.length ? 500 : 200 }, // with an error status if there were problems.
  ); // End of the report.
} // End of run.

export const GET = run; // The scheduler may call with either kind of request,
export const POST = run; // so both run the same job.
