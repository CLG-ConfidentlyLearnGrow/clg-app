// Summary: the dashboard layout with a side menu of sections (which can be
// hidden on bigger screens and opens from a button on phones), the page
// heading, and the chosen section's contents.
//
"use client"; // Marks this file as code that runs in the browser.

import Link from "next/link"; // The Next.js link, for moving between pages without a full reload.
import { useState, type ReactNode } from "react"; // React's memory for on-screen choices, and the type for "anything that can be shown".
import { PageTitle } from "@/components/ui"; // The page heading.
import type { Role } from "@/lib/auth"; // The list of role names, for type checking only.
import { ROLE_THEME } from "@/lib/role-theme"; // The colours for each role.

// One menu section: its id, its words, an optional count of things to do,
// an optional address (when it opens another page, e.g. Sessions or Billing),
// and optional smaller sections shown under it while it's open.
export type Section = { id: string; label: string; count?: number; href?: string; items?: Section[] }; // (the shape described above)

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
  children, // The open section's contents.
}: { // The settings' types:
  basePath: string; // address is text,
  label: string; // name is text,
  role?: Role; // role is optional,
  section: string; // open section is text,
  subSection?: string; // open smaller section is optional text,
  sections: Section[]; // sections is a list,
  children: ReactNode; // contents can be anything shown.
}) { // End of the settings.
  const theme = role ? ROLE_THEME[role] : null; // The role's colours, if a role was given.
  const activeItem = theme ? `${theme.strongBg} font-medium text-white` : "bg-teal-700 font-medium text-white"; // Look of the open menu item: filled in the role's deep colour (or teal), white text.
  const idleItem = `text-zinc-800 ${theme ? theme.hoverTint : "hover:bg-teal-100"}`; // Look of other menu items: dark text, pale tint on hover.
  const activeCount = `bg-white ${theme ? theme.strongText : "text-teal-800"}`; // Look of the open item's count: white with deep-coloured text.
  const idleCount = `${theme ? theme.strongBg : "bg-teal-500"} text-white`; // Look of other items' counts: filled in the deep colour, white text.
  const menuBox = `rounded-2xl border border-zinc-200 bg-white p-2 shadow-sm ${theme ? `border-t-4 ${theme.accentTopBorder}` : ""}`; // Look of the menu box: rounded, bordered, white, with a coloured top edge for a role.
  const [open, setOpen] = useState(true); // Whether the side menu is showing (starts showing).
  const [phoneOpen, setPhoneOpen] = useState(false); // Whether the phone menu is open (starts closed).
  // Clicking an open heading that has smaller sections under it (e.g.
  // Sessions) folds them away, and clicking it again unfolds them (Carla,
  // 12 Nov 2026). This remembers which heading is folded (none to start).
  const [foldedId, setFoldedId] = useState<string | null>(null); // The folded heading's id, or nothing.

  // Shows or hides the side menu.
  function toggle() {
    setOpen((was) => !was); // Flips it to the opposite of what it was.
  } // End of toggle.

  const current = sections.find((s) => s.id === section); // The open section's details.
  const currentSub = current?.items?.find((s) => s.id === subSection); // The open smaller section's details (if any).
  const heading = currentSub ? `${current?.label}: ${currentSub.label}` : (current?.label ?? label); // The page heading, e.g. "Sessions: Bookings".

  // One menu link (used for sections and for the smaller sections under them).
  // "fold" is given for an open heading with smaller sections: it says
  // whether they're showing, and clicking folds or unfolds them instead of
  // reloading the page.
  function itemLink(s: Section, active: boolean, small: boolean, fold?: { showing: boolean }) {
    return ( // Shows:
      <Link // a link:
        href={s.href ?? `${basePath}?section=${s.id}`} // to its own address, or to this section of the page,
        onClick={(e) => { // when clicked:
          if (fold) { // on an open heading with smaller sections:
            e.preventDefault(); // stays on this page,
            setFoldedId(fold.showing ? s.id : null); // and folds them away (or unfolds them if folded).
            return; // (nothing else to do)
          } // End of the fold part.
          setFoldedId(null); // Moving to another section: nothing stays folded,
          setPhoneOpen(false); // and the phone menu closes.
        }} // (end of the click)
        aria-current={active ? "page" : undefined} // telling screen readers it's the current page when open,
        aria-expanded={fold ? fold.showing : undefined} // telling screen readers whether its smaller sections are showing,
        className={`flex items-center justify-between gap-2 rounded-md px-3 ${small ? "py-1.5 text-[13px]" : "py-2 text-sm"} ${ // in a row with words on the left and count on the right (a little smaller for smaller sections), with:
          active ? activeItem : idleItem // the open look or the normal look.
        }`} // (end of the look)
      >{/* (end of the link's settings) */}
        <span className="flex items-center gap-1.5">{/* The words (with an arrow for a heading that can fold): */}
          {s.label}{/* the section's words, */}
          {s.items?.length ? <span aria-hidden className="text-[10px] opacity-70">{fold?.showing ? "▾" : "▸"}</span> : null}{/* a small arrow: down while its smaller sections show, right otherwise (hidden from screen readers). */}
        </span>{/* End of the words. */}
        {s.count ? ( // If there's a count:
          <span // a small rounded badge:
            className={`rounded-full px-2 text-xs ${active ? activeCount : idleCount}`} // in the open or normal count look,
          >{/* (end of the badge's settings) */}
            {s.count}{/* showing the number. */}
          </span> // End of the badge.
        ) : null}{/* Otherwise nothing. */}
      </Link> // End of the link.
    ); // End of what's shown.
  } // End of itemLink.

  const links = ( // The list of menu links, used in both the side and phone menus:
    <nav aria-label={`${label} sections`}>{/* a navigation area named for screen readers, */}
      <ul className="space-y-1">{/* a list with space between items, */}
        {sections.map((s) => { // for each section:
          const open = s.id === section; // whether it's the open one,
          const canFold = open && (s.items?.length ?? 0) > 0; // whether it's an open heading with smaller sections,
          const subs = canFold && foldedId !== s.id ? (s.items ?? []) : []; // its smaller sections (shown while it's open and not folded),
          const active = open && !subs.some((x) => x.id === subSection); // filled in when none of its showing smaller sections is the open one (so a folded heading shows where you are).
          return ( // Shows:
            <li key={s.id}>{/* a list item: */}
              {itemLink(s, active, false, canFold ? { showing: subs.length > 0 } : undefined)}{/* the section's link (folding its smaller sections when it's open), */}
              {subs.length > 0 && ( // and, if it has smaller sections open:
                <ul className={`mt-1 ml-3 space-y-0.5 border-l-2 pl-2 ${theme ? theme.accentBorder : "border-teal-700"}`}>{/* an indented list with a coloured line on its left: */}
                  {subs.map((x) => ( // for each smaller section:
                    <li key={x.id}>{itemLink(x, x.id === subSection, true)}</li> // its link (filled in when open).
                  ))}{/* End of the smaller sections. */}
                </ul> // End of the indented list.
              )}{/* End of this part. */}
            </li> // End of the list item.
          ); // End of what's shown for this section.
        })}{/* End of the loop. */}
      </ul>{/* End of the list. */}
    </nav> // End of the navigation area.
  ); // End of the menu links.

  return ( // Shows:
    <div className="mx-auto flex w-full max-w-6xl gap-6 px-4 py-6 sm:py-8">{/* a centred row holding the menu and the page, */}
      {/* Computers and tablets: side menu that can be hidden */}
      <aside className={`hidden shrink-0 md:block ${open ? "w-60" : "w-10"}`}>{/* the side menu, hidden on phones, wide when showing and narrow when hidden, */}
        <div className="sticky top-4">{/* staying in view while scrolling, */}
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
          {open && <div className={menuBox}>{links}</div>}{/* The menu links in their box, when showing. */}
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
          {phoneOpen && <div className={`mt-2 ${menuBox}`}>{links}</div>}{/* The menu links in their box, when open. */}
        </div>{/* End of the phone block. */}

        <PageTitle title={heading} role={role} />{/* The heading: the open section's name (or the dashboard's), in the role's colour. */}
        <div className="space-y-6">{children}</div>{/* The section's contents, with space between parts. */}
      </div>{/* End of the page area. */}
    </div> // End of the row.
  ); // End of what's shown.
} // End of SectionShell.
