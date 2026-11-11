// Summary: the Teams links job. Makes a meeting for each online session in
// the next few days and deletes meetings for sessions that were cancelled or
// have finished. The database decides which (see the Teams migration), so
// this is safe to call often: from the daily schedule, after bookings and
// cancellations, from the schedule page, and from the admin button.

// Stops this file ever being sent to the browser.
import "server-only";
// The all-powerful database helper, used because this runs as a background job.
import { createAdminClient } from "@/lib/supabase/admin";
// The Microsoft Teams helpers: error type, make a meeting, delete a meeting, read settings.
import { GraphError, createMeeting, deleteMeeting, graphConfig } from "./graph";

// What the job reports back: whether it ran, how many links were made and removed, and any problems.
export type TeamsSummary = { ran: boolean; made: number; removed: number; problems: string[] };

// Runs the Teams links job once. "force" lets the admin button run it again sooner.
export async function runTeamsSync(options: { force?: boolean } = {}): Promise<TeamsSummary> {
  const summary: TeamsSummary = { ran: false, made: 0, removed: 0, problems: [] }; // Starts with nothing done.
  const config = graphConfig(); // Reads the Microsoft settings.
  if (!config) return summary; // Teams isn't set up, so there's nothing to do.
  const db = createAdminClient(); // Connects to the database with full access.

  // Skips if another run started in the last few minutes (or Teams links
  // are switched off). The admin button only waits 10 seconds.
  const started = await db.rpc("teams_start_run", { p_gap: options.force ? "10 seconds" : "5 minutes" }); // Asks the database to start a run.
  if (started.error) { // The database refused with an error:
    summary.problems.push(`Starting: ${started.error.message}`); // notes it,
    return summary; // and stops.
  } // End of the start error check.
  if (!started.data) return summary; // Too soon after the last run (or switched off), so stops quietly.
  summary.ran = true; // Marks that the job is running.

  // Deletions first, so a cancelled session's link stops working quickly.
  const removals = await db.rpc("teams_claim_removals", { p_limit: 50 }); // Gets up to 50 meetings to delete.
  if (removals.error) summary.problems.push(`Finding meetings to delete: ${removals.error.message}`); // Notes any error.
  for (const r of (removals.data ?? []) as { meeting_id: string; graph_meeting_id: string | null; organiser_email: string | null }[]) { // Goes through each meeting to delete.
    try { // Talking to Microsoft could fail.
      if (r.graph_meeting_id && r.organiser_email) await deleteMeeting(config, r.organiser_email, r.graph_meeting_id); // Deletes it in Teams, if it was ever made.
      const done = await db.rpc("teams_record_removed", { p_meeting: r.meeting_id }); // Records the deletion in the database.
      if (done.error) summary.problems.push(`Recording a deletion: ${done.error.message}`); // Notes a save failure,
      else summary.removed++; // or counts it as removed.
    } catch (e) { // Something went wrong:
      const message = e instanceof GraphError ? e.message : "Deleting a meeting: something went wrong."; // uses Microsoft's plain message if there is one,
      summary.problems.push(message); // notes it,
      await db.rpc("teams_record_failed", { p_meeting: r.meeting_id, p_error: message }); // and records the failure so it's retried.
    } // End of the error handling.
  } // End of the deletions loop.

  const claims = await db.rpc("teams_claim_sessions", { p_limit: 20 }); // Gets up to 20 sessions needing a link.
  if (claims.error) summary.problems.push(`Finding sessions: ${claims.error.message}`); // Notes any error.
  for (const c of (claims.data ?? []) as { // Goes through each session, which has:
    meeting_id: string; // the meeting's id in the database,
    organiser_email: string; // the Microsoft account that owns the meeting,
    subject: string; // the meeting title,
    starts_at: string; // the start time,
    ends_at: string; // and the end time.
  }[]) { // End of the session shape.
    try { // Talking to Microsoft could fail.
      const made = await createMeeting(config, c.organiser_email, { // Makes the meeting in Teams:
        subject: c.subject, // with this title,
        startsAt: c.starts_at, // starting then,
        endsAt: c.ends_at, // and ending then.
      }); // End of making the meeting.
      const saved = await db.rpc("teams_record_made", { p_meeting: c.meeting_id, p_graph_id: made.id, p_join_url: made.joinUrl }); // Saves the join link.
      if (saved.error) summary.problems.push(`Saving a link: ${saved.error.message}`); // Notes a save failure,
      else summary.made++; // or counts it as made.
    } catch (e) { // Something went wrong:
      const message = e instanceof GraphError ? e.message : "Making a meeting: something went wrong."; // uses Microsoft's plain message if there is one,
      summary.problems.push(message); // notes it,
      await db.rpc("teams_record_failed", { p_meeting: c.meeting_id, p_error: message }); // and records the failure so it's retried.
      // The same sign-in or permission problem would hit every session.
      if (/sign-in|access policy|refused|organiser account/.test(message)) break; // So stops early rather than failing them all.
    } // End of the error handling.
  } // End of the sessions loop.
  return summary; // Reports what happened.
} // End of runTeamsSync.

// For pages and actions: runs the job after the response, never failing
// the page if Microsoft is slow or down.
export async function runTeamsSyncQuietly(): Promise<void> {
  try { // Anything going wrong is caught below.
    const s = await runTeamsSync(); // Runs the job.
    if (s.problems.length) console.error("Teams links problems:", s.problems); // Notes any problems in the server log.
  } catch (e) { // The job itself crashed:
    console.error("Teams links job failed:", e); // notes it in the server log, without bothering the person.
  } // End of the error handling.
} // End of runTeamsSyncQuietly.
