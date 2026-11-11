// Summary: finishes signing in from a password reset link whose details
// arrive after the "#" in the address.
//
"use client"; // Marks this file as code that runs in the browser.

import { useEffect } from "react"; // React's tool for running code once the page has appeared.
import { signInFromEmailLink } from "@/app/actions/auth"; // The server step that finishes signing in.

// Password reset links can arrive with the sign-in after the "#" in the
// address. Browsers never send that part to the server, so this picks it up,
// removes it from the address bar and finishes signing in.
export function EmailLinkCatcher() {
  useEffect(() => { // Runs once, after the page appears:
    const hash = window.location.hash.slice(1); // the part of the address after "#",
    if (!hash.includes("access_token=") && !hash.includes("error_code=")) return; // not a sign-in or error link: nothing to do.
    const params = new URLSearchParams(hash); // Reads its details.
    window.history.replaceState(null, "", window.location.pathname + window.location.search); // Removes the "#" part from the address bar, so it isn't left on screen.

    if (params.get("error_code") || params.get("error")) { // The link failed or expired:
      window.location.replace("/login?link=expired"); // goes to the login page saying so,
      return; // and stops.
    } // End of the failure case.
    void signInFromEmailLink( // Finishes signing in on the server, with:
      params.get("access_token") ?? "", // the sign-in pass,
      params.get("refresh_token") ?? "", // the refresh pass,
      params.get("type") ?? "", // and the kind of link.
    ); // End of the sign-in step.
  }, []); // The empty list means "run once only".
  return null; // Shows nothing on the page.
} // End of EmailLinkCatcher.
