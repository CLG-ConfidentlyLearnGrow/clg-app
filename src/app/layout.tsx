import type { Metadata, Viewport } from "next";
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
  themeColor: "#414042",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en-AU" className={`${poppins.variable} h-full antialiased`}>
      <body className="flex min-h-full flex-col bg-cream font-sans text-charcoal">
        <header className="border-b-4 border-brand bg-charcoal">
          <div className="mx-auto flex w-full max-w-3xl items-baseline gap-3 px-4 py-3">
            <Link href="/dashboard" className="text-xl font-semibold tracking-wide text-cream">
              CLG
            </Link>
            <span className="text-sm text-teal-300">Confidently Learn Grow</span>
          </div>
        </header>
        {children}
      </body>
    </html>
  );
}
