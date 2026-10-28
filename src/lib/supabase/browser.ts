"use client";

import { createBrowserClient } from "@supabase/ssr";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

// Supabase client in the browser, acting as the signed-in person. Used only
// to send large files (materials) straight to the file store, so they don't
// pass through the app's server. The database's access rules still apply.
export function createBrowserSupabase() {
  return createBrowserClient(supabaseUrl(), supabasePublishableKey());
}
