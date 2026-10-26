import { NextResponse, type NextRequest } from "next/server";
import { isEmailLinkType } from "@/lib/email-links";
import { safeNextPath } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// Landing point for links in Supabase emails: sign-up confirmation,
// invitations and password resets.
export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const params = url.searchParams;
  let next = safeNextPath(params.get("next"));
  const code = params.get("code");
  const tokenHash = params.get("token_hash");
  const type = params.get("type");

  // Supabase sends people back with an error when a link has expired or was
  // already used (email security scanners sometimes "click" links first).
  if (params.get("error") || params.get("error_code")) {
    return NextResponse.redirect(new URL("/login?link=expired", url.origin));
  }

  // Links that use our own email templates: ask the person to press a button
  // first, so a scanner opening the link can't use it up.
  if (!code && tokenHash && isEmailLinkType(type)) {
    const next_ = new URL("/auth/continue", url.origin);
    next_.searchParams.set("token_hash", tokenHash);
    next_.searchParams.set("type", type);
    next_.searchParams.set("next", next);
    return NextResponse.redirect(next_);
  }

  if (!code) {
    return NextResponse.redirect(new URL("/login?link=expired", url.origin));
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    // Usually the link was opened on a different device or browser from the
    // one used to ask for it, or it was already used.
    return NextResponse.redirect(new URL("/login?link=other-device", url.origin));
  }

  // A password reset or invitation always goes on to choosing a password,
  // even if the link arrived without "next" (for example via the Site URL).
  const { data } = await supabase.auth.getClaims();
  const amr = (data?.claims?.amr ?? []) as unknown[];
  const methods = amr.map((m) => (typeof m === "string" ? m : (m as { method?: string })?.method));
  if (methods.includes("recovery") || methods.includes("invite")) next = "/set-password";

  return NextResponse.redirect(new URL(next, url.origin));
}
