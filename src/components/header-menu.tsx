// Summary: the "Menu" button in the top bar on phones and small tablets
// (Carla, 16 Nov 2026). On a narrow screen the top links (Home, Feedback,
// Your privacy, Report app issue), the signed-in name and Sign out don't fit
// beside the logo, so they fold into this button. Tapping it opens a panel
// under the top bar with each link on its own large, easy-to-tap row.
// The panel closes when you tap a link, tap outside it, press Escape, or
// move to another page. The links themselves are made on the server and
// passed in, so this file only handles opening and closing.
//
"use client"; // Runs in the browser, because it reacts to taps.

import { useEffect, useRef, useState } from "react"; // React tools: remember open/closed, refer to page parts, and run code after changes.
import { usePathname } from "next/navigation"; // Reads the current page's address (to close the panel after moving page).

// The button and its panel. `children` is what goes inside the panel.
export function HeaderMenu({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false); // Whether the panel is showing (closed to start with).
  const path = usePathname(); // The current page's address.
  const [openedOn, setOpenedOn] = useState(path); // The page the panel was opened on.
  const boxRef = useRef<HTMLDivElement>(null); // Points at the button and panel together (to spot taps outside them).

  if (open && openedOn !== path) { // If the person has moved to another page while it was open:
    setOpen(false); // close the panel,
    setOpenedOn(path); // and remember the new page.
  } // End of the page check.

  useEffect(() => { // While the panel is open, watch for taps outside it and the Escape key:
    if (!open) return; // Nothing to watch while it's closed.
    function onPointer(event: PointerEvent) { // When someone taps or clicks anywhere:
      if (boxRef.current && !boxRef.current.contains(event.target as Node)) setOpen(false); // close the panel if the tap was outside it.
    } // End of onPointer.
    function onKey(event: KeyboardEvent) { // When a key is pressed:
      if (event.key === "Escape") setOpen(false); // Escape closes the panel.
    } // End of onKey.
    document.addEventListener("pointerdown", onPointer); // Starts listening for taps.
    document.addEventListener("keydown", onKey); // Starts listening for keys.
    return () => { // When the panel closes (or this goes away):
      document.removeEventListener("pointerdown", onPointer); // stop listening for taps,
      document.removeEventListener("keydown", onKey); // and stop listening for keys.
    }; // End of the clean-up.
  }, [open]); // Runs again whenever the panel opens or closes.

  function toggle() { // When the Menu button is tapped:
    setOpenedOn(path); // remember which page it was opened on,
    setOpen((was) => !was); // and open it if closed, or close it if open.
  } // End of toggle.

  function closeIfLink(event: React.MouseEvent) { // When something inside the panel is tapped:
    if ((event.target as HTMLElement).closest("a")) setOpen(false); // close the panel if it was a link (the page is changing).
  } // End of closeIfLink.

  return ( // Shows:
    <div ref={boxRef}>{/* the button and panel together: */}
      <button // the Menu button:
        type="button" // a plain button (not a form send),
        onClick={toggle} // opens or closes the panel,
        aria-expanded={open} // tells screen readers whether the panel is open,
        aria-controls="header-menu-panel" // and which panel it opens,
        className="inline-flex min-h-11 items-center gap-2 rounded-full border border-zinc-300 bg-white px-3.5 text-sm font-medium text-zinc-800 transition hover:border-teal-700 hover:text-teal-800" // a rounded outlined button, at least 44 pixels tall for easy tapping,
      >{/* (end of the button's settings) */}
        <svg aria-hidden="true" viewBox="0 0 20 20" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">{/* a small icon, hidden from screen readers: */}
          {open ? ( // when open, a cross:
            <path d="M5 5l10 10M15 5L5 15" /> // two crossing lines,
          ) : ( // when closed, three lines:
            <path d="M3 5h14M3 10h14M3 15h14" /> // three short lines,
          )}{/* end of the icon's shape, */}
        </svg>{/* end of the icon, */}
        <span className="max-[359px]:sr-only">{open ? "Close" : "Menu"}</span>{/* and the word "Menu" (or "Close" while open); on very narrow phones only screen readers hear it, so the bar still fits. */}
      </button>{/* End of the button. */}
      <div // the panel:
        id="header-menu-panel" // named, so the button can point to it,
        hidden={!open} // hidden while closed,
        onClick={closeIfLink} // closes after a link is tapped,
        className="absolute inset-x-0 top-full z-40 border-b border-zinc-200 bg-white shadow-lg" // full width, just under the top bar, above the page, with a soft shadow,
      >{/* (end of the panel's settings) */}
        <div className="mx-auto w-full max-w-6xl px-4 py-2">{/* its inner column, lined up with the top bar: */}
          {children}{/* the links passed in. */}
        </div>{/* End of the inner column. */}
      </div>{/* End of the panel. */}
    </div> // End of the button and panel.
  ); // End of what's shown.
} // End of HeaderMenu.
