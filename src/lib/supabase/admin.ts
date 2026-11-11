// Summary: makes a database connection with the secret key. It ignores the
// database's access rules, so it's only for the few server jobs that need it.

// Stops this file ever being sent to the browser, because it uses the secret key.
import "server-only";
// The Supabase library's connection maker.
import { createClient } from "@supabase/supabase-js";
// The database's web address.
import { supabaseUrl } from "@/lib/env";

// Server-only client with the secret key. It bypasses the access rules, so
// use it only for the few jobs that need it (login lock, sending invites)
// and never pass its results to the browser unchecked.
export function createAdminClient() {
  const key = process.env.SUPABASE_SECRET_KEY; // Reads the secret key from the app's settings.
  if (!key) { // The key isn't set:
    throw new Error("Missing environment variable SUPABASE_SECRET_KEY. See .env.example."); // Stops with a plain message.
  } // End of the missing-key check.
  return createClient(supabaseUrl(), key, { // Makes the connection with the secret key,
    auth: { persistSession: false, autoRefreshToken: false }, // without saving or refreshing any login (it isn't a person).
  }); // End of the connection settings.
} // End of createAdminClient.
