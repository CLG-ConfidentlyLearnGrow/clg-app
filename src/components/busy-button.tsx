// Summary: buttons that switch off and show a spinner while their form saves,
// so a press can't be repeated by accident.
//
"use client"; // Marks this file as code that runs in the browser.

import { useFormStatus } from "react-dom"; // React's helper that says whether the surrounding form is busy.
import type { ComponentProps } from "react"; // The type for a normal button's settings.

// Buttons that show the person their press is being worked on.
//
// While the form a button sits in is saving, every submit button in that
// form is switched off, so it can't be pressed again and again. The button
// that was pressed also shows a small spinning circle. This works on its own
// in any form that runs a server action: no extra code is needed on the page.

type Props = ComponentProps<"button"> & { // A button's settings are a normal button's, plus:
  // For a very small button (such as a tick box), show only the spinner
  // while it works, in place of the button's own content.
  spinnerOnly?: boolean; // show only the spinner while busy (optional).
}; // End of the settings.

// Works out whether this button's form is saving, and whether this is the
// button that was pressed. A form can have several buttons that share a name
// (for example "accept" and "decline"); the pressed one is the one whose
// value was sent.
function useBusy({ type, name, value }: Pick<Props, "type" | "name" | "value">) {
  const { pending, data } = useFormStatus(); // Whether the form is busy, and what it sent.
  const isSubmit = (type ?? "submit") === "submit"; // True for submit buttons (the default kind).
  if (!pending || !isSubmit) return { formBusy: false, pressed: false }; // Not busy, or not a submit button: nothing to show.
  const pressed = name ? data?.get(name) === String(value ?? "") : true; // With a name, it's the pressed one if its value was sent; without one, it's assumed pressed.
  return { formBusy: true, pressed }; // Busy, and whether this one was pressed.
} // End of useBusy.

// A small spinning circle shown while something is working.
export function Spinner() {
  return ( // Shows:
    <svg className="h-4 w-4 shrink-0 animate-spin" viewBox="0 0 24 24" fill="none" aria-hidden>{/* a small drawing that spins (hidden from screen readers), */}
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.25" strokeWidth="3" />{/* a faint full circle, */}
      <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />{/* and a darker quarter arc that appears to spin. */}
    </svg> // End of the drawing.
  ); // End of what's shown.
} // End of Spinner.

// What goes inside a button: its own words, or the spinner while it works.
function Content({ pressed, spinnerOnly, children }: { pressed: boolean; spinnerOnly?: boolean; children: Props["children"] }) {
  if (!pressed) return <>{children}</>; // Not pressed: just the button's own content.
  if (spinnerOnly) { // Pressed, spinner-only buttons:
    return ( // show:
      <>{/* (a group with no box of its own) */}
        <Spinner />{/* the spinner, */}
        <span className="sr-only">Working on it</span>{/* and words only screen readers hear. */}
      </> // End of the group.
    ); // End of what's shown.
  } // End of the spinner-only case.
  return ( // Other pressed buttons show:
    <span className="inline-flex items-center gap-2">{/* a row holding: */}
      <Spinner />{/* the spinner, */}
      {children}{/* the button's own words, */}
      <span className="sr-only">(working on it)</span>{/* and words only screen readers hear. */}
    </span> // End of the row.
  ); // End of what's shown.
} // End of Content.

// A button with no styling of its own: pass the look in className. Use it
// for link-style or small buttons that submit a form.
export function BusyButton({ spinnerOnly, className = "", disabled, children, ...props }: Props) {
  const { formBusy, pressed } = useBusy(props); // Whether the form is busy and this was pressed.
  return ( // Shows:
    <button // a button:
      {...props} // with every setting passed in,
      disabled={disabled || formBusy} // switched off if asked or while the form is busy,
      aria-busy={pressed || undefined} // telling screen readers it's busy when pressed,
      className={`${className}${pressed ? " cursor-wait" : ""}${formBusy ? " disabled:opacity-60" : ""}`} // with the passed-in look, a waiting cursor when pressed, and faded when off.
    >{/* (end of the button's settings) */}
      <Content pressed={pressed} spinnerOnly={spinnerOnly}>{/* Its content (or spinner): */}
        {children}{/* the button's own words. */}
      </Content>{/* End of the content. */}
    </button> // End of the button.
  ); // End of what's shown.
} // End of BusyButton.

// The app's main (teal, rounded) button.
export function Button({ spinnerOnly, disabled, children, ...props }: Props) {
  const { formBusy, pressed } = useBusy(props); // Whether the form is busy and this was pressed.
  return ( // Shows:
    <button // a button:
      className={`shrink-0 rounded-full bg-teal-700 px-5 py-2.5 text-sm font-medium whitespace-nowrap text-white shadow-sm transition hover:bg-teal-900 hover:font-bold hover:shadow-md disabled:opacity-50 disabled:hover:bg-teal-700 disabled:hover:font-medium${pressed ? " cursor-wait" : ""}`} // teal, rounded, white text, darker and bold on hover, faded when off, waiting cursor when pressed,
      {...props} // with every setting passed in,
      disabled={disabled || formBusy} // switched off if asked or while the form is busy,
      aria-busy={pressed || undefined} // telling screen readers it's busy when pressed.
    >{/* (end of the button's settings) */}
      <Content pressed={pressed} spinnerOnly={spinnerOnly}>{/* Its content (or spinner): */}
        {children}{/* the button's own words. */}
      </Content>{/* End of the content. */}
    </button> // End of the button.
  ); // End of what's shown.
} // End of Button.
