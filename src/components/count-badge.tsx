// Summary: a small number badge for menus and tabs.
//
// A small number in a circle, for menus and tabs where something needs doing
// (e.g. "Matching 4"). Shows nothing when there's nothing to do. Screen
// readers hear "4 to do".
export function CountBadge({ n, className = "bg-zinc-700 text-white" }: { n: number | undefined; className?: string }) { // The badge: takes the number and, optionally, its colours.
  if (!n) return null; // Nothing to do (zero or no number): shows nothing.
  return ( // Shows:
    <span className={`inline-flex min-w-5 items-center justify-center rounded-full px-1.5 text-xs leading-5 ${className}`}>{/* a small rounded pill with the given colours, */}
      {n}{/* the number, */}
      <span className="sr-only"> to do</span>{/* and "to do", heard only by screen readers. */}
    </span> // End of the pill.
  ); // End of what's shown.
} // End of CountBadge.
