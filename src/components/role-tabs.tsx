// Summary: the tabs across the top for each dashboard a person can use.
//
import Link from "next/link"; // Links between pages without a full reload.
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import { ROLE_ORDER, ROLE_TABS } from "@/lib/roles"; // The order of the tabs, and each tab's name and address.
import { ROLE_THEME } from "@/lib/role-theme"; // Each role's colours.
import { getToDoCounts } from "@/lib/to-do-counts"; // Reads the to-do numbers.
import { CountBadge } from "@/components/count-badge"; // The small number badge.

// Tabs across the top for each dashboard this person can use. Hidden when
// they have only one. Each tab has its dashboard's colour; the open one is
// shaded in that colour. A number on a tab shows how many things need doing
// in that dashboard.
export async function RoleTabs({ roles, active }: { roles: Role[]; active: Role }) { // The tabs: takes the person's roles and the open dashboard.
  const mine = ROLE_ORDER.filter((r) => roles.includes(r)); // The person's roles, in tab order.
  if (mine.length < 2) return null; // Only one dashboard: shows no tabs.
  const todo = await getToDoCounts(roles); // The to-do numbers for this person.
  return ( // Shows:
    <div className="border-b border-zinc-200 bg-white/60">{/* a band with a line underneath, */}
      <nav aria-label="Your dashboards" className="mx-auto grid w-full max-w-6xl auto-cols-fr grid-flow-col px-2 sm:flex sm:gap-1 sm:px-4">{/* the row of tabs (read aloud as "Your dashboards"): */}
        {mine.map((r) => { // for each of the person's roles:
          const isActive = r === active; // true if it's the open dashboard,
          const theme = ROLE_THEME[r]; // its colours,
          return ( // shows:
            <Link // a link:
              key={r} // (one per role)
              href={ROLE_TABS[r].href} // to that dashboard,
              aria-current={isActive ? "page" : undefined} // marked as the current page if open,
              className={`-mb-px flex items-center justify-center gap-2 border-b-4 px-2 py-3 text-sm font-medium transition sm:rounded-t-lg sm:px-4 ${ // styled as a tab, with:
                isActive // if it's open,
                  ? `${theme.accentBorder} ${theme.tintBg} ${theme.strongText}` // its colour underline, shading and text,
                  : "border-transparent text-zinc-600 hover:border-zinc-300 hover:text-zinc-800" // otherwise a plain tab that darkens on hover.
              }`} // (end of the style)
            >{/* (end of the settings) */}
              <span className={`h-2 w-2 shrink-0 rounded-full ${theme.accent}`} aria-hidden />{/* A small coloured dot (hidden from screen readers), */}
              {ROLE_TABS[r].label}{/* the tab's name, */}
              <CountBadge n={todo.forRole(r)} className={`${theme.strongBg} text-white`} />{/* and its to-do number in the role's colour. */}
            </Link> // End of the link.
          ); // End of what's shown.
        })}{/* End of the tabs. */}
      </nav>{/* End of the row. */}
    </div> // End of the band.
  ); // End of what's shown.
} // End of RoleTabs.
