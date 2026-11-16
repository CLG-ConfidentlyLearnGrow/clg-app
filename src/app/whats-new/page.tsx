// Summary: the "What's new" page (Carla, 15 Nov 2026). Every update for the
// signed-in person's dashboards, newest first, so they can read again
// anything they closed in the pop-up. Someone with several roles sees one
// part per dashboard. The database only gives back changes for their own
// dashboards.
//
import { Card, Empty, Page } from "@/components/ui"; // The card, "nothing yet" note and page frame.
import { requireViewer, type Role } from "@/lib/auth"; // Makes sure someone is signed in, and the role type.
import { plainDate } from "@/lib/privacy"; // Dates in words.
import { ROLE_THEME } from "@/lib/role-theme"; // Each dashboard's colours and name.
import { ROLE_ORDER } from "@/lib/roles"; // The usual order of dashboards.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { groupUpdates, WHATS_NEW_KINDS, type WhatsNewRow, type WhatsNewUpdate } from "@/lib/whats-new"; // Grouping, kind labels and shapes.

// Shows the page.
export default async function WhatsNewPage() { // The page itself.
  const viewer = await requireViewer(); // Makes sure someone is signed in.
  const supabase = await createClient(); // Connects to the database.
  const roles = ROLE_ORDER.filter((r) => viewer.roles.includes(r)); // Their dashboards, in the usual order.
  const lists: [Role, WhatsNewUpdate[]][] = await Promise.all( // Reads every dashboard's updates at once:
    roles.map(async (role): Promise<[Role, WhatsNewUpdate[]]> => { // for each dashboard:
      const { data } = await supabase.rpc("whats_new_for_me", { p_role: role, p_unseen_only: false }); // every update for it,
      return [role, groupUpdates((data ?? []) as WhatsNewRow[])]; // grouped into updates.
    }), // End of each dashboard.
  ); // End of the reads.

  return ( // Shows:
    <Page title="What is new" intro="Changes to the app for your dashboards, newest first.">{/* a page with a short explanation: */}
      {roles.length === 0 && <Empty>Your account has no dashboard yet.</Empty>}{/* No roles yet. */}
      {lists.map(([role, updates]) => ( // For each dashboard:
        <section key={role} id={role} className="scroll-mt-6 space-y-3">{/* a part (the pop-up's link jumps here): */}
          {roles.length > 1 && <h2 className={`text-lg font-semibold ${ROLE_THEME[role].strongText}`}>{ROLE_THEME[role].title}</h2>}{/* the dashboard's name, when they have more than one, */}
          {updates.length === 0 && <Empty>No updates yet.</Empty>}{/* "No updates yet" when there are none, */}
          {updates.map((u) => ( // then each update:
            <Card key={u.id} title={u.title} description={plainDate(u.showFrom)}>{/* a card with its title and date: */}
              <ul className="space-y-2">{/* its changes: */}
                {u.items.map((i) => ( // for each change:
                  <li key={i.id} className="flex items-start gap-2 text-sm">{/* a line: */}
                    <span className={`mt-0.5 shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold ${WHATS_NEW_KINDS[i.kind]?.className ?? ""}`}>{WHATS_NEW_KINDS[i.kind]?.label ?? i.kind}</span>{/* New, Updated or Removed, */}
                    <span className="whitespace-pre-wrap">{i.body}</span>{/* and what changed. */}
                  </li> // End of the line.
                ))}{/* End of the changes. */}
              </ul>{/* End of the list. */}
            </Card> // End of the card.
          ))}{/* End of the updates. */}
        </section> // End of the part.
      ))}{/* End of the dashboards. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of WhatsNewPage.
