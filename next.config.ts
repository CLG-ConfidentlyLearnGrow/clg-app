import type { NextConfig } from "next";

// The Supabase address, so pages may talk to it (and to its live updates).
function supabaseHost(): string | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) return null;
  try {
    return new URL(url).host;
  } catch {
    return null;
  }
}
const supabase = supabaseHost();

// Content Security Policy: tells the browser to run only the app's own code,
// load images only from the app or Supabase, send form data only to the app
// or Stripe's payment page, and never show the app inside another website.
// This blocks most injected-script attacks (OWASP A03). No nonces are used,
// so pages stay fast and cacheable. "unsafe-eval" is allowed only while
// developing on your own computer.
const isDev = process.env.NODE_ENV === "development";
const contentSecurityPolicy = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  `img-src 'self' blob: data:${supabase ? ` https://${supabase}` : ""}`,
  "font-src 'self'",
  `connect-src 'self'${supabase ? ` https://${supabase} wss://${supabase}` : ""}`,
  "frame-src 'none'",
  "worker-src 'self'",
  "manifest-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self' https://checkout.stripe.com",
  "frame-ancestors 'none'",
].join("; ");

// Security headers sent with every page.
const securityHeaders = [
  { key: "Content-Security-Policy", value: contentSecurityPolicy },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(), interest-cohort=()" },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  experimental: {
    serverActions: {
      // Curriculum loads (about 1MB) and certificate copies (up to 3.5MB). Vercel caps requests at 4.5MB.
      bodySizeLimit: "4mb",
    },
  },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
