// Summary: a tutor's private calendar link (Carla, 12 Nov 2026). Google,
// Outlook and Apple calendars read this address every few hours and show
// the tutor's sessions. Calendar apps can't sign in, so the long secret in
// the address is the only key; the database checks it and gives back only
// that tutor's sessions, with the least detail needed (first name, subject,
// time, place, Teams link).
//
import { createClient } from "@supabase/supabase-js"; // The Supabase library's connection maker.
import { siteUrl, supabasePublishableKey, supabaseUrl } from "@/lib/env"; // The app's address, and the database's address and public key.
import { buildCalendar, type FeedSession } from "@/lib/tutor-calendar"; // Writes the calendar file, and a feed row's shape.

// Sends the calendar file for the secret in the address.
export async function GET(_request: Request, ctx: RouteContext<"/api/calendar/[token]">) { // Takes the request and the address's parts.
  const { token: raw } = await ctx.params; // The secret part of the address.
  const token = raw.replace(/\.ics$/i, "").toLowerCase(); // Drops the ".ics" ending (added so every calendar app accepts the link) and uses lower case.
  const notFound = () => // The reply for a wrong or old link:
    new Response("This calendar link isn't working. Make a new one in the CLG app (Weekly calendar).", { // a plain message,
      status: 404, // "not found",
      headers: { "Cache-Control": "no-store", "Content-Type": "text/plain; charset=utf-8" }, // never saved, plain text.
    }); // End of the reply.
  if (!/^[0-9a-f]{64}$/.test(token)) return notFound(); // Not the right shape: not found (no need to ask the database).

  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { // Connects to the database as "not signed in",
    auth: { persistSession: false, autoRefreshToken: false }, // without saving or refreshing any login (a calendar app isn't a person).
  }); // End of the connection.
  const { data, error } = await supabase.rpc("calendar_feed", { p_token: token }); // Asks for the sessions for this secret.
  if (error) { // The database had a problem:
    console.error("Calendar feed failed:", error.message); // notes it in the server log (never the secret),
    return new Response("The calendar couldn't be loaded just now. Your calendar app will try again.", { // and replies plainly,
      status: 503, // "try again later",
      headers: { "Cache-Control": "no-store", "Content-Type": "text/plain; charset=utf-8" }, // never saved, plain text.
    }); // End of the reply.
  } // End of the problem check.
  // A replaced or turned-off link gets an empty calendar, the same as a tutor
  // with no sessions, so the address gives no hint about whether it ever worked.
  const rows = (data ?? []) as FeedSession[]; // The sessions (none for an old link).

  return new Response(buildCalendar(rows, siteUrl()), { // Sends the calendar file:
    status: 200, // all fine,
    headers: { // with these headers:
      "Content-Type": "text/calendar; charset=utf-8", // it's a calendar file,
      "Content-Disposition": 'inline; filename="clg-sessions.ics"', // its file name if someone opens it in a browser,
      "Cache-Control": "private, no-store", // never kept by shared caches (it's private),
      "X-Robots-Tag": "noindex", // search engines must never list it.
    }, // End of the headers.
  }); // End of the reply.
} // End of GET.
