import { cronSecret } from "@/lib/billing/config";
import { createAdminClient } from "@/lib/supabase/admin";
import { emailIsSetUp, sendEmails, type OutgoingEmail } from "@/lib/email/send";

// Sends notices that are due by email. The database calls this every
// 5 minutes while an email is waiting (see the email_sender migration).
// Each module hands over its own due notices and marks them sent; if
// Resend refuses them, they are put back to try again next time.
const SOURCES = [
  { claim: "session_notice_emails_claim", release: "session_notice_emails_release" },
  { claim: "progress_notice_emails_claim", release: "progress_notice_emails_release" },
  { claim: "billing_tutor_notice_emails_claim", release: "billing_tutor_notice_emails_release" },
  { claim: "emergency_access_emails_claim", release: "emergency_access_emails_release" },
] as const;

async function run(request: Request) {
  const secret = cronSecret();
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
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
