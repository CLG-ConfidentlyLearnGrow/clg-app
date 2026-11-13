// Summary: the daily job that tidies problem reports: it removes screenshots
// 90 days after a report is fixed or closed, reports 2 years after that, and
// screenshot files left behind by a report that never finished sending.
//
import { isCronRequest } from "@/lib/cron-auth"; // Checks the request really comes from the scheduler.
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).

// The daily problem reports tidy-up, called by Vercel's scheduler (see
// vercel.json). The database removes old records and queues their files;
// files can only be deleted through the file store, so this job removes them.
export async function GET(request: Request) {
  if (!isCronRequest(request)) { // Not from the scheduler:
    return new Response("Not allowed", { status: 401 }); // refuses it.
  } // End of the check.
  const supabase = createAdminClient(); // Connects with full access.
  const tidy = await supabase.rpc("problem_reports_tidy"); // Removes old screenshots and reports, and queues their files.
  if (tidy.error) console.error("Problem reports tidy-up:", tidy.error.message); // Couldn't: notes why in the server log (and still clears the queue below).

  const queued = await supabase.rpc("problem_screenshots_to_remove"); // Gets the files waiting to be removed.
  if (queued.error) { // Couldn't get them:
    console.error("Problem screenshot removal:", queued.error.message); // notes why in the server log,
    return Response.json({ removed: 0, problem: "Couldn't read the removal list" }, { status: 500 }); // and reports the problem.
  } // End of the failure case.
  const paths = (queued.data ?? []) as string[]; // The file paths.
  if (paths.length === 0) return Response.json({ records: tidy.data ?? 0, removed: 0 }); // None: reports nothing removed.

  // Removing a file that is already gone is not an error, so clear them all.
  const removed = await supabase.storage.from("problem-screenshots").remove(paths); // Removes the files.
  if (removed.error) { // Couldn't remove them:
    console.error("Problem screenshot removal:", removed.error.message); // notes why in the server log,
    return Response.json({ removed: 0, problem: "Couldn't remove the files" }, { status: 500 }); // and reports the problem.
  } // End of the failure case.
  await supabase.rpc("problem_screenshots_removed", { p_paths: paths }); // Tells the database these files are gone.
  return Response.json({ records: tidy.data ?? 0, removed: paths.length }); // Reports what was removed.
} // End of GET.
