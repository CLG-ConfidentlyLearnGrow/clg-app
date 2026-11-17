// Summary: a card at the top of the tutor and admin dashboards while a staff
// member has an employment contract to sign or finish (Carla, 17 Nov 2026).
// It disappears once the contract is complete or withdrawn.
// See docs/features/employment-contracts.md.
//
import { TextLink } from "@/components/ui"; // A link styled like the rest of the app.
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import { contractHref } from "@/lib/employment-contracts"; // The contract page address.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Shows the card on tutor and admin dashboards when a contract is waiting.
export async function ContractPrompt({ role }: { role: Role }) { // Takes the dashboard.
  if (role !== "tutor" && role !== "admin") return null; // Only staff dashboards show it.
  const supabase = await createClient(); // Connects to the database.
  const { data: me } = await supabase.auth.getUser(); // Who is signed in.
  if (!me.user) return null; // Nobody: nothing to show.
  const { data } = await supabase // Reads their newest waiting contract:
    .from("employment_contracts") // from the contracts table,
    .select("id, title, status") // its id, title and status,
    .eq("account_id", me.user.id) // their own,
    .in("status", ["sent", "signed"]) // waiting to be signed or finished,
    .order("sent_at", { ascending: false }) // newest first,
    .limit(1) // just one,
    .maybeSingle(); // (or none).
  if (!data) return null; // None waiting (or a problem reading it): shows nothing, so the dashboard still works.
  return ( // Shows:
    <div className="mb-6 rounded-2xl border border-brand/40 bg-brand/5 px-5 py-4 text-sm">{/* a bronze-edged card above the page: */}
      <p className="font-semibold">{data.status === "sent" ? "Your employment contract is ready to sign" : "Please finish your contract acknowledgements"}</p>{/* what is needed, */}
      <p className="mt-1">{data.title}. <TextLink href={`${contractHref(data.id as string)}&as=${role}`}>{data.status === "sent" ? "Read and sign it" : "Finish now"}</TextLink></p>{/* the contract and a link to it. */}
    </div> // End of the card.
  ); // End of what's shown.
} // End of ContractPrompt.
