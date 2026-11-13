// Summary: the frame around every page: fonts, page title, the top bar
// (logo, Home, Child safety and privacy links, who is signed in, sign out) and the footer.
// "Child safety" is on every page for everyone signed in, so a concern can
// always be raised quickly (Carla, 12 Nov 2026).
// Sessions and Matching are tabs in each dashboard's side menu now (Carla, 12 Nov 2026).
//
import type { Metadata, Viewport } from "next"; // Types for page details and screen settings.
import Image from "next/image"; // Next.js picture tag (loads images quickly).
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { Poppins } from "next/font/google"; // Loads the Poppins font from Google.
import { signOut } from "@/app/actions/auth"; // The sign-out action.
import { getViewer } from "@/lib/auth"; // Reads who is signed in.
import { getToDoCounts } from "@/lib/to-do-counts"; // Reads the to-do numbers (for new child safety concerns).
import { CountBadge } from "@/components/count-badge"; // The small number badge.
import { EmailLinkCatcher } from "@/components/email-link-catcher"; // Catches sign-in links opened from emails.
import "./globals.css"; // The app-wide styles.

const poppins = Poppins({ // Sets up the Poppins font:
  variable: "--font-poppins", // named so the styles can use it,
  subsets: ["latin"], // with English letters,
  weight: ["400", "500", "600", "700"], // in four weights (normal to bold).
}); // End of the font setup.

export const metadata: Metadata = { // The page details for browsers and search engines:
  title: "CLG Tutoring", // the browser tab title,
  description: "Confidently Learn Grow: tutoring and learning support.", // the short description.
}; // End of the page details.

export const viewport: Viewport = { // Screen settings:
  themeColor: "#ffffff", // the phone's top bar colour (white).
}; // End of the screen settings.

export default async function RootLayout({ children }: LayoutProps<"/">) { // The frame itself, wrapped around each page.
  const viewer = await getViewer(); // The signed-in person (or nobody).
  const newConcerns = viewer ? (await getToDoCounts(viewer.roles)).get("safety", "concerns") : undefined; // New child safety concerns sent to this person (only the officer and deputy ever have any).
  return ( // Shows:
    <html lang="en-AU" className={`${poppins.variable} h-full antialiased`}>{/* the whole page, in Australian English, with the font, */}
      <body className="flex min-h-full flex-col bg-cream font-sans text-charcoal">{/* the page body in the brand colours, */}
        <EmailLinkCatcher />{/* the email sign-in link catcher, */}
        <header className="border-b border-zinc-200 bg-white/90 backdrop-blur">{/* the top bar: */}
          <div className="mx-auto flex w-full max-w-6xl items-center gap-3 px-4 py-3">{/* its inner row, centred, */}
            <Link href="/dashboard" className="flex items-center gap-3" aria-label="CLG Tutoring home">{/* the logo, linking home: */}
              <Image src="/brand/clg-logo-book.png" alt="" width={453} height={256} priority className="h-14 w-auto sm:h-16" />{/* the open-book logo picture, */}
              <span className="hidden text-xs text-zinc-600 sm:block">Confidently Learn &amp; Grow</span>{/* the company name (hidden on small screens). */}
            </Link>{/* End of the logo link. */}
            {viewer && ( // If someone is signed in:
              <div className="ml-auto flex flex-wrap items-center justify-end gap-x-3 gap-y-1">{/* the menu on the right: */}
                <Link href="/dashboard" className="text-sm font-medium text-teal-800 underline-offset-4 hover:underline">{/* the Home link: */}
                  Home{/* its words, */}
                </Link>{/* end of the link. */}
                <Link // the Child safety link, in red so it stands out:
                  href={newConcerns ? "/safety/concerns" : "/safety"} // to new concerns if there are any (officer or deputy), otherwise the concern page,
                  className="inline-flex items-center gap-1.5 rounded-full border border-red-700 px-3 py-0.5 text-sm font-semibold text-red-800 transition hover:bg-red-50" // a red outlined pill,
                >{/* (end of the link's settings) */}
                  Child safety{/* its words, */}
                  <CountBadge n={newConcerns} className="bg-red-700 text-white" />{/* and the number of new concerns, if any. */}
                </Link>{/* end of the link. */}
                <Link href="/my-privacy" className="text-sm font-medium text-teal-800 underline-offset-4 hover:underline">{/* the privacy link: */}
                  Your privacy{/* its words, */}
                </Link>{/* end of the link. */}
                {/* Who is signed in sits above Sign out, in small grey text, so it
                    doesn't look like another menu link. */}
                <div className="flex flex-col items-end gap-0.5 border-l border-zinc-200 pl-3 text-right">{/* The signed-in box: */}
                  <span className="text-[11px] leading-tight text-zinc-500">Signed in as</span>{/* "Signed in as", */}
                  <span className="max-w-[10rem] truncate text-xs leading-tight text-zinc-700" title={viewer.fullName}>{/* their name (cut short if long, full name on hover): */}
                    {viewer.fullName}{/* the name itself, */}
                  </span>{/* end of the name. */}
                  <form action={signOut} className="mt-1">{/* the sign-out form: */}
                    <button // its button:
                      type="submit" // sends the form,
                      className="rounded-full border border-zinc-300 bg-white px-3 py-0.5 text-xs text-zinc-700 transition hover:border-teal-700 hover:text-teal-800" // styled as a small rounded button,
                    >{/* (end of the button's settings) */}
                      Sign out{/* its words, */}
                    </button>{/* end of the button. */}
                  </form>{/* End of the form. */}
                </div>{/* End of the signed-in box. */}
              </div> // End of the menu.
            )}{/* End of the signed-in part. */}
          </div>{/* End of the inner row. */}
        </header>{/* End of the top bar. */}
        <div className="flex-1">{children}</div>{/* The page's own content, filling the space. */}
        <footer className="mt-12 border-t border-zinc-200 py-6 text-center text-xs text-zinc-500">{/* The footer: */}
          <p>CLG Tutoring · Confidently Learn &amp; Grow</p>{/* the company name, */}
          <p className="mt-2 space-x-4">{/* a line of links: */}
            <Link href="/install" className="underline underline-offset-4">{/* the install link: */}
              Add CLG to your home screen{/* its words, */}
            </Link>{/* end of the link. */}
            <Link href="/privacy" className="underline underline-offset-4">{/* the privacy link: */}
              Privacy{/* its words, */}
            </Link>{/* end of the link. */}
          </p>{/* End of the line. */}
        </footer>{/* End of the footer. */}
      </body>{/* End of the page body. */}
    </html> // End of the whole page.
  ); // End of what's shown.
} // End of RootLayout.
