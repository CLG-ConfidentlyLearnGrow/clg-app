// Summary: the top bar on every page (moved out of the page frame and
// redesigned for phones, Carla 16 Nov 2026).
//
// On a computer (wide screens) it looks as before: the logo on the left, then
// Home, Child safety, Feedback, Your privacy and Report app issue in a row,
// with who is signed in and Sign out at the end.
//
// On a phone or small tablet that row didn't fit and wrapped into a messy
// stack, so the bar now holds just three things: the logo on the left, the
// red Child safety button (always one tap away, because raising a concern
// must be quick), and a Menu button. The Menu button opens a panel with
// Home, Feedback, Your privacy, Report app issue, who is signed in, and
// Sign out, each on its own large row that's easy to tap.
//
// The logo keeps its true shape at every size (it used to get squeezed
// narrower on phones when the links took up the space).
//
import Image from "next/image"; // Next.js picture tag (loads images quickly).
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { Suspense } from "react"; // Lets part of the bar wait for the page address without holding up the rest.
import { signOut } from "@/app/actions/auth"; // The sign-out action.
import type { Viewer } from "@/lib/auth"; // The shape of the signed-in person's details (for type checking only).
import { CountBadge } from "@/components/count-badge"; // The small number badge.
import { ReportProblemLink } from "@/components/report-problem-link"; // The "Report app issue" link (remembers the page you were on).
import { HeaderMenu } from "@/components/header-menu"; // The phone Menu button and its panel.

// The look of a top bar link on a computer.
const WIDE_LINK = "text-sm font-medium text-teal-800 underline-offset-4 hover:underline"; // Small bronze words, underlined on hover.
// The look of a link in the phone menu panel: a full-width row at least 48 pixels tall.
const ROW_LINK = "flex min-h-12 items-center rounded-lg px-3 text-base font-medium text-zinc-800 transition hover:bg-teal-50 hover:text-teal-800"; // Larger words, a soft bronze tint on hover.

// The links that sit in the top bar (or in the phone menu), apart from Child safety.
const LINKS = [ // Each link's address and words, in the order shown:
  { href: "/dashboard", label: "Home" }, // your dashboard,
  { href: "/feedback", label: "Feedback" }, // feedback (open to everyone signed in, Carla 15 Nov 2026),
  { href: "/my-privacy", label: "Your privacy" }, // your privacy page.
]; // ("Report app issue" is added separately, because it remembers the page you were on.)

// The red Child safety button, used in both layouts.
function ChildSafetyLink({ href, count }: { href: string; count: number | undefined }) {
  return ( // Shows:
    <Link // the link, in red so it stands out:
      href={href} // to the right safety page,
      className="inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-full border border-red-700 px-3 text-sm font-semibold whitespace-nowrap text-red-800 transition hover:bg-red-50" // a red outlined pill that never wraps onto two lines,
    >{/* (end of the link's settings) */}
      Child safety{/* its words, */}
      <CountBadge n={count} className="bg-red-700 text-white" />{/* and the number of new concerns and flags, if any. */}
    </Link> // End of the link.
  ); // End of what's shown.
} // End of ChildSafetyLink.

// The whole top bar. It's given the signed-in person (or nobody) and their
// new safety items, which the page frame has already looked up.
export function SiteHeader({ viewer, newConcerns, newFlags }: { viewer: Viewer | null; newConcerns: number | undefined; newFlags: number | undefined }) {
  const safetyCount = (newConcerns ?? 0) + (newFlags ?? 0) || undefined; // New concerns and flags added together for the badge (nothing when zero).
  const safetyHref = newConcerns ? "/safety/concerns" : newFlags ? "/safety/flags" : "/safety"; // Child safety goes to new concerns first, then flagged words (officer or deputy), otherwise the concern page.
  return ( // Shows:
    <header className="relative border-b border-zinc-200 bg-white/90 backdrop-blur">{/* the top bar (the phone menu panel opens just under it): */}
      <div className="mx-auto flex w-full max-w-6xl items-center gap-3 px-4 py-2 lg:py-3">{/* its inner row, centred: */}
        <Link href="/dashboard" className="flex shrink-0 items-center gap-3" aria-label="CLG Tutoring home">{/* the logo, linking home, never squeezed narrower: */}
          <Image src="/brand/clg-logo-book.png" alt="" width={453} height={256} priority className="h-11 w-auto shrink-0 sm:h-14 lg:h-16" />{/* the open-book logo picture, keeping its true shape (wider than tall), */}
          <span className="hidden text-xs text-zinc-600 sm:block">Confidently Learn &amp; Grow</span>{/* the company name (hidden on phones). */}
        </Link>{/* End of the logo link. */}
        {viewer && ( // If someone is signed in:
          <>{/* the two menu layouts (only one shows at a time): */}
            <nav aria-label="Main" className="ml-auto hidden items-center gap-x-4 lg:flex">{/* on a computer, the full row of links: */}
              <Link href={LINKS[0].href} className={WIDE_LINK}>{LINKS[0].label}</Link>{/* Home, */}
              <ChildSafetyLink href={safetyHref} count={safetyCount} />{/* the red Child safety button, */}
              {LINKS.slice(1).map((link) => ( // then each remaining link:
                <Link key={link.href} href={link.href} className={WIDE_LINK}>{link.label}</Link> // Feedback and Your privacy,
              ))}{/* end of the links, */}
              <Suspense fallback={<Link href="/report-problem" className={WIDE_LINK}>Report app issue</Link>}>{/* then "Report app issue" (a plain link while the page address loads), */}
                <ReportProblemLink />{/* which remembers the page you were on. */}
              </Suspense>{/* End of the report link. */}
              {/* Who is signed in sits above Sign out, in small grey text, so it
                  doesn't look like another menu link. */}
              <div className="flex flex-col items-end gap-0.5 border-l border-zinc-200 pl-4 text-right">{/* The signed-in box: */}
                <span className="text-[11px] leading-tight text-zinc-500">Signed in as</span>{/* "Signed in as", */}
                <Link href="/my-name" className="max-w-[10rem] truncate text-xs leading-tight text-zinc-700 underline-offset-2 hover:underline" title={`${viewer.fullName} (change your name)`}>{/* their name, linking to the page to change it (cut short if long, full name on hover): */}
                  {viewer.fullName}{/* the name itself, */}
                </Link>{/* end of the name. */}
                <form action={signOut} className="mt-1">{/* the sign-out form: */}
                  <button type="submit" className="rounded-full border border-zinc-300 bg-white px-3 py-0.5 text-xs text-zinc-700 transition hover:border-teal-700 hover:text-teal-800">{/* its small rounded button: */}
                    Sign out{/* its words, */}
                  </button>{/* end of the button. */}
                </form>{/* End of the form. */}
              </div>{/* End of the signed-in box. */}
            </nav>{/* End of the computer layout. */}
            <div className="ml-auto flex items-center gap-2 lg:hidden">{/* on a phone or tablet, just two buttons on the right: */}
              <ChildSafetyLink href={safetyHref} count={safetyCount} />{/* the red Child safety button (one tap away), */}
              <HeaderMenu>{/* and the Menu button, whose panel holds: */}
                <nav aria-label="Main" className="flex flex-col py-1">{/* the links, one per row: */}
                  {LINKS.map((link) => ( // each link:
                    <Link key={link.href} href={link.href} className={ROW_LINK}>{link.label}</Link> // Home, Feedback, Your privacy,
                  ))}{/* end of the links, */}
                  <Suspense fallback={<Link href="/report-problem" className={ROW_LINK}>Report app issue</Link>}>{/* and "Report app issue" (a plain link while the page address loads), */}
                    <ReportProblemLink className={ROW_LINK} />{/* which remembers the page you were on. */}
                  </Suspense>{/* End of the report link. */}
                </nav>{/* End of the links. */}
                <div className="mt-1 flex items-center justify-between gap-3 border-t border-zinc-200 px-3 pt-3 pb-2">{/* Then, under a line, who is signed in and Sign out side by side: */}
                  <div className="min-w-0">{/* the name part (allowed to shrink): */}
                    <p className="text-xs text-zinc-500">Signed in as</p>{/* "Signed in as", */}
                    <Link href="/my-name" className="block truncate text-sm font-medium text-zinc-800 underline-offset-2 hover:underline" title={`${viewer.fullName} (change your name)`}>{/* their name, linking to the page to change it (cut short if very long): */}
                      {viewer.fullName}{/* the name itself, */}
                    </Link>{/* end of the name. */}
                  </div>{/* End of the name part. */}
                  <form action={signOut} className="shrink-0">{/* the sign-out form: */}
                    <button type="submit" className="min-h-11 rounded-full border border-zinc-300 bg-white px-4 text-sm text-zinc-700 transition hover:border-teal-700 hover:text-teal-800">{/* its rounded button, at least 44 pixels tall: */}
                      Sign out{/* its words, */}
                    </button>{/* end of the button. */}
                  </form>{/* End of the form. */}
                </div>{/* End of the signed-in row. */}
              </HeaderMenu>{/* End of the Menu button. */}
            </div>{/* End of the phone layout. */}
          </>/* End of the two layouts. */
        )}{/* End of the signed-in part. */}
      </div>{/* End of the inner row. */}
    </header> // End of the top bar.
  ); // End of what's shown.
} // End of SiteHeader.
