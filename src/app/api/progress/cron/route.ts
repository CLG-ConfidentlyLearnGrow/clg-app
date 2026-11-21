// Summary: the daily job that removes files of deleted progress uploads and
// deleted session files.
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
  // Uploaded evidence first, then session files (Carla, 21 Nov 2026). Each
  // has its own file store and its own list of files waiting to go.
  const evidence = await removeQueued(supabase, "evidence_files_to_remove", "evidence_files_removed", "learning-evidence"); // Removes deleted evidence files.
  const sessionFiles = await removeQueued(supabase, "session_files_to_remove", "session_files_removed", "session-files"); // Removes deleted session files.
  const problem = evidence.problem ?? sessionFiles.problem; // The first problem, if any.
  return Response.json( // Reports:
    { removed: evidence.removed + sessionFiles.removed, ...(problem ? { problem } : {}) }, // how many were removed, and any problem,
    { status: problem ? 500 : 200 }, // with a failure status if there was a problem.
  ); // End of the report.
} // End of GET.

// Removes the files waiting in one queue from one file store, then tells
// the database they are gone. Gives back how many and any problem.
async function removeQueued( // Takes:
  supabase: ReturnType<typeof createAdminClient>, // the full-access connection,
  listFn: "evidence_files_to_remove" | "session_files_to_remove", // the database function that lists the queue,
  doneFn: "evidence_files_removed" | "session_files_removed", // the one that clears it,
  bucket: "learning-evidence" | "session-files", // and the file store.
): Promise<{ removed: number; problem?: string }> { // Gives back the count and any problem.
  const queued = await supabase.rpc(listFn); // Gets the list of files waiting to be removed.
  if (queued.error) { // Could not get it:
    console.error(`File removal (${bucket}):`, queued.error.message); // notes why in the server log,
    return { removed: 0, problem: "Could not read the removal list" }; // and reports the problem.
  } // End of the failure case.
  const paths = (queued.data ?? []) as string[]; // The file paths.
  if (paths.length === 0) return { removed: 0 }; // None: nothing removed.
  // Removing a file that is already gone is not an error, so clear them all.
  const removed = await supabase.storage.from(bucket).remove(paths); // Removes the files.
  if (removed.error) { // Could not remove them:
    console.error(`File removal (${bucket}):`, removed.error.message); // notes why in the server log,
    return { removed: 0, problem: "Could not remove the files" }; // and reports the problem.
  } // End of the failure case.
  await supabase.rpc(doneFn, { p_paths: paths }); // Tells the database these files are gone.
  return { removed: paths.length }; // Reports how many were removed.
} // End of removeQueued.
