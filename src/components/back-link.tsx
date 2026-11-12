// Summary: a "Back" button that returns to the previous page, or the home page.
//
"use client"; // Marks this file as code that runs in the browser.

import { useRouter } from "next/navigation"; // Next.js's tool for moving between pages from code.

// "Back" that returns to the page the person came from (for example the
// sign-up or agree form, with what they typed still there), or to the home
// page when the page was opened on its own.
export function BackLink({ label = "Back" }: { label?: string }) {
  const router = useRouter(); // Gets the page mover.
  return ( // Shows:
    <button // a button:
      type="button" // that doesn't send any form,
      onClick={() => (window.history.length > 1 ? router.back() : router.push("/"))} // that goes back if there's a page to go back to, otherwise home,
      className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 transition hover:decoration-teal-700" // styled like a link.
    >{/* (end of the button's settings) */}
      {label}{/* The button's words. */}
    </button> // End of the button.
  ); // End of what's shown.
} // End of BackLink.
