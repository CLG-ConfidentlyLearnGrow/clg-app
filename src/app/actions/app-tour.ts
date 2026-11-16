// Summary: the server action for the first-time app tour (Carla, 16 Nov
// 2026). The tour calls it when someone moves through it, closes it or
// finishes it, so it doesn't open by itself again and "Carry on the tour"
// can start where they left off. The database checks again that the tour
// belongs to one of the person's own dashboards.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { z } from "zod"; // The form-checking library.
import { GUIDE_IDS } from "@/lib/app-guides"; // The tour ids (tours share the App guide ids).
import { TOUR_VERSIONS } from "@/lib/app-tours"; // Each tour's current edition.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The rules for what the tour sends.
const schema = z.object({ // The tour sends:
  tour: z.enum(GUIDE_IDS), // which tour (only a real one),
  step: z.number().int().min(0).max(100), // the step reached (0 is the welcome),
  finished: z.boolean(), // and whether they reached the end.
}); // End of the rules.

// Saves how far the signed-in person got in one of their tours. It never
// throws: if saving fails, the worst case is the tour opens again next time.
export async function saveTourProgress(tour: string, step: number, finished: boolean): Promise<void> { // Takes the tour, step and whether it's finished.
  const parsed = schema.safeParse({ tour, step, finished }); // Checks what was sent.
  if (!parsed.success) return; // Not valid: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("app_tour_save", { // Saves it (the database checks it's their own dashboard's tour):
    p_tour: parsed.data.tour, // which tour,
    p_version: TOUR_VERSIONS[parsed.data.tour], // the edition they saw (always the current one),
    p_step: parsed.data.step, // the step reached,
    p_finished: parsed.data.finished, // and whether they finished.
  }); // End of the save.
} // End of saveTourProgress.
