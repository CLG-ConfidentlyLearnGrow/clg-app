// Summary: a submit button for email-link forms that can only be pressed once.
//
"use client"; // Marks this file as code that runs in the browser.

import { useFormStatus } from "react-dom"; // React's helper that says whether the surrounding form is busy.
import { Button } from "@/components/ui"; // The main button.

// A submit button that can only be pressed once while the form is working.
// Email links work only once: a second press would use the link up and show
// "expired" even though the first press worked.
export function SubmitOnce({ label }: { label: string }) {
  const { pending } = useFormStatus(); // Whether the form is busy.
  return ( // Shows:
    <Button type="submit" disabled={pending} aria-busy={pending}>{/* the button, switched off while busy, telling screen readers it's busy, */}
      {pending ? "One moment…" : label}{/* showing "One moment…" while busy, otherwise its words. */}
    </Button> // End of the button.
  ); // End of what's shown.
} // End of SubmitOnce.
