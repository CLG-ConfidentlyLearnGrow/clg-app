"use client";

import { useFormStatus } from "react-dom";
import type { ComponentProps } from "react";

// Buttons that show the person their press is being worked on.
//
// While the form a button sits in is saving, every submit button in that
// form is switched off, so it can't be pressed again and again. The button
// that was pressed also shows a small spinning circle. This works on its own
// in any form that runs a server action: no extra code is needed on the page.

type Props = ComponentProps<"button"> & {
  // For a very small button (such as a tick box), show only the spinner
  // while it works, in place of the button's own content.
  spinnerOnly?: boolean;
};

// Works out whether this button's form is saving, and whether this is the
// button that was pressed. A form can have several buttons that share a name
// (for example "accept" and "decline"); the pressed one is the one whose
// value was sent.
function useBusy({ type, name, value }: Pick<Props, "type" | "name" | "value">) {
  const { pending, data } = useFormStatus();
  const isSubmit = (type ?? "submit") === "submit";
  if (!pending || !isSubmit) return { formBusy: false, pressed: false };
  const pressed = name ? data?.get(name) === String(value ?? "") : true;
  return { formBusy: true, pressed };
}

export function Spinner() {
  return (
    <svg className="h-4 w-4 shrink-0 animate-spin" viewBox="0 0 24 24" fill="none" aria-hidden>
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.25" strokeWidth="3" />
      <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

function Content({ pressed, spinnerOnly, children }: { pressed: boolean; spinnerOnly?: boolean; children: Props["children"] }) {
  if (!pressed) return <>{children}</>;
  if (spinnerOnly) {
    return (
      <>
        <Spinner />
        <span className="sr-only">Working on it</span>
      </>
    );
  }
  return (
    <span className="inline-flex items-center gap-2">
      <Spinner />
      {children}
      <span className="sr-only">(working on it)</span>
    </span>
  );
}

// A button with no styling of its own: pass the look in className. Use it
// for link-style or small buttons that submit a form.
export function BusyButton({ spinnerOnly, className = "", disabled, children, ...props }: Props) {
  const { formBusy, pressed } = useBusy(props);
  return (
    <button
      {...props}
      disabled={disabled || formBusy}
      aria-busy={pressed || undefined}
      className={`${className}${pressed ? " cursor-wait" : ""}${formBusy ? " disabled:opacity-60" : ""}`}
    >
      <Content pressed={pressed} spinnerOnly={spinnerOnly}>
        {children}
      </Content>
    </button>
  );
}

// The app's main (teal, rounded) button.
export function Button({ spinnerOnly, disabled, children, ...props }: Props) {
  const { formBusy, pressed } = useBusy(props);
  return (
    <button
      className={`shrink-0 rounded-full bg-teal-700 px-5 py-2.5 text-sm font-medium whitespace-nowrap text-white shadow-sm transition hover:bg-teal-900 hover:font-bold hover:shadow-md disabled:opacity-50 disabled:hover:bg-teal-700 disabled:hover:font-medium${pressed ? " cursor-wait" : ""}`}
      {...props}
      disabled={disabled || formBusy}
      aria-busy={pressed || undefined}
    >
      <Content pressed={pressed} spinnerOnly={spinnerOnly}>
        {children}
      </Content>
    </button>
  );
}
