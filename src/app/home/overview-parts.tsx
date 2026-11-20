// Summary: the building blocks of every Overview page: a row of quick-look
// tiles, the "Needs your attention" list, and the "Coming up" list of
// sessions. Each dashboard's Overview (in page.tsx) fills them with its own
// information, so all four look and read the same way.
//
import Link from "next/link"; // Links between pages without a full reload.
import type { ReactNode } from "react"; // The type for "anything that can be shown".
import { Card, Empty, TextLink } from "@/components/ui"; // Shared page parts: a card, an empty-state line and a text link.
import { CountBadge } from "@/components/count-badge"; // The small number in a circle.
import type { Role } from "@/lib/auth"; // The type for a role (for type checking only).
import { ROLE_THEME } from "@/lib/role-theme"; // Each dashboard's colours.
import { placeLabel, sessionWhen } from "@/lib/scheduling"; // Where a session is, in words, and when, in words.
import type { AttentionLine, OverviewSession } from "@/lib/home-overview"; // The shapes of an attention line and a session (for type checking only).

// One quick-look tile: a big number or short phrase, what it means, and
// (optionally) where to go to see more.
export type Tile = { // Each tile has:
  label: string; // what it is about (small words on top),
  value: string; // the big number or short phrase,
  note?: string; // an extra line under it (optional),
  href?: string; // the page to open when tapped (optional),
  warn?: boolean; // whether it needs action (shown in amber).
}; // End of Tile.

// A row of quick-look tiles: two across on a phone, up to four on a computer.
export function Tiles({ tiles, role }: { tiles: Tile[]; role: Role }) { // Takes the tiles and the dashboard (for its colour).
  if (tiles.length === 0) return null; // No tiles: shows nothing.
  const theme = ROLE_THEME[role]; // The dashboard's colours.
  return ( // Shows:
    <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">{/* a grid of tiles: */}
      {tiles.map((t) => { // for each tile:
        const look = `block h-full rounded-2xl border bg-white p-4 shadow-sm ${t.warn ? "border-amber-300 bg-amber-50" : "border-zinc-200/80"} border-t-4 ${t.warn ? "border-t-amber-400" : theme.accentTopBorder}`; // a white box with the dashboard's colour along the top (amber when it needs action),
        const inside = ( // what is inside the tile:
          <>{/* (a group) */}
            <span className="block text-xs font-medium uppercase tracking-wide text-zinc-500">{t.label}</span>{/* the small label, */}
            <span className={`mt-1 block text-2xl font-semibold leading-tight ${t.warn ? "text-amber-900" : theme.strongText}`}>{t.value}</span>{/* the big number or phrase, */}
            {t.note && <span className="mt-1 block text-sm text-zinc-600">{t.note}</span>}{/* and the extra line, if any. */}
          </> // End of the group.
        ); // End of what is inside.
        return t.href ? ( // A tile that opens a page:
          <Link key={t.label} href={t.href} className={`${look} transition hover:shadow-md`}>{inside}</Link> // is a link (with a stronger shadow on hover),
        ) : ( // otherwise:
          <div key={t.label} className={look}>{inside}</div> // a plain box.
        ); // End of this tile.
      })}{/* End of the tiles. */}
    </div> // End of the grid.
  ); // End of what is shown.
} // End of Tiles.

// The "Needs your attention" card: one line per page with something
// waiting, or "All caught up" when there is nothing.
export function AttentionCard({ lines }: { lines: AttentionLine[] }) { // Takes the lines.
  return ( // Shows:
    <Card title="Needs your attention" description={lines.length ? "Tap a line to go straight to it." : undefined}>{/* a card (with a hint when there are lines): */}
      {lines.length === 0 ? ( // Nothing waiting:
        <Empty>All caught up. Nothing needs you right now.</Empty> // a friendly line.
      ) : ( // Otherwise:
        <ul className="divide-y divide-zinc-100">{/* a list: */}
          {lines.map((l) => ( // for each line:
            <li key={l.id}>{/* a row: */}
              <Link href={l.href} className="flex items-start gap-3 py-3 text-sm first:pt-0 hover:bg-zinc-50">{/* the whole row is a link: */}
                <CountBadge n={l.count} className={l.urgent ? "mt-0.5 bg-red-700 text-white" : "mt-0.5 bg-zinc-700 text-white"} />{/* the number (red for child safety), */}
                <span className="min-w-0">{/* the words: */}
                  <span className={`block font-medium underline-offset-2 hover:underline ${l.urgent ? "text-red-800" : "text-zinc-900"}`}>{l.label}</span>{/* the page's name, */}
                  <span className="block text-zinc-600">{l.detail}</span>{/* and what is waiting there. */}
                </span>{/* End of the words. */}
              </Link>{/* End of the link. */}
            </li> // End of the row.
          ))}{/* End of the lines. */}
        </ul> // End of the list.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what is shown.
} // End of AttentionCard.

// The "Coming up" card: the next sessions, each with when, who, what and
// where, and a link to Sessions for the rest. "show" picks which names to
// show: the student's (tutors and parents), the tutor's (parents and
// students), or both.
export function ComingUpCard({ // The card, given:
  sessions, // The sessions to list (already only this dashboard's own, soonest first).
  show, // Which names to show.
  sessionsHref, // The address of this dashboard's Sessions page.
  empty, // The words to show when there are none.
}: { // The settings' types:
  sessions: OverviewSession[]; // a list of sessions,
  show: "student" | "tutor" | "both"; // one of three choices,
  sessionsHref: string; // an address,
  empty: ReactNode; // anything that can be shown.
}) { // End of the settings.
  const first = (name: string) => name.trim().split(/\s+/)[0] ?? name; // A person's first name.
  const list = sessions.slice(0, 5); // The next 5 at most, so the card stays short.
  return ( // Shows:
    <Card title="Coming up" description="Your next sessions in the coming week.">{/* a card: */}
      {list.length === 0 ? ( // None:
        <Empty>{empty}</Empty> // the empty words.
      ) : ( // Otherwise:
        <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
          {list.map((s) => ( // for each session:
            <li key={s.id} className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 py-2.5 first:pt-0 last:pb-0">{/* a row: */}
              <span className="font-medium">{sessionWhen(s.starts_at)}</span>{/* when it starts, */}
              <span className="text-zinc-700">{/* then: */}
                {show !== "tutor" && `${s.student_name} · `}{/* the student's name (when shown), */}
                {s.subject}{/* the subject, */}
                {show !== "student" && ` with ${first(s.tutor_name)}`}{/* the tutor's first name (when shown), */}
                {` · ${placeLabel(s.delivery, s.library_name)}`}{/* and where. */}
              </span>{/* End of the details. */}
            </li> // End of the row.
          ))}{/* End of the sessions. */}
        </ul> // End of the list.
      )}{/* End of this part. */}
      <p className="mt-4 text-sm">{/* a line under the list: */}
        <TextLink href={sessionsHref}>Open Sessions</TextLink> for every booking, cancellations and away dates.{/* where to see and change everything. */}
      </p>{/* End of the line. */}
    </Card> // End of the card.
  ); // End of what is shown.
} // End of ComingUpCard.
