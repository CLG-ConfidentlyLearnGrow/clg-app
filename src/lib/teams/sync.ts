import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { GraphError, createMeeting, deleteMeeting, graphConfig } from "./graph";

// The Teams links job. Makes a meeting for each online session in the next
// few days and deletes meetings for sessions that were cancelled or have
// finished. The database decides which (see the Teams migration), so this
// is safe to call often: from the daily schedule, after bookings and
// cancellations, from the schedule page, and from the admin button.

export type TeamsSummary = { ran: boolean; made: number; removed: number; problems: string[] };

export async function runTeamsSync(options: { force?: boolean } = {}): Promise<TeamsSummary> {
  const summary: TeamsSummary = { ran: false, made: 0, removed: 0, problems: [] };
  const config = graphConfig();
  if (!config) return summary;
  const db = createAdminClient();

  // Skips if another run started in the last few minutes (or Teams links
  // are switched off). The admin button only waits 10 seconds.
  const started = await db.rpc("teams_start_run", { p_gap: options.force ? "10 seconds" : "5 minutes" });
  if (started.error) {
    summary.problems.push(`Starting: ${started.error.message}`);
    return summary;
  }
  if (!started.data) return summary;
  summary.ran = true;

  // Deletions first, so a cancelled session's link stops working quickly.
  const removals = await db.rpc("teams_claim_removals", { p_limit: 50 });
  if (removals.error) summary.problems.push(`Finding meetings to delete: ${removals.error.message}`);
  for (const r of (removals.data ?? []) as { meeting_id: string; graph_meeting_id: string | null; organiser_email: string | null }[]) {
    try {
      if (r.graph_meeting_id && r.organiser_email) await deleteMeeting(config, r.organiser_email, r.graph_meeting_id);
      const done = await db.rpc("teams_record_removed", { p_meeting: r.meeting_id });
      if (done.error) summary.problems.push(`Recording a deletion: ${done.error.message}`);
      else summary.removed++;
    } catch (e) {
      const message = e instanceof GraphError ? e.message : "Deleting a meeting: something went wrong.";
      summary.problems.push(message);
      await db.rpc("teams_record_failed", { p_meeting: r.meeting_id, p_error: message });
    }
  }

  const claims = await db.rpc("teams_claim_sessions", { p_limit: 20 });
  if (claims.error) summary.problems.push(`Finding sessions: ${claims.error.message}`);
  for (const c of (claims.data ?? []) as {
    meeting_id: string;
    organiser_email: string;
    subject: string;
    starts_at: string;
    ends_at: string;
  }[]) {
    try {
      const made = await createMeeting(config, c.organiser_email, {
        subject: c.subject,
        startsAt: c.starts_at,
        endsAt: c.ends_at,
      });
      const saved = await db.rpc("teams_record_made", { p_meeting: c.meeting_id, p_graph_id: made.id, p_join_url: made.joinUrl });
      if (saved.error) summary.problems.push(`Saving a link: ${saved.error.message}`);
      else summary.made++;
    } catch (e) {
      const message = e instanceof GraphError ? e.message : "Making a meeting: something went wrong.";
      summary.problems.push(message);
      await db.rpc("teams_record_failed", { p_meeting: c.meeting_id, p_error: message });
      // The same sign-in or permission problem would hit every session.
      if (/sign-in|access policy|refused|organiser account/.test(message)) break;
    }
  }
  return summary;
}

// For pages and actions: runs the job after the response, never failing
// the page if Microsoft is slow or down.
export async function runTeamsSyncQuietly(): Promise<void> {
  try {
    const s = await runTeamsSync();
    if (s.problems.length) console.error("Teams links problems:", s.problems);
  } catch (e) {
    console.error("Teams links job failed:", e);
  }
}
