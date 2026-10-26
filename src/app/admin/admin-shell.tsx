"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";

type Section = { id: string; label: string; count?: number };

// Admin layout: a menu of sections that can be hidden to give the page more
// room. On phones the menu opens from a button at the top.
export function AdminShell({
  section,
  sections,
  children,
}: {
  section: string;
  sections: Section[];
  children: ReactNode;
}) {
  const [open, setOpen] = useState(true);
  const [phoneOpen, setPhoneOpen] = useState(false);

  function toggle() {
    setOpen((was) => !was);
  }

  const current = sections.find((s) => s.id === section);

  const links = (
    <nav aria-label="Admin sections">
      <ul className="space-y-1">
        {sections.map((s) => {
          const active = s.id === section;
          return (
            <li key={s.id}>
              <Link
                href={`/admin?section=${s.id}`}
                onClick={() => setPhoneOpen(false)}
                aria-current={active ? "page" : undefined}
                className={`flex items-center justify-between gap-2 rounded-md px-3 py-2 text-sm ${
                  active ? "bg-teal-700 font-medium text-white" : "text-zinc-800 hover:bg-teal-100"
                }`}
              >
                <span>{s.label}</span>
                {s.count ? (
                  <span
                    className={`rounded-full px-2 text-xs ${active ? "bg-white text-teal-800" : "bg-teal-500 text-white"}`}
                  >
                    {s.count}
                  </span>
                ) : null}
              </Link>
            </li>
          );
        })}
      </ul>
      <p className="mt-4 border-t border-zinc-200 px-3 pt-3 text-sm">
        <Link href="/dashboard" className="text-teal-700 underline">
          Back to dashboard
        </Link>
      </p>
    </nav>
  );

  return (
    <div className="mx-auto flex w-full max-w-6xl gap-6 px-4 py-8">
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
          {open && <div className="rounded-lg border border-zinc-200 bg-white p-2 shadow-sm">{links}</div>}
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
              Admin menu: <strong>{current?.label}</strong>
            </span>
            <span aria-hidden>{phoneOpen ? "▲" : "▼"}</span>
          </button>
          {phoneOpen && <div className="mt-2 rounded-lg border border-zinc-200 bg-white p-2 shadow-sm">{links}</div>}
        </div>

        <h1 className="mb-6 text-2xl font-semibold">{current?.label ?? "Admin"}</h1>
        <div className="space-y-6">{children}</div>
      </div>
    </div>
  );
}
