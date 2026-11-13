// Summary: the "Add to your own calendar" controls on the tutor's weekly
// calendar page. A tutor makes a private calendar link, copies it (or taps
// a button for Google or Apple calendar), and can make a new link or turn
// it off. The link is shown once, straight after it's made, because CLG
// keeps only a scrambled copy (Carla, 12 Nov 2026).
//
"use client"; // Runs in the browser, so the link can be shown and copied straight away.

import { useActionState, useState } from "react"; // React's form helper, and a remembered value.
import { makeCalendarLink, turnOffCalendarLink, type CalendarLinkState } from "@/app/actions/calendar"; // The server actions, and their reply's shape.
import { BusyButton, FormMessage } from "@/components/ui"; // The busy-aware button and the message box.

// The small outline button look used for the secondary buttons here.
const outline = // The look:
  "rounded-full border border-zinc-300 px-4 py-2 text-sm font-medium text-zinc-800 transition hover:border-zinc-500 hover:bg-zinc-50"; // rounded, thin border, darker on hover.

// The calendar link controls. "hasLink" says whether the tutor already has
// a working link; "madeOn" and "lastUsed" are words about it, if so.
export function CalendarLinkCard({ hasLink, madeOn, lastUsed }: { hasLink: boolean; madeOn: string | null; lastUsed: string | null }) { // Takes the link's state.
  const [made, formAction] = useActionState( // One form for both buttons: its latest reply and its sender.
    async (_prev: CalendarLinkState, data: FormData) => // Runs when a button is pressed:
      data.get("do") === "off" ? turnOffCalendarLink() : makeCalendarLink(), // "Turn off" turns it off; otherwise makes a new link.
    {} as CalendarLinkState, // Starts with nothing to show.
  ); // End of the form helper.
  const turnedOff = Boolean(made.message) && !made.link && !made.error; // Whether the link was just turned off.
  const showLink = !turnedOff && (hasLink || Boolean(made.link)); // Whether there's a working link to talk about.
  const [copied, setCopied] = useState(false); // Whether the link was just copied.
  const link = made.link; // The new link, if one was just made.
  const webcal = link?.replace(/^https?:\/\//, "webcal://"); // The same link as "webcal://", which opens Apple Calendar (and most phone calendars) to subscribe.
  const google = webcal ? `https://calendar.google.com/calendar/r?cid=${encodeURIComponent(webcal)}` : null; // Google Calendar's "add this calendar" address.

  // Copies the link, and says so for a moment.
  async function copy() { // No inputs.
    if (!link) return; // No link: nothing to copy.
    try { // Tries to copy:
      await navigator.clipboard.writeText(link); // puts the link on the clipboard,
      setCopied(true); // shows "Copied",
      setTimeout(() => setCopied(false), 3000); // and goes back after 3 seconds.
    } catch { // Copying isn't allowed in this browser:
      setCopied(false); // leaves the button as it was (the link is still there to select by hand).
    } // End of the copy attempt.
  } // End of copy.

  return ( // Shows:
    <div className="space-y-4">{/* a column with space between parts: */}
      <FormMessage state={made} />{/* the latest message (made, turned off, or a problem), */}

      {link ? ( // Just made a link:
        <div className="space-y-3 rounded-xl border border-amber-200 bg-amber-50 p-4">{/* a highlighted box: */}
          <p className="text-sm font-medium text-amber-900">{/* a warning: */}
            Copy this link now. For your privacy CLG can&apos;t show it again (you can always make a new one).{/* copy it now. */}
          </p>{/* End of the warning. */}
          <input // the link, in a box that's easy to select:
            readOnly // can't be typed in,
            value={link} // shows the link,
            onFocus={(e) => e.currentTarget.select()} // selects it all when tapped,
            aria-label="Your private calendar link" // its name for screen readers,
            className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 font-mono text-xs" // full width, small fixed-width text.
          />{/* End of the link box. */}
          <div className="flex flex-wrap gap-2">{/* a row of buttons: */}
            <button type="button" onClick={copy} className={outline}>{/* copy, */}
              {copied ? "Copied" : "Copy link"}{/* saying "Copied" just after. */}
            </button>{/* End of the copy button. */}
            {google && ( // Google Calendar:
              <a href={google} target="_blank" rel="noreferrer" className={outline}>{/* opens Google Calendar in a new tab, */}
                Add to Google Calendar{/* its words. */}
              </a> // End of the Google link.
            )}{/* End of the Google part. */}
            {webcal && ( // Apple and phone calendars:
              <a href={webcal} className={outline}>{/* opens the device's calendar app, */}
                Add to Apple or phone calendar{/* its words. */}
              </a> // End of the Apple link.
            )}{/* End of the Apple part. */}
          </div>{/* End of the buttons. */}
          <p className="text-xs text-zinc-600">{/* help for Outlook: */}
            Outlook: open Outlook calendar, choose Add calendar, then Subscribe from web (or From internet), and paste the link.{/* the steps. */}
          </p>{/* End of the Outlook help. */}
        </div> // End of the highlighted box.
      ) : showLink ? ( // Already has a working link:
        <p className="text-sm text-zinc-700">{/* a line about it: */}
          Your calendar link was made on {madeOn}.{/* when it was made, */}
          {lastUsed ? ` Your calendar app last checked it on ${lastUsed}.` : " No calendar app has used it yet."}{/* and when a calendar app last used it. */}
        </p> // End of the line.
      ) : ( // No link yet:
        <p className="text-sm text-zinc-700">{/* an explanation: */}
          You don&apos;t have a calendar link yet. Make one to see your CLG sessions in Google, Outlook or Apple calendar.{/* what it's for. */}
        </p> // End of the explanation.
      )}{/* End of the link part. */}

      <form action={formAction} className="flex flex-wrap gap-2">{/* the action buttons, in one form: */}
        <BusyButton // making a link:
          type="submit" // sends the form,
          name="do" // tells the action which button,
          value="make" // "make",
          className="rounded-full bg-teal-700 px-5 py-2.5 text-sm font-medium text-white shadow-sm transition hover:bg-teal-900" // teal and rounded,
        >{/* (end of the button's settings) */}
          {showLink ? "Make a new link" : "Make my calendar link"}{/* words that fit whether one exists. */}
        </BusyButton>{/* End of the button. */}
        {showLink && ( // If there's a link to turn off:
          <BusyButton type="submit" name="do" value="off" className={outline}>{/* the turn-off button ("off"), */}
            Turn off my link{/* its words. */}
          </BusyButton> // End of the button.
        )}{/* End of the turn-off part. */}
      </form>{/* End of the action buttons. */}
      {showLink && ( // If there's a link:
        <p className="text-xs text-zinc-500">{/* a note: */}
          Making a new link stops the old one straight away. Do this if you shared it by mistake or lost your phone.{/* when to make a new one. */}
        </p> // End of the note.
      )}{/* End of the note part. */}
    </div> // End of the column.
  ); // End of what's shown.
} // End of CalendarLinkCard.
