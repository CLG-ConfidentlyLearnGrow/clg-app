import Link from "next/link";
import type { Role } from "@/lib/auth";
import { ROLE_ORDER, ROLE_TABS } from "@/lib/roles";

// Tabs across the top for each dashboard this person can use. Hidden when
// they have only one.
export function RoleTabs({ roles, active }: { roles: Role[]; active: Role }) {
  const mine = ROLE_ORDER.filter((r) => roles.includes(r));
  if (mine.length < 2) return null;
  return (
    <div className="border-b border-zinc-200 bg-white/60">
      <nav aria-label="Your dashboards" className="mx-auto flex w-full max-w-6xl gap-1 overflow-x-auto px-4">
        {mine.map((r) => {
          const isActive = r === active;
          return (
            <Link
              key={r}
              href={ROLE_TABS[r].href}
              aria-current={isActive ? "page" : undefined}
              className={`-mb-px border-b-2 px-4 py-3 text-sm font-medium whitespace-nowrap transition ${
                isActive
                  ? "border-brand text-teal-800"
                  : "border-transparent text-zinc-600 hover:border-zinc-300 hover:text-zinc-800"
              }`}
            >
              {ROLE_TABS[r].label}
            </Link>
          );
        })}
      </nav>
    </div>
  );
}
