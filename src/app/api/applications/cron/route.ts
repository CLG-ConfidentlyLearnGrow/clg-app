// Summary: the daily job that tidies tutor applications: it deletes
// applications past their keeping period (declined or withdrawn: 12 months
// after the decision; never decided: 12 months after sending; approved: 7
// years), removes their CVs from the file store, and clears old scrambled
// internet addresses. See docs/features/tutor-applications.md.
//
import { isCronRequest } from "@/lib/cron-auth"; // Checks the request really comes from the scheduler.
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).

// The daily tidy-up, called by Vercel's scheduler (see vercel.json). The
// database deletes old applications and queues their CVs; files can only be
// deleted through the file store, so this job removes them.
export async function GET(request: Request) {
  if (!isCronRequest(request)) { // Not from the scheduler:
    return new Response("Not allowed", { status: 401 }); // refuses it.
  } // End of the check.
  const supabase = createAdminClient(); // Connects with full access.
  const tidy = await supabase.rpc("tutor_applications_tidy"); // Deletes old applications and queues their CVs.
  if (tidy.error) console.error("Tutor applications tidy-up:", tidy.error.message); // Couldn't: notes why in the server log (and still clears the queue below).

  const queued = await supabase.rpc("tutor_application_files_to_remove"); // Gets the CVs waiting to be removed.
  if (queued.error) { // Couldn't get them:
    console.error("Tutor application CV removal:", queued.error.message); // notes why in the server log,
    return Response.json({ removed: 0, problem: "Could not read the removal list" }, { status: 500 }); // and reports the problem.
  } // End of the failure case.
  const paths = (queued.data ?? []) as string[]; // The file paths.
  if (paths.length === 0) return Response.json({ records: tidy.data ?? 0, removed: 0 }); // None: reports nothing removed.

  // Removing a file that is already gone is not an error, so clear them all.
  const removed = await supabase.storage.from("tutor-applications").remove(paths); // Removes the CVs.
  if (removed.error) { // Couldn't remove them:
    console.error("Tutor application CV removal:", removed.error.message); // notes why in the server log,
    return Response.json({ removed: 0, problem: "Could not remove the files" }, { status: 500 }); // and reports the problem.
  } // End of the failure case.
  await supabase.rpc("tutor_application_files_removed", { p_paths: paths }); // Tells the database these files are gone.
  return Response.json({ records: tidy.data ?? 0, removed: paths.length }); // Reports what was removed.
} // End of GET.
