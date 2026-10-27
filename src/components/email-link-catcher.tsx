"use client";

import { useEffect } from "react";
import { signInFromEmailLink } from "@/app/actions/auth";

// Password reset links can arrive with the sign-in after the "#" in the
// address. Browsers never send that part to the server, so this picks it up,
// removes it from the address bar and finishes signing in.
export function EmailLinkCatcher() {
  useEffect(() => {
    const hash = window.location.hash.slice(1);
    if (!hash.includes("access_token=") && !hash.includes("error_code=")) return;
    const params = new URLSearchParams(hash);
    window.history.replaceState(null, "", window.location.pathname + window.location.search);

    if (params.get("error_code") || params.get("error")) {
      window.location.replace("/login?link=expired");
      return;
    }
    void signInFromEmailLink(
      params.get("access_token") ?? "",
      params.get("refresh_token") ?? "",
      params.get("type") ?? "",
    );
  }, []);
  return null;
}
