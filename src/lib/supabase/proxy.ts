import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

// Paths anyone may open without signing in.
const PUBLIC_PATHS = [
  "/",
  "/login",
  "/signup",
  // Staff invite links (each checks its own secret).
  "/join",
  "/forgot-password",
  "/check-email",
  "/privacy",
  "/install",
  "/manifest.webmanifest",
  "/auth/confirm",
  "/auth/continue",
  // Billing messages from Stripe and Xero, and the daily run. Each checks
  // its own signature or secret instead of a login.
  "/api/billing/stripe",
  "/api/billing/xero/webhook",
  "/api/billing/cron",
  // The daily Teams links run (checks the same secret).
  "/api/teams/cron",
  // The daily progress tidy-up (checks the same secret).
  "/api/progress/cron",
  // The email sender, woken by the database (checks the same secret).
  "/api/email/cron",
];

// Keeps the Supabase session fresh on every request and sends signed-out
// visitors to the login page.
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(supabaseUrl(), supabasePublishableKey(), {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, headers) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
        Object.entries(headers ?? {}).forEach(([key, value]) =>
          response.headers.set(key, value),
        );
      },
    },
  });

  // Do not put code between createServerClient and getClaims: it refreshes
  // the session cookie.
  const { data } = await supabase.auth.getClaims();
  const signedIn = Boolean(data?.claims?.sub);

  const path = request.nextUrl.pathname;

  // If Supabase sends an email link back to the wrong page (for example the
  // home page, when the address isn't in its Redirect URLs list), pass it on
  // to the page that handles email links.
  const params = request.nextUrl.searchParams;
  if (path !== "/auth/confirm" && (params.has("code") || params.has("error_code"))) {
    const url = request.nextUrl.clone();
    url.pathname = "/auth/confirm";
    return NextResponse.redirect(url);
  }

  if (!signedIn && !PUBLIC_PATHS.includes(path)) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    return NextResponse.redirect(url);
  }

  return response;
}
