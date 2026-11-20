// Summary: the dashboard layout with a side menu of sections (which can be
// hidden on bigger screens and opens from a button on phones), the page
// heading, and the chosen section's contents.
//
"use client"; // Marks this file as code that runs in the browser.

import Link from "next/link"; // The Next.js link, for moving between pages without a full reload.
import { useEffect, useRef, useState, type ReactNode } from "react"; // React's tools: run code after showing, point at a box on screen, memory for on-screen choices, and the type for "anything that can be shown".
import { PageTitle } from "@/components/ui"; // The page heading.
import type { Role } from "@/lib/auth"; // The list of role names, for type checking only.
import { ROLE_THEME } from "@/lib/role-theme"; // The colours for each role.

// One menu section: its id, its words, an optional count of things to do,
// an optional address (when it opens another page, e.g. Sessions or Billing),
// optional smaller sections (sub-tabs) that can be opened under it, and
// "countsInside", which says its sub-tabs carry all of its numbers (so a
// folded heading can show their total, and an open one can leave the
// numbers to its sub-tabs).
export type Section = { id: string; label: string; count?: number; href?: string; items?: Section[]; countsInside?: boolean }; // (the shape described above)

// Dashboard layout: side headings for each section, which can be hidden to
// give the page more room. On phones the menu opens from a button at the top.
// "role" colours the menu and heading in that dashboard's colour.
// A section with its own smaller sections (e.g. Sessions: Overview,
// Bookings, Notices) shows them indented under it while it's open;
// "subSection" says which of those is open.
export function SectionShell({
  basePath, // The page's address, e.g. "/admin".
  label, // The dashboard's name, used in menu labels.
  role, // Which dashboard it is (for its colours), if any.
  section, // The section currently open.
  subSection, // The smaller section open inside it, if it has any.
  sections, // Every section in the menu.
  help, // A "Show me how" button to show beside the heading, if any (Carla, 18 Nov 2026).
  children, // The open section's contents.
}: { // The settings' types:
  basePath: string; // address is text,
  label: string; // name is text,
  role?: Role; // role is optional,
  section: string; // open section is text,
  subSection?: string; // open smaller section is optional text,
  sections: Section[]; // sections is a list,
  help?: ReactNode; // the help button is optional,
  children: ReactNode; // contents can be anything shown.
}) { // End of the settings.
  const theme = role ? ROLE_THEME[role] : null; // The role's colours, if a role was given.
  const activeItem = theme ? `${theme.strongBg} font-medium text-white` : "bg-teal-700 font-medium text-white"; // Look of the open menu item: filled in the role's deep colour (or teal), white text.
  const idleItem = `text-zinc-800 ${theme ? theme.hoverTint : "hover:bg-teal-100"}`; // Look of other menu items: dark text, pale tint on hover.
  const activeCount = `bg-white ${theme ? theme.strongText : "text-teal-800"}`; // Look of the open item's count: white with deep-coloured text.
  const idleCount = `${theme ? theme.strongBg : "bg-teal-500"} text-white`; // Look of other items' counts: filled in the deep colour, white text.
  const menuBox = `rounded-2xl border border-zinc-200 bg-white p-2 shadow-sm ${theme ? `border-t-4 ${theme.accentTopBorder}` : ""}`; // Look of the menu box: rounded, bordered, white, with a coloured top edge for a role.
  // Lets the menu box scroll by itself when its links don't all fit, and
  // stops that scrolling from carrying on into the page once it reaches
  // the top or bottom of the menu (Carla, 16 Nov 2026).
  const menuScroll = "overflow-y-auto overscroll-contain"; // Scroll inside the box when needed; don't pass the scroll on to the page.
  const [open, setOpen] = useState(true); // Whether the side menu is showing (starts showing).

  // Fits the side menu into the space actually left on screen (Carla, 16 Nov
  // 2026). Near the top of a page the top bar and dashboard tabs take up room
  // above the menu, so "the whole screen's height" was too tall and the last
  // tabs fell off the bottom. This measures where the menu starts and lets it
  // reach only to just above the bottom of the window, checking again
  // whenever the page scrolls or the window changes size.
  const stickyRef = useRef<HTMLDivElement>(null); // Points at the block holding the Hide menu button and the menu.
  const [menuMax, setMenuMax] = useState<number | null>(null); // How tall that block may be, in pixels (unknown until measured).
  useEffect(() => { // After the page shows (and again if the menu is hidden or shown):
    let frame = 0; // The waiting re-measure, if one is booked (0 means none).
    function measure() { // Works out the room left and saves it.
      frame = 0; // This re-measure is happening now, so none is waiting.
      const box = stickyRef.current; // The block holding the menu.
      if (!box) return; // Not on screen (e.g. leaving the page): nothing to measure.
      const top = Math.max(box.getBoundingClientRect().top, 16); // Where it starts from the top of the window (at least the 16px gap it keeps when stuck).
      setMenuMax(Math.max(window.innerHeight - top - 16, 160)); // Room from there to 16px above the window's bottom (never under 160px, so it stays usable).
    } // End of measure.
    function schedule() { // Books one re-measure for the next screen update (avoids measuring on every scroll tick).
      if (!frame) frame = requestAnimationFrame(measure); // Only if one isn't already booked.
    } // End of schedule.
    schedule(); // Measures once to start.
    window.addEventListener("scroll", schedule, { passive: true }); // Measures again when the page scrolls (the menu's start moves until it sticks).
    window.addEventListener("resize", schedule); // Measures again when the window changes size.
    return () => { // When leaving the page (or before measuring again):
      window.removeEventListener("scroll", schedule); // stops listening for scrolling,
      window.removeEventListener("resize", schedule); // stops listening for size changes,
      cancelAnimationFrame(frame); // and cancels any booked re-measure.
    }; // End of the clean-up.
  }, [open]); // Runs again when the menu is hidden or shown.
  const [phoneOpen, setPhoneOpen] = useState(false); // Whether the phone menu is open (starts closed).
  // Every heading with sub-tabs has an arrow beside it. Clicking the arrow
  // opens or closes its sub-tabs right there, from any page, without loading
  // another page (Carla, 20 Nov 2026). Clicking the open heading's name also
  // folds or unfolds its sub-tabs (Carla, 12 Nov 2026). To start with, only
  // the heading of the page you are on is open. This remembers the headings
  // the person has opened or closed themselves since (none to start).
  const [openChoice, setOpenChoice] = useState<Record<string, boolean>>({}); // Each heading's id, with true (opened) or false (closed), for the ones the person has changed.
  const isShowing = (s: Section) => openChoice[s.id] ?? s.id === section; // Whether a heading's sub-tabs show: the person's choice, or open only for the page you are on.
  const flip = (s: Section) => setOpenChoice((was) => ({ ...was, [s.id]: !isShowing(s) })); // Opens a heading's sub-tabs if closed, or closes them if open.

  // Shows or hides the side menu.
  function toggle() {
    setOpen((was) => !was); // Flips it to the opposite of what it was.
  } // End of toggle.

  const current = sections.find((s) => s.id === section); // The open section's details.
  const currentSub = current?.items?.find((s) => s.id === subSection); // The open smaller section's details (if any).
  const heading = currentSub ? `${current?.label}: ${currentSub.label}` : (current?.label ?? label); // The page heading, e.g. "Sessions: Bookings".

  // The number to show beside a menu item (Carla, 20 Nov 2026). A heading
  // whose sub-tabs carry its numbers (e.g. Sessions: Overview, Bookings,
  // Notices) shows the total of their numbers while they are folded away,
  // so nothing waiting is hidden, and shows no number while they are open,
  // because each sub-tab then shows its own. A heading whose sub-tabs have
  // no numbers of their own keeps its own number either way, and any other
  // item shows its own number.
  function shownCount(s: Section, showing: boolean): number | undefined {
    if (!s.items?.length || !s.countsInside) return s.count; // No sub-tabs, or sub-tabs without their own numbers: its own number (if any).
    if (showing) return undefined; // Sub-tabs showing: no total (each shows its own number).
    const total = s.items.reduce((sum, x) => sum + (x.count ?? 0), 0); // Adds up the sub-tabs' numbers.
    return total > 0 ? total : undefined; // The total, or nothing when there is nothing to do.
  } // End of shownCount.

  // One sub-tab's link (e.g. Sessions: Bookings), shown indented under its
  // heading. "active" fills it in when it is the page you are on.
  function subLink(x: Section, active: boolean) {
    return ( // Shows:
      <Link // a link:
        href={x.href ?? `${basePath}?section=${x.id}`} // to its own address, or to this section of the page,
        onClick={() => { // when clicked:
          setOpenChoice({}); // moving page: every heading goes back to its usual open or closed state,
          setPhoneOpen(false); // and the phone menu closes.
        }} // (end of the click)
        aria-current={active ? "page" : undefined} // telling screen readers it is the current page when open,
        className={`flex items-center justify-between gap-2 rounded-md px-3 py-1.5 text-[13px] ${active ? activeItem : idleItem}`} // in a row with words on the left and count on the right, a little smaller than headings, in the open or normal look.
      >{/* (end of the link's settings) */}
        <span>{x.label}</span>{/* The sub-tab's words. */}
        {x.count ? ( // If there is a number to show:
          <span className={`rounded-full px-2 text-xs ${active ? activeCount : idleCount}`}>{x.count}</span> // a small rounded badge showing it, in the open or normal count look.
        ) : null}{/* Otherwise nothing. */}
      </Link> // End of the link.
    ); // End of what's shown.
  } // End of subLink.

  // One heading row: its link (words and number) and, when it has sub-tabs,
  // an arrow button that opens or closes them in place (Carla, 20 Nov 2026).
  // "where" says which copy of the menu this is (side or phone), so each
  // copy's sub-tab list gets its own name for screen readers.
  function headingRow(s: Section, where: string) {
    const current = s.id === section; // Whether this heading is the page you are on.
    const hasSubs = (s.items?.length ?? 0) > 0; // Whether it has sub-tabs.
    const showing = hasSubs && isShowing(s); // Whether its sub-tabs are showing now.
    const listId = `menu-${where}-${s.id}`; // The name of its sub-tab list (for the arrow button to point to).
    const active = current && !(showing && s.items?.some((x) => x.id === subSection)); // Filled in when it is the page you are on and the open sub-tab is not showing under it (so a folded heading still shows where you are).
    const count = shownCount(s, showing); // The number to show beside it (if any).
    return ( // Shows:
      <li key={s.id}>{/* a list item: */}
        <div className={`flex items-stretch rounded-md ${active ? activeItem : idleItem}`}>{/* one row holding the link and the arrow, filled in when it is the page you are on: */}
          <Link // the heading's link:
            href={s.href ?? `${basePath}?section=${s.id}`} // to its own address, or to this section of the page,
            data-no-loading={current && hasSubs ? "" : undefined} // marked as staying on this page when it only folds or unfolds (so no loading bar shows),
            onClick={(e) => { // when clicked:
              if (current && hasSubs) { // on the open heading with sub-tabs:
                e.preventDefault(); // stays on this page,
                flip(s); // and folds or unfolds its sub-tabs.
                return; // (nothing else to do)
              } // End of the fold part.
              setOpenChoice({}); // Moving page: every heading goes back to its usual open or closed state,
              setPhoneOpen(false); // and the phone menu closes.
            }} // (end of the click)
            aria-current={active ? "page" : undefined} // telling screen readers it is the current page when open,
            className={`flex min-w-0 flex-1 items-center justify-between gap-2 rounded-md py-2 text-sm ${hasSubs ? "pl-3 pr-1" : anySubs ? "pl-3 pr-10" : "px-3"}`} // taking the row's width, words on the left and number on the right (less space on the right when the arrow follows, and room left where other rows have an arrow, so every number lines up).
          >{/* (end of the link's settings) */}
            <span className="min-w-0">{s.label}</span>{/* The heading's words. */}
            {count ? ( // If there is a number to show:
              <span className={`shrink-0 rounded-full px-2 text-xs ${active ? activeCount : idleCount}`}>{count}</span> // a small rounded badge showing it, in the open or normal count look.
            ) : null}{/* Otherwise nothing. */}
          </Link>{/* End of the link. */}
          {hasSubs && ( // If it has sub-tabs, the arrow button:
            <button // a button:
              type="button" // that does not send any form,
              onClick={() => flip(s)} // that opens or closes the sub-tabs right here, without loading a page,
              aria-expanded={showing} // telling screen readers whether the sub-tabs are showing,
              aria-controls={listId} // and which list it opens,
              aria-label={`${showing ? "Hide" : "Show"} ${s.label} sub-tabs`} // named for screen readers, e.g. "Show Billing sub-tabs",
              title={showing ? "Hide sub-tabs" : "Show sub-tabs"} // with a tooltip saying what it will do,
              className="flex w-9 shrink-0 items-center justify-center rounded-md hover:bg-black/10 focus-visible:outline-2 focus-visible:outline-offset-[-2px]" // a square-ish target at the end of the row, slightly darker on hover, with a clear outline when reached by keyboard.
            >{/* (end of the button's settings) */}
              <svg aria-hidden="true" viewBox="0 0 20 20" className={`h-4 w-4 transition-transform motion-reduce:transition-none ${showing ? "rotate-90" : ""}`} fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">{/* an arrow (hidden from screen readers) pointing right when closed and turning to point down when open: */}
                <path d="M7.5 5l5 5-5 5" />{/* the arrow's shape. */}
              </svg>{/* End of the arrow. */}
            </button> // End of the button.
          )}{/* End of the arrow part. */}
        </div>{/* End of the row. */}
        {showing && ( // If its sub-tabs are showing:
          <ul id={listId} className={`mt-1 ml-3 space-y-0.5 border-l-2 pl-2 ${theme ? theme.accentBorder : "border-teal-700"}`}>{/* an indented list with a coloured line on its left: */}
            {s.items?.map((x) => ( // for each sub-tab:
              <li key={x.id}>{subLink(x, current && x.id === subSection)}</li> // its link (filled in when it is the page you are on).
            ))}{/* End of the sub-tabs. */}
          </ul> // End of the indented list.
        )}{/* End of this part. */}
      </li> // End of the list item.
    ); // End of what's shown.
  } // End of headingRow.

  const anySubs = sections.some((s) => (s.items?.length ?? 0) > 0); // Whether any heading has sub-tabs (and so an arrow), to line up the numbers.

  // The list of menu links, used in both the side and phone menus. "where"
  // says which one it is (see headingRow).
  const links = (where: string) => ( // Shows:
    <nav aria-label={`${label} sections`}>{/* a navigation area named for screen readers, */}
      <ul className="space-y-1">{/* a list with space between items, */}
        {sections.map((s) => headingRow(s, where))}{/* and each heading's row (with its sub-tabs when showing). */}
      </ul>{/* End of the list. */}
    </nav> // End of the navigation area.
  ); // End of the menu links.

  return ( // Shows:
    <div className="mx-auto flex w-full max-w-6xl gap-6 px-4 py-6 sm:py-8">{/* a centred row holding the menu and the page, */}
      {/* Computers and tablets: side menu that can be hidden */}
      <aside className={`hidden shrink-0 md:block ${open ? "w-60" : "w-10"}`}>{/* the side menu, hidden on phones, wide when showing and narrow when hidden, */}
        {/* Carla, 16 Nov 2026: the menu scrolls on its own, without moving the page. */}
        <div // a block:
          ref={stickyRef} // that's measured (see above),
          className="sticky top-4 flex max-h-[calc(100dvh-2rem)] flex-col" // staying in view while scrolling, never taller than the screen (less a small gap) before it's measured, stacking the button above the menu,
          style={menuMax ? { maxHeight: menuMax } : undefined} // and once measured, never taller than the room actually left on screen.
        >{/* (end of the block's settings) */}
          <button // a button:
            type="button" // that doesn't send any form,
            onClick={toggle} // that shows or hides the menu,
            aria-expanded={open} // telling screen readers whether the menu is showing,
            className="mb-3 flex h-9 items-center gap-2 rounded-md border border-zinc-300 bg-white px-3 text-sm hover:bg-teal-50" // small, bordered, pale tint on hover,
            title={open ? "Hide menu" : "Show menu"} // with a tooltip saying what it will do.
          >{/* (end of the button's settings) */}
            <span aria-hidden>{open ? "«" : "»"}</span>{/* Arrows pointing left or right (hidden from screen readers). */}
            {open && <span>Hide menu</span>}{/* "Hide menu" in words when showing. */}
            {!open && <span className="sr-only">Show menu</span>}{/* "Show menu" for screen readers only when hidden. */}
          </button>{/* End of the button. */}
          {open && <div className={`${menuBox} ${menuScroll} min-h-0`}>{links("side")}</div>}{/* The menu links in their box, when showing, scrolling inside the box when there are more than fit on screen. */}
        </div>{/* End of the in-view block. */}
      </aside>{/* End of the side menu. */}

      <div className="min-w-0 flex-1">{/* The page area, taking the rest of the width, */}
        {/* Phones: menu button that opens the list */}
        <div className="mb-4 md:hidden">{/* a block shown on phones only, */}
          <button // a button:
            type="button" // that doesn't send any form,
            onClick={() => setPhoneOpen((v) => !v)} // that opens or closes the phone menu,
            aria-expanded={phoneOpen} // telling screen readers whether it's open,
            className="flex w-full items-center justify-between rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm" // full width, bordered,
          >{/* (end of the button's settings) */}
            <span>{/* The words: */}
              {label} menu: <strong>{currentSub?.label ?? current?.label}</strong>{/* e.g. "Admin menu: Families". */}
            </span>{/* End of the words. */}
            <span aria-hidden>{phoneOpen ? "▲" : "▼"}</span>{/* An up or down arrow (hidden from screen readers). */}
          </button>{/* End of the button. */}
          {phoneOpen && <div className={`mt-2 ${menuBox} ${menuScroll} max-h-[60dvh]`}>{links("phone")}</div>}{/* The menu links in their box, when open, no taller than about two-thirds of the screen and scrolling inside the box. */}
        </div>{/* End of the phone block. */}

        <div className="flex flex-wrap items-start justify-between gap-x-4">{/* The heading row (the button drops below the heading on a narrow phone): */}
          <PageTitle title={heading} role={role} />{/* the heading: the open section's name (or the dashboard's), in the role's colour, */}
          {help && <div className="mb-6 sm:mt-9">{help}</div>}{/* and the "Show me how" button, level with the heading on wider screens. */}
        </div>{/* End of the heading row. */}
        <div className="space-y-6">{children}</div>{/* The section's contents, with space between parts. */}
      </div>{/* End of the page area. */}
    </div> // End of the row.
  ); // End of what's shown.
} // End of SectionShell.
