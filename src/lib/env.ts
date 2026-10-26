// Reads required settings once, with a clear error if one is missing.
function required(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(`Missing environment variable ${name}. See .env.example.`);
  }
  return value;
}

export const supabaseUrl = () =>
  required("NEXT_PUBLIC_SUPABASE_URL", process.env.NEXT_PUBLIC_SUPABASE_URL);

export const supabasePublishableKey = () =>
  required(
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );

// The app's own web address, used in links inside emails (password reset,
// sign-up, invitations). On the live site this is always the address Vercel
// lists as the production domain, so a mistyped NEXT_PUBLIC_SITE_URL can't
// send people to the wrong website. Elsewhere (your computer, previews) it
// comes from NEXT_PUBLIC_SITE_URL.
export const siteUrl = () => {
  const live = process.env.VERCEL_PROJECT_PRODUCTION_URL;
  if (process.env.VERCEL_ENV === "production" && live) {
    return `https://${live.replace(/^https?:\/\//, "").replace(/\/$/, "")}`;
  }
  return required("NEXT_PUBLIC_SITE_URL", process.env.NEXT_PUBLIC_SITE_URL).replace(/\/$/, "");
};
