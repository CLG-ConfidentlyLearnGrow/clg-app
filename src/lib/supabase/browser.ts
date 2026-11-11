// Summary: a database connection that runs in the person's web browser,
// acting as them, used only to upload large files straight to storage.

// Marks this file as code that runs in the browser.
"use client";

// The Supabase library's browser connection maker.
import { createBrowserClient } from "@supabase/ssr";
// The database's web address and public key.
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

// Supabase client in the browser, acting as the signed-in person. Used only
// to send large files (materials) straight to the file store, so they don't
// pass through the app's server. The database's access rules still apply.
export function createBrowserSupabase() {
  return createBrowserClient(supabaseUrl(), supabasePublishableKey()); // Makes the connection with the public key.
} // End of createBrowserSupabase.
