import type { Metadata, Viewport } from "next";
import Image from "next/image";
import Link from "next/link";
import { Poppins } from "next/font/google";
import { signOut } from "@/app/actions/auth";
import { FRONT_DESK, getAdminLevel, getViewer } from "@/lib/auth";
import { EmailLinkCatcher } from "@/components/email-link-catcher";
import "./globals.css";

const poppins = Poppins({
  variable: "--font-poppins",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  title: "CLG Tutoring",
  description: "Confidently Learn Grow: tutoring and learning support.",
};

export const viewport: Viewport = {
  themeColor: "#ffffff",
};

export default async function RootLayout({ children }: LayoutProps<"/">) {
  const viewer = await getViewer();
  // Matching is one of an admin's main jobs, so it sits in the top bar.
  const adminLevel = viewer?.roles.includes("admin") ? await getAdminLevel() : null;
  const canMatch = adminLevel !== null && FRONT_DESK.includes(adminLevel);
  return (
    <html lang="en-AU" className={`${poppins.variable} h-full antialiased`}>
      <body className="flex min-h-full flex-col bg-cream font-sans text-charcoal">
        <EmailLinkCatcher />
        <header className="border-b border-zinc-200 bg-white/90 backdrop-blur">
          <div className="mx-auto flex w-full max-w-6xl items-center gap-3 px-4 py-3">
            <Link href="/dashboard" className="flex items-center gap-3" aria-label="CLG Tutoring home">
              <Image src="/brand/clg-logo-book.png" alt="" width={453} height={256} priority className="h-14 w-auto sm:h-16" />
              <span className="hidden text-xs text-zinc-600 sm:block">Confidently Learn &amp; Grow</span>
            </Link>
            {viewer && (
              <div className="ml-auto flex flex-wrap items-center justify-end gap-x-3 gap-y-1">
                <Link href="/dashboard" className="text-sm font-medium text-teal-800 underline-offset-4 hover:underline">
                  Home
                </Link>
                <Link href="/schedule" className="text-sm font-medium text-teal-800 underline-offset-4 hover:underline">
                  Sessions
                </Link>
                {canMatch && (
                  <Link href="/matching" className="text-sm font-medium text-teal-800 underline-offset-4 hover:underline">
                    Matching
                  </Link>
                )}
                <Link href="/my-privacy" className="text-sm font-medium text-teal-800 underline-offset-4 hover:underline">
                  Your privacy
                </Link>
                {/* Who is signed in sits above Sign out, in small grey text, so it
                    doesn't look like another menu link. */}
                <div className="flex flex-col items-end gap-0.5 border-l border-zinc-200 pl-3 text-right">
                  <span className="text-[11px] leading-tight text-zinc-500">Signed in as</span>
                  <span className="max-w-[10rem] truncate text-xs leading-tight text-zinc-700" title={viewer.fullName}>
                    {viewer.fullName}
                  </span>
                  <form action={signOut} className="mt-1">
                    <button
                      type="submit"
                      className="rounded-full border border-zinc-300 bg-white px-3 py-0.5 text-xs text-zinc-700 transition hover:border-teal-700 hover:text-teal-800"
                    >
                      Sign out
                    </button>
                  </form>
                </div>
              </div>
            )}
          </div>
        </header>
        <div className="flex-1">{children}</div>
        <footer className="mt-12 border-t border-zinc-200 py-6 text-center text-xs text-zinc-500">
          <p>CLG Tutoring · Confidently Learn &amp; Grow</p>
          <p className="mt-2 space-x-4">
            <Link href="/install" className="underline underline-offset-4">
              Add CLG to your home screen
            </Link>
            <Link href="/privacy" className="underline underline-offset-4">
              Privacy
            </Link>
          </p>
        </footer>
      </body>
    </html>
  );
}
