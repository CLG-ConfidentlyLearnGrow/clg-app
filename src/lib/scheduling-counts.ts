import type { createClient } from "@/lib/supabase/server";

type Client = Awaited<ReturnType<typeof createClient>>;

// Numbers for tabs that need action (Carla, 11 Nov 2026): "matching" for
// CLG admins, "libraries" for owner and operations admins, and
// "booking-length" for families. Missing keys mean nothing to do.
export async function schedulingCounts(supabase: Client): Promise<Record<string, number>> {
  const { data } = await supabase.rpc("scheduling_counts");
  const out: Record<string, number> = {};
  for (const row of (data ?? []) as { key: string; n: number }[]) out[row.key] = row.n;
  return out;
}
