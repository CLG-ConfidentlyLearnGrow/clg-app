import { isCronRequest } from "@/lib/cron-auth";
import { createAdminClient } from "@/lib/supabase/admin";

// The daily progress tidy-up, called by Vercel's scheduler (see vercel.json).
// Removes the files of uploads that were deleted (by the family, or with the
// student). Files can only be deleted through the file store, so the
// database queues them and this job removes them.
export async function GET(request: Request) {
  if (!isCronRequest(request)) {
    return new Response("Not allowed", { status: 401 });
  }
  const supabase = createAdminClient();
  const queued = await supabase.rpc("evidence_files_to_remove");
  if (queued.error) {
    console.error("Evidence file removal:", queued.error.message);
    return Response.json({ removed: 0, problem: "Couldn't read the removal list" }, { status: 500 });
  }
  const paths = (queued.data ?? []) as string[];
  if (paths.length === 0) return Response.json({ removed: 0 });

  // Removing a file that is already gone is not an error, so clear them all.
  const removed = await supabase.storage.from("learning-evidence").remove(paths);
  if (removed.error) {
    console.error("Evidence file removal:", removed.error.message);
    return Response.json({ removed: 0, problem: "Couldn't remove the files" }, { status: 500 });
  }
  await supabase.rpc("evidence_files_removed", { p_paths: paths });
  return Response.json({ removed: paths.length });
}
