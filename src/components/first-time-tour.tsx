// Summary: decides whether the first-time app tour should open on a
// dashboard (Carla, 16 Nov 2026). The dashboard frame calls this on every
// dashboard page. The tour opens when the person has never seen this
// dashboard's tour (or has only seen an older edition of it). Admins get the
// tour for their own admin level. If the lookup fails (for example before
// the database change has been run), no tour opens, so the page always
// works.
//
import type { ReactNode } from "react"; // The type for "anything that can be shown".
import { AppTour } from "@/components/app-tour"; // The tour pop-up itself.
import { getAdminLevel, type Role } from "@/lib/auth"; // The admin level reader, and the role type.
import { ownGuide } from "@/lib/app-guides"; // Picks the guide (and so the tour) for a dashboard.
import { TOUR_VERSIONS, getTour } from "@/lib/app-tours"; // Each tour's edition, and the tours.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Gives back the tour pop-up if this dashboard's tour should open now, or
// nothing. The frame uses "nothing" to know it can show "What's new"
// instead (so two pop-ups never open at once).
export async function firstTimeTour(role: Role): Promise<ReactNode | null> { // Takes the dashboard.
  const level = role === "admin" ? await getAdminLevel() : null; // The admin level, on the admin dashboard.
  const id = ownGuide(role, level); // This dashboard's tour (none for an admin without a level).
  if (!id) return null; // No tour: nothing to show.
  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase.from("app_tour_progress").select("version").eq("tour", id).maybeSingle(); // Their saved progress for this tour (the database only gives back their own).
  if (error) return null; // The lookup failed: no tour this time.
  if (data && Number(data.version) >= TOUR_VERSIONS[id]) return null; // Already seen this edition: no tour.
  return <AppTour tour={getTour(id)} role={role} save autoOpen />; // Not seen yet: the tour, opening by itself.
} // End of firstTimeTour.
