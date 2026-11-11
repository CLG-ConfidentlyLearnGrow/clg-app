"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { PageTitle } from "@/components/ui";
import type { Role } from "@/lib/auth";
import { ROLE_THEME } from "@/lib/role-theme";

type Section = { id: string; label: string; count?: number };

// Dashboard layout: side headings for each section, which can be hidden to
// give the page more room. On phones the menu opens from a button at the top.
// "role" colours the menu and heading in that dashboard's colour.
export function SectionShell({
  basePath,
  label,
  role,
  section,
  sections,
  children,
}: {
  basePath: string;
  label: string;
  role?: Role;
  section: string;
  sections: Section[];
  children: ReactNode;
}) {
  const theme = role ? ROLE_THEME[role] : null;
  const activeItem = theme ? `${theme.strongBg} font-medium text-white` : "bg-teal-700 font-medium text-white";
  const idleItem = `text-zinc-800 ${theme ? theme.hoverTint : "hover:bg-teal-100"}`;
  const activeCount = `bg-white ${theme ? theme.strongText : "text-teal-800"}`;
  const idleCount = `${theme ? theme.strongBg : "bg-teal-500"} text-white`;
  const menuBox = `rounded-2xl border border-zinc-200 bg-white p-2 shadow-sm ${theme ? `border-t-4 ${theme.accentTopBorder}` : ""}`;
  const [open, setOpen] = useState(true);
  const [phoneOpen, setPhoneOpen] = useState(false);

  function toggle() {
    setOpen((was) => !was);
  }

  const current = sections.find((s) => s.id === section);

  const links = (
    <nav aria-label={`${label} sections`}>
      <ul className="space-y-1">
        {sections.map((s) => {
          const active = s.id === section;
          return (
            <li key={s.id}>
              <Link
                href={`${basePath}?section=${s.id}`}
                onClick={() => setPhoneOpen(false)}
                aria-current={active ? "page" : undefined}
                className={`flex items-center justify-between gap-2 rounded-md px-3 py-2 text-sm ${
                  active ? activeItem : idleItem
                }`}
              >
                <span>{s.label}</span>
                {s.count ? (
                  <span
                    className={`rounded-full px-2 text-xs ${active ? activeCount : idleCount}`}
                  >
                    {s.count}
                  </span>
                ) : null}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );

  return (
    <div className="mx-auto flex w-full max-w-6xl gap-6 px-4 py-6 sm:py-8">
      {/* Computers and tablets: side menu that can be hidden */}
      <aside className={`hidden shrink-0 md:block ${open ? "w-60" : "w-10"}`}>
        <div className="sticky top-4">
          <button
            type="button"
            onClick={toggle}
            aria-expanded={open}
            className="mb-3 flex h-9 items-center gap-2 rounded-md border border-zinc-300 bg-white px-3 text-sm hover:bg-teal-50"
            title={open ? "Hide menu" : "Show menu"}
          >
            <span aria-hidden>{open ? "«" : "»"}</span>
            {open && <span>Hide menu</span>}
            {!open && <span className="sr-only">Show menu</span>}
          </button>
          {open && <div className={menuBox}>{links}</div>}
        </div>
      </aside>

      <div className="min-w-0 flex-1">
        {/* Phones: menu button that opens the list */}
        <div className="mb-4 md:hidden">
          <button
            type="button"
            onClick={() => setPhoneOpen((v) => !v)}
            aria-expanded={phoneOpen}
            className="flex w-full items-center justify-between rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm"
          >
            <span>
              {label} menu: <strong>{current?.label}</strong>
            </span>
            <span aria-hidden>{phoneOpen ? "▲" : "▼"}</span>
          </button>
          {phoneOpen && <div className={`mt-2 ${menuBox}`}>{links}</div>}
        </div>

        <PageTitle title={current?.label ?? label} role={role} />
        <div className="space-y-6">{children}</div>
      </div>
    </div>
  );
}
