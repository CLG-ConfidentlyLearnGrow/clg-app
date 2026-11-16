// Summary: the frame around every page: fonts, page title, the top bar
// (logo, Home, Child safety, privacy and "Report app issue" links, who is
// signed in, sign out; built in src/components/site-header.tsx, with a Menu
// button on phones since 16 Nov 2026) and the footer.
// "Child safety" is on every page for everyone signed in, so a concern can
// always be raised quickly (Carla, 12 Nov 2026).
// Sessions and Matching are tabs in each dashboard's side menu now (Carla, 12 Nov 2026).
//
import type { Metadata, Viewport } from "next"; // Types for page details and screen settings.
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { Poppins } from "next/font/google"; // Loads the Poppins font from Google.
import { getViewer } from "@/lib/auth"; // Reads who is signed in.
import { getToDoCounts } from "@/lib/to-do-counts"; // Reads the to-do numbers (for new child safety concerns).
import { SiteHeader } from "@/components/site-header"; // The top bar (with the phone Menu button).
import { EmailLinkCatcher } from "@/components/email-link-catcher"; // Catches sign-in links opened from emails.
import { PressFeedback } from "@/components/press-feedback"; // Shows every press of a button or link straight away, and a loading bar while a page opens.
import { Suspense } from "react"; // Lets the press feedback wait for the page address without holding up the rest of the page.
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
  const counts = viewer ? await getToDoCounts(viewer.roles) : undefined; // The to-do numbers (for the Child safety button in the top bar).
  const newConcerns = counts?.get("safety", "concerns"); // New child safety concerns sent to this person (only the officer and deputy ever have any).
  const newFlags = counts?.get("safety", "word_flags"); // Flagged words not yet reviewed (only the officer and deputy ever have any).
  return ( // Shows:
    <html lang="en-AU" className={`${poppins.variable} h-full antialiased`}>{/* the whole page, in Australian English, with the font, */}
      <body className="flex min-h-full flex-col bg-cream font-sans text-charcoal">{/* the page body in the brand colours, */}
        <EmailLinkCatcher />{/* the email sign-in link catcher, */}
        <Suspense fallback={null}><PressFeedback /></Suspense>{/* the pressed look for every button and link, and the loading bar (waits for the page address, showing nothing meanwhile), */}
        <SiteHeader viewer={viewer} newConcerns={newConcerns} newFlags={newFlags} />{/* the top bar (logo, links, Child safety, who is signed in; a Menu button on phones), */}
        <div className="flex-1">{children}</div>{/* The page's own content, filling the space. */}
        <footer className="mt-12 border-t border-zinc-200 py-6 text-center text-xs text-zinc-500">{/* The footer: */}
          <p>CLG Tutoring · Confidently Learn &amp; Grow</p>{/* the company name, */}
          <p className="mt-2 space-x-4">{/* a line of links: */}
            <Link href="/install" className="underline underline-offset-4">{/* the install link: */}
              Add CLG to your home screen{/* its words, */}
            </Link>{/* end of the link. */}
            {viewer && ( // only for people signed in:
              <Link href="/whats-new" className="underline underline-offset-4">{/* the "What's new" link (every update for their dashboards, Carla 15 Nov 2026): */}
                What is new{/* its words, */}
              </Link> // end of the link.
            )}{/* End of the signed-in link. */}
            <Link href="/privacy" className="underline underline-offset-4">{/* the privacy link: */}
              Privacy{/* its words, */}
            </Link>{/* end of the link. */}
          </p>{/* End of the line. */}
        </footer>{/* End of the footer. */}
      </body>{/* End of the page body. */}
    </html> // End of the whole page.
  ); // End of what's shown.
} // End of RootLayout.
