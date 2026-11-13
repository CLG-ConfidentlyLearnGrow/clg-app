// Summary: runs before every page loads. It keeps the person's login fresh,
// passes stray email links to the right page, and sends signed-out visitors
// to the login page unless the page is public.

// The Supabase library's server connection maker.
import { createServerClient } from "@supabase/ssr";
// Next.js tools for reading the request and building the reply.
import { NextResponse, type NextRequest } from "next/server";
// The database's web address and public key.
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

// Paths anyone may open without signing in.
const PUBLIC_PATHS = [
  "/", // The home page.
  "/login", // The login page.
  "/signup", // The sign-up page.
  // Staff invite links (each checks its own secret).
  "/join", // The staff invite page.
  "/forgot-password", // The password reset request page.
  "/check-email", // The "check your email" page.
  "/privacy", // The privacy policy.
  "/install", // How to install the app.
  "/manifest.webmanifest", // The file that makes the app installable.
  "/auth/confirm", // Where email links land.
  "/auth/continue", // The step after an email link.
  // Billing messages from Stripe and Xero, and the daily run. Each checks
  // its own signature or secret instead of a login.
  "/api/billing/stripe", // Stripe's payment messages.
  "/api/billing/xero/webhook", // Xero's invoice messages.
  "/api/billing/cron", // The daily billing run.
  // The daily Teams links run (checks the same secret).
  "/api/teams/cron", // The Teams links job.
  // The daily progress tidy-up (checks the same secret).
  "/api/progress/cron", // The progress tidy-up job.
  // The email sender, woken by the database (checks the same secret).
  "/api/email/cron", // The email sending job.
  // The daily reports run (checks the same secret).
  "/api/reports/cron", // The monthly, quarterly and yearly reports job.
  // The daily problem reports tidy-up (checks the same secret).
  "/api/problems/cron", // Removes old problem report screenshots and reports.
]; // End of the public pages list.

// Keeps the Supabase session fresh on every request and sends signed-out
// visitors to the login page.
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request }); // By default, lets the request carry on to the page.

  const supabase = createServerClient(supabaseUrl(), supabasePublishableKey(), { // Connects to the database as the visitor,
    cookies: { // telling it how to read and write login cookies:
      getAll() { // To read them,
        return request.cookies.getAll(); // hands over the request's cookies.
      }, // End of getAll.
      setAll(cookiesToSet, headers) { // To save refreshed cookies:
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value)); // updates them on the request (so the page sees them),
        response = NextResponse.next({ request }); // rebuilds the reply with the updated request,
        cookiesToSet.forEach(({ name, value, options }) => // and for each cookie
          response.cookies.set(name, value, options), // saves it on the reply (so the browser keeps it).
        ); // End of the cookie loop.
        Object.entries(headers ?? {}).forEach(([key, value]) => // Also copies any extra headers Supabase asks for
          response.headers.set(key, value), // onto the reply (for example, "don't cache this").
        ); // End of the header loop.
      }, // End of setAll.
    }, // End of the cookie settings.
  }); // End of the connection settings.

  // Do not put code between createServerClient and getClaims: it refreshes
  // the session cookie.
  const { data } = await supabase.auth.getClaims(); // Checks the login and refreshes it if needed.
  const signedIn = Boolean(data?.claims?.sub); // True if a signed-in person was found.

  const path = request.nextUrl.pathname; // The page being asked for, e.g. "/admin".

  // If Supabase sends an email link back to the wrong page (for example the
  // home page, when the address isn't in its Redirect URLs list), pass it on
  // to the page that handles email links.
  const params = request.nextUrl.searchParams; // The extra bits after "?" in the address.
  if (path !== "/auth/confirm" && (params.has("code") || params.has("error_code"))) { // An email link has landed on the wrong page:
    const url = request.nextUrl.clone(); // Copies the address,
    url.pathname = "/auth/confirm"; // points it at the email link page,
    return NextResponse.redirect(url); // and sends the browser there.
  } // End of the stray link check.

  if (!signedIn && !PUBLIC_PATHS.includes(path)) { // Signed out and the page isn't public:
    const url = request.nextUrl.clone(); // Copies the address,
    url.pathname = "/login"; // points it at the login page,
    url.search = ""; // drops anything after "?",
    return NextResponse.redirect(url); // and sends the browser there.
  } // End of the sign-in check.

  return response; // Otherwise lets the page load as normal.
} // End of updateSession.
