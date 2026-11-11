// Summary: the tabs across the top for moving between a person's dashboards.
//
// The Next.js link, for moving between pages without a full reload.
import Link from "next/link";
// The list of role names, for type checking only.
import type { Role } from "@/lib/auth";
// The tab order and where each tab goes.
import { ROLE_ORDER, ROLE_TABS } from "@/lib/roles";
// The colours for each role.
import { ROLE_THEME } from "@/lib/role-theme";

// Tabs across the top for each dashboard this person can use. Hidden when
// they have only one. Each tab has its dashboard's colour; the open one is
// shaded in that colour.
export function RoleTabs({ roles, active }: { roles: Role[]; active: Role }) {
  const mine = ROLE_ORDER.filter((r) => roles.includes(r)); // This person's roles, in tab order.
  if (mine.length < 2) return null; // Only one role: no tabs needed.
  return ( // Shows:
    <div className="border-b border-zinc-200 bg-white/60">{/* a strip with a line under it, */}
      <nav aria-label="Your dashboards" className="mx-auto grid w-full max-w-6xl auto-cols-fr grid-flow-col px-2 sm:flex sm:gap-1 sm:px-4">{/* the tab row (named for screen readers), spread evenly on phones and in a row on bigger screens, */}
        {mine.map((r) => { // for each of their roles:
          const isActive = r === active; // whether this is the open dashboard,
          const theme = ROLE_THEME[r]; // and that role's colours.
          return ( // Shows:
            <Link // a link:
              key={r} // (React's id for the tab)
              href={ROLE_TABS[r].href} // to that dashboard,
              aria-current={isActive ? "page" : undefined} // telling screen readers it's the current page when open,
              className={`-mb-px flex items-center justify-center gap-2 border-b-4 px-2 py-3 text-sm font-medium transition sm:rounded-t-lg sm:px-4 ${ // with a bottom bar, and:
                isActive // when open,
                  ? `${theme.accentBorder} ${theme.tintBg} ${theme.strongText}` // the role's bar colour, pale background and deep text,
                  : "border-transparent text-zinc-600 hover:border-zinc-300 hover:text-zinc-800" // otherwise no bar colour and grey text, darker on hover.
              }`} // (end of the look)
            >{/* (end of the link's settings) */}
              <span className={`h-2 w-2 shrink-0 rounded-full ${theme.accent}`} aria-hidden />{/* A dot in the role's colour (hidden from screen readers). */}
              {ROLE_TABS[r].label}{/* The tab's words, e.g. "Parent". */}
            </Link> // End of the link.
          ); // End of what's shown for this tab.
        })}{/* End of the loop. */}
      </nav>{/* End of the tab row. */}
    </div> // End of the strip.
  ); // End of what's shown.
} // End of RoleTabs.
