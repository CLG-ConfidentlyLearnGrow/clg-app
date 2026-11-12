// Summary: the daily job that removes files of deleted progress uploads.
//
import { isCronRequest } from "@/lib/cron-auth"; // Checks the request really comes from the scheduler.
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).

// The daily progress tidy-up, called by Vercel's scheduler (see vercel.json).
// Removes the files of uploads that were deleted (by the family, or with the
// student). Files can only be deleted through the file store, so the
// database queues them and this job removes them.
export async function GET(request: Request) {
  if (!isCronRequest(request)) { // Not from the scheduler:
    return new Response("Not allowed", { status: 401 }); // refuses it.
  } // End of the check.
  const supabase = createAdminClient(); // Connects with full access.
  const queued = await supabase.rpc("evidence_files_to_remove"); // Gets the list of files waiting to be removed.
  if (queued.error) { // Couldn't get it:
    console.error("Evidence file removal:", queued.error.message); // notes why in the server log,
    return Response.json({ removed: 0, problem: "Couldn't read the removal list" }, { status: 500 }); // and reports the problem.
  } // End of the failure case.
  const paths = (queued.data ?? []) as string[]; // The file paths.
  if (paths.length === 0) return Response.json({ removed: 0 }); // None: reports nothing removed.

  // Removing a file that is already gone is not an error, so clear them all.
  const removed = await supabase.storage.from("learning-evidence").remove(paths); // Removes the files.
  if (removed.error) { // Couldn't remove them:
    console.error("Evidence file removal:", removed.error.message); // notes why in the server log,
    return Response.json({ removed: 0, problem: "Couldn't remove the files" }, { status: 500 }); // and reports the problem.
  } // End of the failure case.
  await supabase.rpc("evidence_files_removed", { p_paths: paths }); // Tells the database these files are gone.
  return Response.json({ removed: paths.length }); // Reports how many were removed.
} // End of GET.
