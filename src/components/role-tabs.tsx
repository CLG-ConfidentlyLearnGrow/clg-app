import Link from "next/link";
import type { Role } from "@/lib/auth";
import { ROLE_ORDER, ROLE_TABS } from "@/lib/roles";
import { ROLE_THEME } from "@/lib/role-theme";
import { getToDoCounts } from "@/lib/to-do-counts";
import { CountBadge } from "@/components/count-badge";

// Tabs across the top for each dashboard this person can use. Hidden when
// they have only one. Each tab has its dashboard's colour; the open one is
// shaded in that colour. A number on a tab shows how many things need doing
// in that dashboard.
export async function RoleTabs({ roles, active }: { roles: Role[]; active: Role }) {
  const mine = ROLE_ORDER.filter((r) => roles.includes(r));
  if (mine.length < 2) return null;
  const todo = await getToDoCounts(roles);
  return (
    <div className="border-b border-zinc-200 bg-white/60">
      <nav aria-label="Your dashboards" className="mx-auto grid w-full max-w-6xl auto-cols-fr grid-flow-col px-2 sm:flex sm:gap-1 sm:px-4">
        {mine.map((r) => {
          const isActive = r === active;
          const theme = ROLE_THEME[r];
          return (
            <Link
              key={r}
              href={ROLE_TABS[r].href}
              aria-current={isActive ? "page" : undefined}
              className={`-mb-px flex items-center justify-center gap-2 border-b-4 px-2 py-3 text-sm font-medium transition sm:rounded-t-lg sm:px-4 ${
                isActive
                  ? `${theme.accentBorder} ${theme.tintBg} ${theme.strongText}`
                  : "border-transparent text-zinc-600 hover:border-zinc-300 hover:text-zinc-800"
              }`}
            >
              <span className={`h-2 w-2 shrink-0 rounded-full ${theme.accent}`} aria-hidden />
              {ROLE_TABS[r].label}
              <CountBadge n={todo.forRole(r)} className={`${theme.strongBg} text-white`} />
            </Link>
          );
        })}
      </nav>
    </div>
  );
}
