// Summary: the loading screen shown while a page is getting ready (Carla,
// 22 Nov 2026: "Loading screen shows 'Confidently Learn and Grow' under the
// logo"). Next.js shows this straight away when someone opens a page, and
// swaps in the page when it is ready. The top bar stays in place.
//
import Image from "next/image"; // Next.js picture tag (loads images quickly).

// The loading screen: the CLG logo, the words "Confidently Learn and Grow"
// under it, and a small spinning circle so people know the app is working.
export default function Loading() {
  return ( // Shows:
    <div role="status" aria-live="polite" className="flex min-h-[50vh] flex-col items-center justify-center gap-3 py-12">{/* a centred block that screen readers announce: */}
      <Image src="/brand/clg-logo-book.png" alt="CLG" width={453} height={256} priority className="h-20 w-auto" />{/* the open-book logo, keeping its true shape, */}
      <p className="text-base font-medium text-zinc-700">Confidently Learn and Grow</p>{/* the words under the logo, */}
      <span aria-hidden="true" className="mt-2 h-6 w-6 animate-spin rounded-full border-2 border-zinc-300 border-t-brand" />{/* a small spinning circle (hidden from screen readers), */}
      <span className="sr-only">Loading</span>{/* and the word "Loading" for screen readers only. */}
    </div> // End of the block.
  ); // End of what is shown.
} // End of Loading.
