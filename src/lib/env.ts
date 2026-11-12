// Summary: reads the app's settings (environment variables set in Vercel or
// on a computer), with a clear message if a needed one is missing.

// Reads required settings once, with a clear error if one is missing.
function required(name: string, value: string | undefined): string {
  if (!value) { // The setting is blank or not set at all.
    throw new Error(`Missing environment variable ${name}. See .env.example.`); // Stops with a plain message naming it.
  } // End of the missing check.
  return value; // The setting is present, so it is handed back.
} // End of required.

// The web address of CLG's Supabase database.
export const supabaseUrl = () =>
  required("NEXT_PUBLIC_SUPABASE_URL", process.env.NEXT_PUBLIC_SUPABASE_URL); // Must be set, or the app stops.

// The public key that lets the app talk to Supabase as a signed-in person.
export const supabasePublishableKey = () =>
  required( // Must be set, or the app stops.
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", // The setting's name, shown if it's missing.
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, // The setting's value.
  ); // End of the key check.

// The app's own web address, used in links inside emails (password reset,
// sign-up, invitations). On the live site this is always the address Vercel
// lists as the production domain, so a mistyped NEXT_PUBLIC_SITE_URL can't
// send people to the wrong website. Elsewhere (your computer, previews) it
// comes from NEXT_PUBLIC_SITE_URL.
export const siteUrl = () => {
  const live = process.env.VERCEL_PROJECT_PRODUCTION_URL; // The live address Vercel knows about.
  if (process.env.VERCEL_ENV === "production" && live) { // On the live site, with that address known:
    return `https://${live.replace(/^https?:\/\//, "").replace(/\/$/, "")}`; // Uses it, tidied to "https://address" with no end slash.
  } // End of the live-site case.
  return required("NEXT_PUBLIC_SITE_URL", process.env.NEXT_PUBLIC_SITE_URL).replace(/\/$/, ""); // Otherwise uses the setting, minus any end slash.
}; // End of siteUrl.
