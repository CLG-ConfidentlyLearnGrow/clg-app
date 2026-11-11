// Summary: a database connection on the server that acts as the signed-in
// person, so every query is limited by the database's access rules.

// Stops this file ever being sent to the browser.
import "server-only";
// The Supabase library's server connection maker.
import { createServerClient } from "@supabase/ssr";
// Lets the server read and set the browser's login cookies.
import { cookies } from "next/headers";
// The database's web address and public key.
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

// Supabase client acting as the signed-in person. Every query it makes is
// limited by the database's access rules.
export async function createClient() {
  const cookieStore = await cookies(); // Gets this request's cookies (where the login is kept).

  return createServerClient(supabaseUrl(), supabasePublishableKey(), { // Makes the connection with the public key,
    cookies: { // telling it how to read and write the login cookies:
      getAll() { // To read them,
        return cookieStore.getAll(); // hands over every cookie from the request.
      }, // End of getAll.
      setAll(cookiesToSet) { // To save refreshed login cookies,
        try { // (this can fail on some pages)
          cookiesToSet.forEach(({ name, value, options }) => // goes through each cookie
            cookieStore.set(name, value, options), // and saves it on the reply.
          ); // End of the loop.
        } catch { // Saving wasn't allowed here.
          // Called from a Server Component, where cookies are read-only.
          // The proxy refreshes the session instead.
        } // End of the error handling.
      }, // End of setAll.
    }, // End of the cookie settings.
  }); // End of the connection settings.
} // End of createClient.
