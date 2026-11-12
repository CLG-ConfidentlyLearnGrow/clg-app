// Summary: where links in sign-in emails land; signs the person in and sends them on.
//
import { NextResponse, type NextRequest } from "next/server"; // The reply tools for redirects.
import { isEmailLinkType } from "@/lib/email-links"; // Checks the link's kind is one we know.
import { safeNextPath } from "@/lib/forms"; // Makes sure the "next page" is inside the app.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Landing point for links in Supabase emails: sign-up confirmation,
// invitations and password resets.
export async function GET(request: NextRequest) {
  const url = new URL(request.url); // The full address.
  const params = url.searchParams; // Its settings after the "?".
  let next = safeNextPath(params.get("next")); // The page to go to next, kept inside the app.
  const code = params.get("code"); // A sign-in code (from Supabase's own links).
  const tokenHash = params.get("token_hash"); // A link code (from our own emails).
  const type = params.get("type"); // The link's kind.

  // Supabase sends people back with an error when a link has expired or was
  // already used (email security scanners sometimes "click" links first).
  if (params.get("error") || params.get("error_code")) { // If there's an error:
    return NextResponse.redirect(new URL("/login?link=expired", url.origin)); // sends them to sign in with an "expired" note.
  } // End of the check.

  // Links that use our own email templates: ask the person to press a button
  // first, so a scanner opening the link can't use it up.
  if (!code && tokenHash && isEmailLinkType(type)) { // Our own link with a code and known kind:
    const next_ = new URL("/auth/continue", url.origin); // the "one more step" page,
    next_.searchParams.set("token_hash", tokenHash); // with the link code,
    next_.searchParams.set("type", type); // the kind,
    next_.searchParams.set("next", next); // and the next page.
    return NextResponse.redirect(next_); // Sends them there.
  } // End of that case.

  if (!code) { // No sign-in code:
    return NextResponse.redirect(new URL("/login?link=expired", url.origin)); // sends them to sign in with an "expired" note.
  } // End of the check.

  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.auth.exchangeCodeForSession(code); // Swaps the code for a signed-in session.
  if (error) { // It failed:
    // Usually the link was opened on a different device or browser from the
    // one used to ask for it, or it was already used.
    return NextResponse.redirect(new URL("/login?link=other-device", url.origin)); // sends them to sign in with an "other device" note.
  } // End of the failure case.

  // A password reset or invitation always goes on to choosing a password,
  // even if the link arrived without "next" (for example via the Site URL).
  const { data } = await supabase.auth.getClaims(); // Reads who is signed in.
  const amr = (data?.claims?.amr ?? []) as unknown[]; // How they signed in.
  const methods = amr.map((m) => (typeof m === "string" ? m : (m as { method?: string })?.method)); // Each way as a word.
  if (methods.includes("recovery") || methods.includes("invite")) next = "/set-password"; // A reset or invitation: goes to choose a password.

  return NextResponse.redirect(new URL(next, url.origin)); // Sends them on to the next page.
} // End of GET.
