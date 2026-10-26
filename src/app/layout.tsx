import type { Metadata, Viewport } from "next";
import Image from "next/image";
import Link from "next/link";
import { Poppins } from "next/font/google";
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

export default function RootLayout({ children }: LayoutProps<"/">) {
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
          </div>
        </header>
        <div className="flex-1">{children}</div>
        <footer className="mt-12 border-t border-zinc-200 py-6 text-center text-xs text-zinc-500">
          CLG Tutoring · Confidently Learn &amp; Grow
        </footer>
      </body>
    </html>
  );
}
