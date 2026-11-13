// Summary: the "Report a problem" link in the top bar. It remembers which
// page the person was on, so reviewers know where the problem happened.
//
"use client"; // Runs in the browser, so it can read the current page's address.

import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { usePathname, useSearchParams } from "next/navigation"; // Reads the current page's address and its settings.

// The link itself. On the report page it doesn't pass itself as "from".
export function ReportProblemLink() {
  const path = usePathname(); // The current page, e.g. "/schedule".
  const query = useSearchParams().toString(); // Its settings, e.g. "as=parent".
  const from = path === "/report-problem" ? "" : `${path}${query ? `?${query}` : ""}`; // The page to remember (none when already on the report page).
  return ( // Shows:
    <Link // the link:
      href={from ? `/report-problem?from=${encodeURIComponent(from)}` : "/report-problem"} // to the report page, with the page they were on,
      className="text-sm font-medium text-teal-800 underline-offset-4 hover:underline" // in the same style as the other top bar links,
    >{/* (end of the link's settings) */}
      Report a problem{/* its words, */}
    </Link> // end of the link.
  ); // End of what's shown.
} // End of ReportProblemLink.
