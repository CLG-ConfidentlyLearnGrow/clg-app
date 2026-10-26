import "server-only";
import { createClient } from "@supabase/supabase-js";
import { supabaseUrl } from "@/lib/env";

// Server-only client with the secret key. It bypasses the access rules, so
// use it only for the few jobs that need it (login lock, sending invites)
// and never pass its results to the browser unchecked.
export function createAdminClient() {
  const key = process.env.SUPABASE_SECRET_KEY;
  if (!key) {
    throw new Error("Missing environment variable SUPABASE_SECRET_KEY. See .env.example.");
  }
  return createClient(supabaseUrl(), key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
