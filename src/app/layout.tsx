import type { Metadata, Viewport } from "next";
import Image from "next/image";
import Link from "next/link";
import { Poppins } from "next/font/google";
import { signOut } from "@/app/actions/auth";
import { getViewer } from "@/lib/auth";
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
  return (
    <html lang="en-AU" className={`${poppins.variable} h-full antialiased`}>
      <body className="flex min-h-full flex-col bg-cream font-sans text-charcoal">
        <header className="border-b border-zinc-200 bg-white/90 backdrop-blur">
          <div className="mx-auto flex w-full max-w-6xl items-center gap-3 px-4 py-3">
            <Link href="/dashboard" className="flex items-center gap-3" aria-label="CLG Tutoring home">
              <Image src="/brand/clg-book.png" alt="" width={68} height={40} priority className="h-10 w-auto" />
              <span className="leading-tight">
                <span className="block text-sm font-semibold tracking-[0.3em] text-teal-700">CLG TUTORING</span>
                <span className="block text-xs text-zinc-600">Confidently Learn &amp; Grow</span>
              </span>
            </Link>
            {viewer && (
              <div className="ml-auto flex items-center gap-3">
                <span className="hidden text-sm text-zinc-600 sm:inline">{viewer.fullName}</span>
                <form action={signOut}>
                  <button
                    type="submit"
                    className="rounded-full border border-zinc-300 bg-white px-4 py-1.5 text-sm text-zinc-700 transition hover:border-teal-700 hover:text-teal-800"
                  >
                    Sign out
                  </button>
                </form>
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
