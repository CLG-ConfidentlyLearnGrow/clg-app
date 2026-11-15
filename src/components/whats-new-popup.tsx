// Summary: the "What's new" pop-up (Carla, 15 Nov 2026). It opens by itself
// when someone opens a dashboard that has updates they haven't seen, lists
// what was added, updated or removed in that dashboard, and closes with
// "Got it", the Escape key or the close button. Closing it tells the server,
// so it doesn't show again until the next update. It uses the browser's own
// dialog box, which keeps keyboard focus inside it and works with screen
// readers.
//
"use client"; // Marks this file as code that runs in the browser.

import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { useEffect, useRef } from "react"; // React helpers: run code after showing, and hold a reference to the dialog box.
import { markWhatsNewSeen } from "@/app/actions/whats-new"; // The server action that remembers the pop-up was closed.
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import { ROLE_THEME } from "@/lib/role-theme"; // Each dashboard's colours and name.
import { POPUP_MAX_UPDATES, WHATS_NEW_KINDS, type WhatsNewUpdate } from "@/lib/whats-new"; // The kind labels, the pop-up limit and the update shape.

// Shows the pop-up for one dashboard's unseen updates.
export function WhatsNewPopup({ role, updates }: { role: Role; updates: WhatsNewUpdate[] }) { // Takes the dashboard and its unseen updates.
  const dialog = useRef<HTMLDialogElement>(null); // The dialog box on the page.
  const saved = useRef(false); // Whether the close has already been sent (so it's only sent once).
  const theme = ROLE_THEME[role]; // This dashboard's colours and name.
  const shown = updates.slice(0, POPUP_MAX_UPDATES); // The newest few updates (the pop-up stays short).
  const more = updates.length - shown.length; // How many more are only on the page.

  useEffect(() => { // After the page shows:
    const box = dialog.current; // the dialog box,
    if (box && !box.open) box.showModal(); // opens it in front of the page (if it isn't open already).
  }, []); // (runs once)

  // Runs when the dialog closes, however it was closed.
  function onClose() { // No inputs.
    if (saved.current) return; // Already sent: nothing to do.
    saved.current = true; // Notes it's been sent.
    void markWhatsNewSeen(role); // Tells the server they've seen these updates (no need to wait for it).
  } // End of onClose.

  return ( // Shows:
    <dialog // the browser's dialog box:
      ref={dialog} // remembered so it can be opened,
      onClose={onClose} // telling the server when it closes,
      aria-labelledby="whats-new-title" // named by its heading for screen readers,
      className="m-auto w-[min(92vw,32rem)] rounded-2xl border border-zinc-200 bg-white p-0 text-charcoal shadow-xl backdrop:bg-charcoal/40" // centred, rounded, white, with the page dimmed behind.
    >{/* (end of the box's settings) */}
      <div className={`h-1.5 w-full ${theme.accent}`} aria-hidden />{/* A thin bar in the dashboard's colour. */}
      <div className="max-h-[75vh] overflow-y-auto p-6">{/* The contents, scrolling if long: */}
        <div className="flex items-start justify-between gap-3">{/* the heading row: */}
          <div>{/* the words: */}
            <p className={`text-xs font-semibold uppercase tracking-wide ${theme.strongText}`}>{theme.title}</p>{/* which dashboard, */}
            <h2 id="whats-new-title" className="mt-1 text-xl font-semibold tracking-tight">What&apos;s new</h2>{/* and the heading. */}
          </div>{/* End of the words. */}
          <button // the close button:
            type="button" // a plain button (not a form send),
            onClick={() => dialog.current?.close()} // closes the box,
            className="rounded-full px-2 text-2xl leading-none text-zinc-500 hover:text-charcoal" // a large, plain "×",
            aria-label="Close" // read out as "Close".
          >{/* (end of the button's settings) */}
            ×{/* the cross. */}
          </button>{/* End of the close button. */}
        </div>{/* End of the heading row. */}

        {shown.map((u) => ( // For each update shown:
          <section key={u.id} className="mt-5">{/* a part: */}
            <h3 className="font-semibold">{u.title}</h3>{/* its title, */}
            <ul className="mt-2 space-y-2">{/* and its changes: */}
              {u.items.map((i) => ( // for each change:
                <li key={i.id} className="flex items-start gap-2 text-sm">{/* a line: */}
                  <span className={`mt-0.5 shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold ${WHATS_NEW_KINDS[i.kind]?.className ?? ""}`}>{WHATS_NEW_KINDS[i.kind]?.label ?? i.kind}</span>{/* New, Updated or Removed, */}
                  <span className="whitespace-pre-wrap">{i.body}</span>{/* and what changed. */}
                </li> // End of the line.
              ))}{/* End of the changes. */}
            </ul>{/* End of the list. */}
          </section> // End of the part.
        ))}{/* End of the updates. */}
        {more > 0 && <p className="mt-4 text-sm text-zinc-600">And {more} more {more === 1 ? "update" : "updates"} on the What&apos;s new page.</p>}{/* How many more there are. */}

        <div className="mt-6 flex flex-wrap items-center justify-between gap-3">{/* the bottom row: */}
          <Link href={`/whats-new#${role}`} onClick={() => dialog.current?.close()} className="text-sm font-medium text-teal-800 underline underline-offset-4">{/* a link to every update (closing the box first): */}
            See all updates{/* its words. */}
          </Link>{/* End of the link. */}
          <button // the main button:
            type="button" // a plain button,
            onClick={() => dialog.current?.close()} // closes the box,
            className={`rounded-full px-5 py-2 text-sm font-semibold text-white ${theme.strongBg}`} // a rounded button in the dashboard's deep colour,
            autoFocus // and has the keyboard focus when the box opens.
          >{/* (end of the button's settings) */}
            Got it{/* its words. */}
          </button>{/* End of the main button. */}
        </div>{/* End of the bottom row. */}
      </div>{/* End of the contents. */}
    </dialog> // End of the dialog box.
  ); // End of what's shown.
} // End of WhatsNewPopup.
