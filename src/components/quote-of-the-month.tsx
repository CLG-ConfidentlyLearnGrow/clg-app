// Summary: shares the quote of the month with the loading screen (Carla,
// 22 Nov 2026). The page frame reads it once and hands it down; the loading
// screen shows it under "Confidently Learn and Grow".
//
"use client"; // Runs in the browser, because the loading screen shows before the page arrives.

import { createContext, useContext, type ReactNode } from "react"; // React's way to share a value with everything inside.
import type { Quote } from "@/lib/quotes"; // The quote shape.

// The shared value: this month's quote, or nothing.
const MonthQuoteContext = createContext<Quote | null>(null); // Starts empty.

// Shares the quote with everything inside it.
export function MonthQuoteProvider({ quote, children }: { quote: Quote | null; children: ReactNode }) { // Takes the quote and the page inside.
  return <MonthQuoteContext.Provider value={quote}>{children}</MonthQuoteContext.Provider>; // Shares it.
} // End of MonthQuoteProvider.

// Shows the quote of the month (nothing if there is none).
export function MonthQuote() { // No inputs: it reads the shared quote.
  const quote = useContext(MonthQuoteContext); // The shared quote.
  if (!quote) return null; // None: shows nothing.
  return ( // Shows:
    <figure className="max-w-md px-4 text-center">{/* a centred block: */}
      <blockquote className="text-sm text-zinc-600 italic">“{quote.body}”</blockquote>{/* the quote, */}
      {quote.who && <figcaption className="mt-1 text-xs text-zinc-500">{quote.who}</figcaption>}{/* and who said it. */}
    </figure> // End of the block.
  ); // End of what is shown.
} // End of MonthQuote.
