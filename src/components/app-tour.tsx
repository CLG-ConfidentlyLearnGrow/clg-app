// Summary: the first-time app tour pop-up (Carla, 16 Nov 2026). It takes
// someone through the main parts of their dashboard one step at a time:
// what each part is, why it matters, and where to find it. It opens by
// itself the first time someone uses a dashboard, and can be opened again
// from the App guide with a button. It closes with "Not now", "Finish", the
// Escape key or the close button, and remembers how far they got, so it
// doesn't open by itself again. It uses the browser's own dialog box, which
// keeps keyboard focus inside it and works with screen readers.
//
"use client"; // Marks this file as code that runs in the browser.

import { useEffect, useId, useRef, useState } from "react"; // React helpers: run code after showing, make a unique id, hold references, and remember the step.
import { saveTourProgress } from "@/app/actions/app-tour"; // The server action that remembers how far they got.
import { Rich } from "@/components/app-guide-view"; // Shows text with **starred** words in bold.
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import type { Tour } from "@/lib/app-tours"; // The tour shape (for type checking).
import { ROLE_THEME } from "@/lib/role-theme"; // Each dashboard's colours and name.

// Shows the tour. "autoOpen" opens it as soon as the page shows (the first
// time). "buttonLabel" shows a button that opens it instead (the App
// guide). "save" says whether to remember progress (only for the person's
// own dashboard's tour). "startAt" is the step to open on.
export function AppTour({
  tour, // The tour's steps.
  role, // The dashboard, for its colours.
  save, // Whether to remember how far they got.
  autoOpen = false, // Whether to open straight away.
  buttonLabel, // The words for a button that opens it, if any.
  startAt = 0, // The step to open on.
}: { // The settings' types:
  tour: Tour; // the tour,
  role: Role; // a role,
  save: boolean; // yes or no,
  autoOpen?: boolean; // optional yes or no,
  buttonLabel?: string; // optional words,
  startAt?: number; // optional step number.
}) { // End of the settings.
  const dialog = useRef<HTMLDialogElement>(null); // The dialog box on the page.
  const heading = useRef<HTMLHeadingElement>(null); // The step's heading (focused on each step, so screen readers read it).
  const last = tour.steps.length - 1; // The number of the last step.
  const first = Math.min(Math.max(startAt, 0), last); // The opening step, kept within the tour.
  const [step, setStep] = useState(first); // The step showing now.
  const stepRef = useRef(first); // The same step, readable when the box closes.
  const finishedRef = useRef(false); // Whether they reached the end this time.
  const theme = ROLE_THEME[role]; // This dashboard's colours and name.
  const current = tour.steps[step]; // The step's words.
  const titleId = useId(); // A unique id for the heading (the page can have two tours: the first-time one and the App guide's).

  useEffect(() => { // After the page shows:
    const box = dialog.current; // the dialog box,
    if (autoOpen && box && !box.open) box.showModal(); // opens it in front of the page, if it should open by itself.
  }, [autoOpen]); // (runs once)

  // Moves to a step, and puts the keyboard focus on its heading.
  function go(to: number) { // Takes the step number.
    const n = Math.min(Math.max(to, 0), last); // Keeps it within the tour.
    stepRef.current = n; // Remembers it for when the box closes.
    if (n === last) finishedRef.current = true; // Reaching the last step counts as finishing.
    setStep(n); // Shows it.
    requestAnimationFrame(() => heading.current?.focus()); // After it shows, focuses its heading.
  } // End of go.

  // Opens the box (from the App guide button).
  function open() { // No inputs.
    finishedRef.current = false; // A fresh start for this time.
    stepRef.current = first; // Back to the opening step.
    setStep(first); // Shows it.
    dialog.current?.showModal(); // Opens the box in front of the page.
  } // End of open.

  // Runs when the box closes, however it was closed.
  function onClose() { // No inputs.
    if (!save) return; // Not their own tour (an admin looking at another): nothing to remember.
    void saveTourProgress(tour.id, stepRef.current, finishedRef.current); // Tells the server how far they got (no need to wait for it).
  } // End of onClose.

  return ( // Shows:
    <>{/* (a group) */}
      {buttonLabel && ( // If there's a button to open it:
        <button // the button:
          type="button" // a plain button (not a form send),
          onClick={open} // opens the tour,
          className={`rounded-full px-4 py-2 text-sm font-semibold text-white ${theme.strongBg}`} // a rounded button in the dashboard's deep colour.
        >{/* (end of the button's settings) */}
          {buttonLabel}{/* its words. */}
        </button> // End of the button.
      )}{/* End of the button. */}
      <dialog // the browser's dialog box:
        ref={dialog} // remembered so it can be opened,
        onClose={onClose} // remembering progress when it closes,
        aria-labelledby={titleId} // named by the step's heading for screen readers,
        className="m-auto w-[min(92vw,34rem)] rounded-2xl border border-zinc-200 bg-white p-0 text-charcoal shadow-xl backdrop:bg-charcoal/40" // centred, rounded, white, with the page dimmed behind.
      >{/* (end of the box's settings) */}
        <div className="h-1.5 w-full bg-zinc-100" aria-hidden>{/* A thin progress bar: */}
          <div className={`h-full ${theme.accent} transition-all`} style={{ width: `${((step + 1) / tour.steps.length) * 100}%` }} />{/* filled in the dashboard's colour as far as this step. */}
        </div>{/* End of the progress bar. */}
        <div className="max-h-[80vh] overflow-y-auto p-6">{/* The contents, scrolling if long: */}
          <div className="flex items-start justify-between gap-3">{/* the heading row: */}
            <div>{/* the words: */}
              <p className={`text-xs font-semibold uppercase tracking-wide ${theme.strongText}`}>{/* which tour, and the step number: */}
                {tour.title} · Step {step + 1} of {tour.steps.length}{/* e.g. "Welcome to CLG · Step 2 of 10". */}
              </p>{/* End of the small line. */}
              <h2 id={titleId} ref={heading} tabIndex={-1} className="mt-1 text-xl font-semibold tracking-tight outline-none">{current.title}</h2>{/* The step's heading (focusable, so screen readers read it). */}
            </div>{/* End of the words. */}
            <button // the close button:
              type="button" // a plain button,
              onClick={() => dialog.current?.close()} // closes the box,
              className="rounded-full px-2 text-2xl leading-none text-zinc-500 hover:text-charcoal" // a large, plain "×",
              aria-label="Close the tour" // read out as "Close the tour".
            >{/* (end of the button's settings) */}
              ×{/* the cross. */}
            </button>{/* End of the close button. */}
          </div>{/* End of the heading row. */}

          <div className="mt-4 space-y-3 text-sm leading-relaxed text-zinc-800">{/* The step's words: */}
            {current.text.map((t, i) => <p key={i}><Rich text={t} /></p>)}{/* each paragraph, */}
          </div>{/* End of the words. */}
          {current.why && ( // If the step says why it matters:
            <div className={`mt-4 rounded-lg px-3 py-2 text-sm ${theme.tintBg}`}>{/* a soft box in the dashboard's pale colour: */}
              <p className="font-semibold">Why it matters</p>{/* its label, */}
              <p className="mt-1"><Rich text={current.why} /></p>{/* and the reason. */}
            </div> // End of the box.
          )}{/* End of why. */}
          {current.where && ( // If the step says where to find it:
            <p className="mt-3 text-sm text-zinc-700">{/* a line: */}
              <span className="font-semibold">Find it: </span><Rich text={current.where} />{/* "Find it:" and where. */}
            </p> // End of the line.
          )}{/* End of where. */}

          <div className="mt-6 flex flex-wrap items-center justify-between gap-3">{/* the bottom row: */}
            {step === 0 ? ( // On the welcome step:
              <button type="button" onClick={() => dialog.current?.close()} className="text-sm font-medium text-zinc-600 underline underline-offset-4">{/* a "not now" link-style button that closes the box: */}
                Not now{/* its words. */}
              </button> // End of the button.
            ) : ( // On every other step:
              <button type="button" onClick={() => go(step - 1)} className="text-sm font-medium text-teal-800 underline underline-offset-4">{/* a "back" link-style button: */}
                Back{/* its words. */}
              </button> // End of the button.
            )}{/* End of the left button. */}
            <div className="flex items-center gap-3">{/* the right-hand buttons: */}
              {step > 0 && step < last && ( // In the middle of the tour:
                <button type="button" onClick={() => dialog.current?.close()} className="text-sm text-zinc-600 underline underline-offset-4">{/* a "skip" button that closes the box: */}
                  Skip the tour{/* its words. */}
                </button> // End of the button.
              )}{/* End of skip. */}
              {step < last ? ( // Before the last step:
                <button // the main button:
                  type="button" // a plain button,
                  onClick={() => go(step + 1)} // moves to the next step,
                  className={`rounded-full px-5 py-2 text-sm font-semibold text-white ${theme.strongBg}`} // a rounded button in the dashboard's deep colour,
                  autoFocus // and has the keyboard focus when the box opens.
                >{/* (end of the button's settings) */}
                  {step === 0 ? "Start the tour" : "Next"}{/* "Start the tour" on the welcome, then "Next". */}
                </button> // End of the main button.
              ) : ( // On the last step:
                <button // the finish button:
                  type="button" // a plain button,
                  onClick={() => { finishedRef.current = true; dialog.current?.close(); }} // marks it finished and closes the box,
                  className={`rounded-full px-5 py-2 text-sm font-semibold text-white ${theme.strongBg}`} // a rounded button in the dashboard's deep colour,
                  autoFocus // and has the keyboard focus.
                >{/* (end of the button's settings) */}
                  Finish{/* its words. */}
                </button> // End of the finish button.
              )}{/* End of the main button. */}
            </div>{/* End of the right-hand buttons. */}
          </div>{/* End of the bottom row. */}
        </div>{/* End of the contents. */}
      </dialog>{/* End of the dialog box. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of AppTour.
