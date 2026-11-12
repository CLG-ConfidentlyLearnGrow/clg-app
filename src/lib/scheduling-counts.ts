// Summary: reads the scheduling to-do numbers from the database.
//
import type { createClient } from "@/lib/supabase/server"; // The type of a database connection (for type checking only).

type Client = Awaited<ReturnType<typeof createClient>>; // The shape of a database connection.

// Numbers for tabs that need action (Carla, 11 Nov 2026): "matching" for
// CLG admins, "libraries" for owner and operations admins, and
// "booking-length" for families. Missing keys mean nothing to do.
export async function schedulingCounts(supabase: Client): Promise<Record<string, number>> { // Gets the numbers, given a database connection.
  const { data } = await supabase.rpc("scheduling_counts"); // Asks the database for the scheduling numbers.
  const out: Record<string, number> = {}; // The numbers by name, starting empty.
  for (const row of (data ?? []) as { key: string; n: number }[]) out[row.key] = row.n; // Puts each row's number under its name.
  return out; // Hands them back.
} // End of schedulingCounts.
