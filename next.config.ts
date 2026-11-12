// Summary: the app's Next.js settings: security headers sent with every page,
// the upload size limit, and the style tool.
//
import type { NextConfig } from "next"; // The type for Next.js settings.

// The Supabase address, so pages may talk to it (and to its live updates).
function supabaseHost(): string | null { // Gives the Supabase server's name, or nothing if it isn't set or is wrong.
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL; // The Supabase address from the settings.
  if (!url) return null; // Not set: nothing.
  try { // Tries to read it:
    return new URL(url).host; // gives back just the server name.
  } catch { // If it isn't a proper address:
    return null; // nothing.
  } // End of the fallback.
} // End of supabaseHost.
const supabase = supabaseHost(); // The Supabase server's name.

// Content Security Policy: tells the browser to run only the app's own code,
// load images only from the app or Supabase, send form data only to the app
// or Stripe's payment page, and never show the app inside another website.
// This blocks most injected-script attacks (OWASP A03). No nonces are used,
// so pages stay fast and cacheable. "unsafe-eval" is allowed only while
// developing on your own computer.
const isDev = process.env.NODE_ENV === "development"; // Whether the app is running on a developer's own computer.
const contentSecurityPolicy = [ // The rules, one per line:
  "default-src 'self'", // by default, only the app itself,
  `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`, // scripts only from the app (plus eval while developing),
  "style-src 'self' 'unsafe-inline'", // styles only from the app,
  `img-src 'self' blob: data:${supabase ? ` https://${supabase}` : ""}`, // images from the app, files made on the page, and Supabase,
  "font-src 'self'", // fonts only from the app,
  `connect-src 'self'${supabase ? ` https://${supabase} wss://${supabase}` : ""}`, // data and live updates only to the app and Supabase,
  "frame-src 'none'", // no other sites shown inside pages,
  "worker-src 'self'", // background workers only from the app,
  "manifest-src 'self'", // the install details only from the app,
  "object-src 'none'", // no plug-ins,
  "base-uri 'self'", // links in the page resolve only against the app,
  "form-action 'self' https://checkout.stripe.com", // forms only send to the app or Stripe's payment page,
  "frame-ancestors 'none'", // and no other site may show the app inside itself.
].join("; "); // Joined into one line.

// Security headers sent with every page. Location is allowed only for the
// app itself: tutors share it, when asked each time, to sign on to an
// in-person session. No other site embedded in a page can ask for it.
const securityHeaders = [ // The headers:
  { key: "Content-Security-Policy", value: contentSecurityPolicy }, // the content rules above,
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" }, // keeps other sites' windows apart from the app,
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" }, // always use a secure connection (for two years, including subdomains),
  { key: "X-Frame-Options", value: "DENY" }, // never show the app inside another site (older browsers),
  { key: "X-Content-Type-Options", value: "nosniff" }, // don't guess file types,
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" }, // send only the site name when following a link elsewhere,
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(self), interest-cohort=()" }, // no camera, no microphone, location only for the app, no ad tracking.
]; // End of the headers.

const nextConfig: NextConfig = { // The Next.js settings:
  poweredByHeader: false, // don't say the app runs on Next.js,
  experimental: { // early features:
    serverActions: { // server actions:
      // Curriculum loads (about 1MB) and certificate copies (up to 3.5MB). Vercel caps requests at 4.5MB.
      bodySizeLimit: "4mb", // the largest upload allowed.
    }, // (end of server actions)
  }, // (end of early features)
  turbopack: { // the build tool:
    rules: { // its rules:
      "*.css": { // for style files:
        loaders: ["@tailwindcss/turbopack"], // run them through Tailwind,
        as: "*.css", // and treat them as style files.
      }, // (end of the style rule)
    }, // (end of the rules)
  }, // (end of the build tool)
  async headers() { // the headers to send:
    return [{ source: "/:path*", headers: securityHeaders }]; // these security headers on every page.
  }, // (end of headers)
}; // End of the settings.

export default nextConfig; // Gives the settings to Next.js.
