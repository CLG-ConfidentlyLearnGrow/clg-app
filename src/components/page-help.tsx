// Summary: the "Show me how" button beside each dashboard page's heading
// (Carla, 18 Nov 2026). It opens a pop-up with the App guide steps for the
// page the person is on, so anyone needing a refresher can get it without
// leaving the page. The pop-up also has a link to the whole App guide and a
// button to take the app tour again. It uses the browser's own dialog box,
// which keeps keyboard focus inside it, closes with the Escape key, and
// works with screen readers.
//
"use client"; // Marks this file as code that runs in the browser.

import Link from "next/link"; // Links between pages.
import { useId, useRef, type ReactNode } from "react"; // React helpers: make a unique id, hold a reference, and the type for "anything that can be shown".
import { AppTour } from "@/components/app-tour"; // The app tour pop-up, opened again from here.
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import type { Tour } from "@/lib/app-tours"; // The tour shape (for type checking).
import { ROLE_THEME } from "@/lib/role-theme"; // Each dashboard's colours.

// Shows the button and its pop-up. "page" is the page's name (for the
// pop-up's heading), "guideHref" is the address of the whole App guide, and
// "children" are the guide steps for this page (made on the server).
export function PageHelp({
  role, // The dashboard, for its colours.
  page, // The page's name, e.g. "Sessions".
  guideHref, // The address of the whole App guide for this dashboard.
  tour, // This dashboard's app tour, to take again.
  children, // The App guide steps for this page.
}: { // The settings' types:
  role: Role; // a role,
  page: string; // words,
  guideHref: string; // an address,
  tour: Tour; // the tour,
  children: ReactNode; // anything shown.
}) { // End of the settings.
  const dialog = useRef<HTMLDialogElement>(null); // The dialog box on the page.
  const titleId = useId(); // A unique id for the pop-up's heading (read out by screen readers).
  const theme = ROLE_THEME[role]; // This dashboard's colours.

  return ( // Shows:
    <>{/* (a group) */}
      <button // the "Show me how" button:
        type="button" // a plain button (not a form send),
        onClick={() => dialog.current?.showModal()} // opens the pop-up in front of the page,
        aria-haspopup="dialog" // tells screen readers it opens a pop-up,
        className={`inline-flex shrink-0 items-center gap-2 rounded-full border bg-white px-3 py-1.5 text-sm font-medium shadow-sm hover:bg-zinc-50 ${theme.accentBorder} ${theme.strongText}`} // a rounded, outlined button in the dashboard's colour.
      >{/* (end of the button's settings) */}
        <span aria-hidden className={`flex h-5 w-5 items-center justify-center rounded-full text-xs font-bold text-white ${theme.strongBg}`}>?</span>{/* a small "?" circle (not read out), */}
        Show me how{/* and the words. */}
      </button>{/* End of the button. */}
      <dialog // the browser's dialog box:
        ref={dialog} // remembered so it can be opened,
        aria-labelledby={titleId} // named by its heading for screen readers,
        className="m-auto w-[min(94vw,40rem)] rounded-2xl border border-zinc-200 bg-white p-0 text-charcoal shadow-xl backdrop:bg-charcoal/40" // centred, rounded, white, with the page dimmed behind.
      >{/* (end of the box's settings) */}
        <div className={`h-1.5 w-full ${theme.accent}`} aria-hidden />{/* A thin bar in the dashboard's colour along the top. */}
        <div className="max-h-[80vh] overflow-y-auto p-6">{/* The contents, scrolling if long: */}
          <div className="flex items-start justify-between gap-3">{/* the heading row: */}
            <div>{/* the words: */}
              <p className={`text-xs font-semibold uppercase tracking-wide ${theme.strongText}`}>How to use this page</p>{/* a small label, */}
              <h2 id={titleId} className="mt-1 text-xl font-semibold tracking-tight">{page}</h2>{/* and the page's name. */}
            </div>{/* End of the words. */}
            <button // the close button:
              type="button" // a plain button,
              onClick={() => dialog.current?.close()} // closes the box,
              className="rounded-full px-2 text-2xl leading-none text-zinc-500 hover:text-charcoal" // a large, plain "×",
              aria-label="Close" // read out as "Close".
            >{/* (end of the button's settings) */}
              ×{/* the cross. */}
            </button>{/* End of the close button. */}
          </div>{/* End of the heading row. */}
          <p className="mt-2 text-sm text-zinc-600">Open a task to see its steps.</p>{/* How to use the pop-up. */}
          <div className="mt-4">{children}</div>{/* The App guide steps for this page. */}
          <div className="mt-6 flex flex-wrap items-center justify-between gap-3 border-t border-zinc-100 pt-4">{/* the bottom row: */}
            <Link href={guideHref} className="text-sm font-medium text-teal-800 underline underline-offset-4">Open the whole App guide</Link>{/* a link to the whole guide (with search), */}
            <div className="flex flex-wrap items-center gap-3">{/* the right-hand buttons: */}
              <AppTour tour={tour} role={role} save buttonLabel="Take the app tour again" />{/* the app tour, opened again with a button (it opens in front of this pop-up), */}
              <button type="button" onClick={() => dialog.current?.close()} className="text-sm text-zinc-600 underline underline-offset-4">Close</button>{/* and a plain close button. */}
            </div>{/* End of the right-hand buttons. */}
          </div>{/* End of the bottom row. */}
        </div>{/* End of the contents. */}
      </dialog>{/* End of the dialog box. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of PageHelp.
