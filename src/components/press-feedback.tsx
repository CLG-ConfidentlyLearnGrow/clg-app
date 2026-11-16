// Summary: makes every press of a button, link, tab or "Show / Hide" title
// visible straight away, on phones, tablets and computers (Carla, 16 Nov 2026).
// It does three things for the whole app, so no page needs extra code:
//   1. Marks the pressed item for a short moment, so even a very quick tap on
//      a phone shows the "pressed in" look set in globals.css.
//   2. Lets iPhones and iPads show the pressed look at all (Safari only shows
//      it once the page listens for touches).
//   3. Shows a thin moving bar along the top of the screen while a new page
//      loads after a link or search is pressed, so nobody presses it again.
//
"use client"; // Marks this file as code that runs in the browser.

import { usePathname, useSearchParams } from "next/navigation"; // Next.js helpers that give the current page address and its search words.
import { useEffect, useRef, useState } from "react"; // React helpers: run set-up code, remember things, and redraw when something changes.

// Everything that counts as "something you can press".
const PRESSABLE = [ // The list of kinds:
  "button", // buttons,
  "a[href]", // links (only real links, with somewhere to go),
  "[role='button']", // other items that act as buttons,
  "[role='tab']", // tabs,
  "summary", // the clickable title of a "Show / Hide" card,
  "input[type='submit']", // old-style send buttons,
  "input[type='button']", // old-style plain buttons,
  "input[type='reset']", // and old-style clear buttons.
].join(", "); // Joined into one search the browser understands.

// The shortest time the pressed look stays on, in thousandths of a second.
// A quick tap on a phone can be over in a few hundredths of a second, which
// is too fast to see, so the look is held for at least this long.
const MIN_PRESS_MS = 160; // About a sixth of a second.

// The longest time the loading bar stays on if a page never finishes
// changing (for example the page refused to open), so it never sticks.
const MAX_LOADING_MS = 15000; // Fifteen seconds.

// Finds the pressable item a press landed on (the press may land on words
// or a picture inside it), unless that item is switched off.
function pressableFrom(target: EventTarget | null): HTMLElement | null { // Takes where the press landed; gives back the item, or nothing.
  if (!(target instanceof Element)) return null; // The press did not land on part of the page: nothing to do.
  const item = target.closest<HTMLElement>(PRESSABLE); // The nearest pressable item around where the press landed.
  if (!item) return null; // Not on anything pressable: nothing to do.
  if (item.matches(":disabled") || item.getAttribute("aria-disabled") === "true") return null; // Switched off: it should not look pressed.
  return item; // The item to mark as pressed.
} // End of pressableFrom.

// Works out whether a click on a link will open a new page inside this app
// (as opposed to a new tab, a download, another website or the same page).
function opensPageHere(link: HTMLAnchorElement, event: MouseEvent): boolean { // Takes the link and the click; gives back yes or no.
  if (event.button !== 0) return false; // Only a normal (left) click or a tap counts.
  if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return false; // A click with a key held opens a new tab or window instead.
  if (link.target && link.target !== "_self") return false; // A link set to open in a new tab does not change this page.
  if (link.hasAttribute("download")) return false; // A download link does not change this page.
  const to = new URL(link.href, window.location.href); // Where the link goes, as a full address.
  if (to.origin !== window.location.origin) return false; // A link to another website is not this app's page loading.
  const here = window.location.pathname + window.location.search; // The page and search words open now.
  return to.pathname + to.search !== here; // True only if the link goes to a different page (not just a spot on this one).
} // End of opensPageHere.

// The part that is added once to every page (see layout.tsx).
export function PressFeedback() { // Takes no settings.
  const pathname = usePathname(); // The page address open now (changes when a new page opens).
  const searchParams = useSearchParams(); // The search words in the address (change when a search runs).
  const here = `${pathname}?${searchParams.toString()}`; // The page and search words open now, as one piece of text.
  // The page that was open when a link or search was pressed (nothing when
  // no new page is loading). Once the open page is different, the new page
  // has arrived, so the bar hides by itself.
  const [loadingFrom, setLoadingFrom] = useState<string | null>(null); // Starts as nothing (not loading).
  const loading = loadingFrom === here; // Loading only while the page it started from is still the one open.
  const busyLink = useRef<HTMLElement | null>(null); // The link that was pressed to load the page, so it can be marked busy and then cleared.

  // Sets up the press listeners once, when the page first opens.
  useEffect(() => { // Runs this code after the page is drawn:
    let pressed: HTMLElement | null = null; // The item that is currently held down (none to start).
    let pressedAt = 0; // When it was pressed (used to keep the look on for the minimum time).

    // Shows the loading bar, noting which page it started from.
    function startLoading() { // (see the note above)
      const params = new URLSearchParams(window.location.search); // The search words in the address now.
      setLoadingFrom(`${window.location.pathname}?${params.toString()}`); // Notes the page open now, in the same form as "here" above.
    } // End of startLoading.

    // Takes the pressed look off an item, after the minimum time has passed.
    function release(item: HTMLElement, since: number) { // (see the note above)
      const wait = Math.max(0, MIN_PRESS_MS - (performance.now() - since)); // How much of the minimum time is still left (none if it has passed).
      window.setTimeout(() => item.removeAttribute("data-pressed"), wait); // Takes the look off once that time is up.
    } // End of release.

    // A finger, pen or mouse button goes down on the page.
    function onPointerDown(event: PointerEvent) { // (see the note above)
      const item = pressableFrom(event.target); // The pressable item it went down on, if any.
      if (!item) return; // Not on anything pressable: nothing to do.
      item.setAttribute("data-pressed", ""); // Gives it the pressed look straight away.
      pressed = item; // Remembers it, so the look can come off when the press ends.
      pressedAt = performance.now(); // Remembers when the press started.
    } // End of onPointerDown.

    // The finger, pen or mouse button lifts (or the press is cancelled, for
    // example because the person started scrolling instead).
    function onPointerEnd() { // (see the note above)
      if (!pressed) return; // Nothing was held down: nothing to do.
      release(pressed, pressedAt); // Takes the look off after the minimum time.
      pressed = null; // Nothing is held down any more.
    } // End of onPointerEnd.

    // A key is pressed. Enter (and Space on buttons) presses whatever has the
    // keyboard focus, so that should look pressed too.
    function onKeyDown(event: KeyboardEvent) { // (see the note above)
      if (event.repeat) return; // Ignores the repeats sent while a key is held down.
      const item = pressableFrom(document.activeElement); // The pressable item with the keyboard focus, if any.
      if (!item) return; // Focus is not on something pressable (for example a text box): nothing to do.
      const isLink = item.tagName === "A"; // Whether it is a link (links are pressed with Enter only).
      if (event.key !== "Enter" && !(event.key === " " && !isLink)) return; // Not a key that presses it: nothing to do.
      item.setAttribute("data-pressed", ""); // Gives it the pressed look,
      release(item, performance.now()); // and takes it off after the minimum time.
    } // End of onKeyDown.

    // A click has finished being handled by the page. If it was on a link
    // to another page in the app, the loading bar is shown until it opens.
    // (Next.js links always cancel the browser's own page change and open
    // the page themselves, so a cancelled click is still a page loading. A
    // link that only does something on this page, such as folding the side
    // menu, is marked "data-no-loading" instead.)
    function onClick(event: MouseEvent) { // (see the note above)
      if (!(event.target instanceof Element)) return; // The click did not land on part of the page: nothing to do.
      const link = event.target.closest<HTMLAnchorElement>("a[href]"); // The link that was clicked, if any.
      if (!link || !opensPageHere(link, event)) return; // Not a link that opens a page here: nothing to do.
      if (link.hasAttribute("data-no-loading")) return; // A link marked as staying on this page: no page is loading.
      link.setAttribute("aria-busy", "true"); // Tells screen readers this link is busy loading.
      busyLink.current = link; // Remembers it, so it can be cleared when the page opens.
      startLoading(); // Shows the loading bar.
    } // End of onClick.

    // A form is sent. Search and filter forms load a new page, so the loading
    // bar is shown for those. Forms that save something already show their
    // own spinner on the button (see busy-button.tsx), so they are skipped.
    function onSubmit(event: SubmitEvent) { // (see the note above)
      if (event.defaultPrevented) return; // The page handled the form itself: no page is loading.
      const form = event.target; // The form that was sent.
      if (!(form instanceof HTMLFormElement)) return; // Not a form: nothing to do.
      if (form.method.toLowerCase() !== "get") return; // Only search-style forms (which put the words in the address) load a new page.
      if (form.getAttribute("action")?.startsWith("javascript:")) return; // A form run by the app's own code (it saves, not searches): skipped.
      startLoading(); // Shows the loading bar.
    } // End of onSubmit.

    // An empty touch listener. iPhones and iPads only show the pressed look
    // once the page listens for touches, so this switches it on.
    function onTouchStart() {} // Does nothing on purpose.

    document.addEventListener("pointerdown", onPointerDown, { passive: true }); // Listens for presses starting (without slowing scrolling).
    document.addEventListener("pointerup", onPointerEnd, { passive: true }); // Listens for presses ending.
    document.addEventListener("pointercancel", onPointerEnd, { passive: true }); // Listens for presses being cancelled.
    document.addEventListener("keydown", onKeyDown); // Listens for key presses.
    document.addEventListener("click", onClick); // Listens for clicks, after the page has handled them.
    document.addEventListener("submit", onSubmit); // Listens for forms being sent.
    document.addEventListener("touchstart", onTouchStart, { passive: true }); // The empty touch listener for iPhones and iPads.
    return () => { // When this part is removed from the page, tidies up:
      document.removeEventListener("pointerdown", onPointerDown); // stops listening for presses starting,
      document.removeEventListener("pointerup", onPointerEnd); // presses ending,
      document.removeEventListener("pointercancel", onPointerEnd); // presses being cancelled,
      document.removeEventListener("keydown", onKeyDown); // key presses,
      document.removeEventListener("click", onClick); // clicks,
      document.removeEventListener("submit", onSubmit); // forms being sent,
      document.removeEventListener("touchstart", onTouchStart); // and touches.
    }; // End of the tidy-up.
  }, []); // Runs once only.

  // When the page address or search words change, the new page has opened,
  // so the busy mark comes off the link that was pressed. (The loading bar
  // hides by itself, see "loading" above.)
  useEffect(() => { // Runs this code after the page is drawn:
    busyLink.current?.removeAttribute("aria-busy"); // The link is no longer busy.
    busyLink.current = null; // Forgets the link.
  }, [here]); // Runs each time the address or search words change.

  // If the loading bar has been on too long, hides it so it never sticks.
  useEffect(() => { // Runs this code after the page is drawn:
    if (!loading) return; // Not loading: nothing to time.
    const timer = window.setTimeout(() => setLoadingFrom(null), MAX_LOADING_MS); // Hides the bar after the longest allowed time.
    return () => window.clearTimeout(timer); // Cancels that timer if the page opens first.
  }, [loading]); // Runs each time loading starts or stops.

  return ( // Shows:
    <div className="nav-progress" data-active={loading || undefined} role="status" aria-live="polite">{/* a thin bar fixed to the top of the screen (only visible while loading), also read out by screen readers, */}
      {loading && <span className="sr-only">Loading the page</span>}{/* with words only screen readers hear while loading. */}
    </div> // End of the bar.
  ); // End of what is shown.
} // End of PressFeedback.
