// Summary: looks up the "What's new" updates the signed-in person hasn't
// seen on one dashboard and, if there are any, shows the pop-up. Every
// dashboard page includes this through the dashboard frame. If the lookup
// fails, nothing is shown, so the page itself always works.
//
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { groupUpdates, type WhatsNewRow } from "@/lib/whats-new"; // Groups changes into updates, and the row shape.
import { WhatsNewPopup } from "@/components/whats-new-popup"; // The pop-up itself.

// Shows the pop-up for this dashboard when there's something new.
export async function WhatsNew({ role }: { role: Role }) { // Takes the dashboard.
  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase.rpc("whats_new_for_me", { p_role: role, p_unseen_only: true }); // Asks for this dashboard's unseen changes (the database only gives back their own).
  if (error || !data?.length) return null; // Nothing new (or the lookup failed): shows nothing.
  return <WhatsNewPopup role={role} updates={groupUpdates(data as WhatsNewRow[])} />; // Shows the pop-up with the updates.
} // End of WhatsNew.
