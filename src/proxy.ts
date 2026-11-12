// Summary: runs before every page request, to keep the person's sign-in fresh.
//
import type { NextRequest } from "next/server"; // The type of an incoming request.
import { updateSession } from "@/lib/supabase/proxy"; // Refreshes the sign-in and sends signed-out people to the login page.

// Runs for each request matched below.
export async function proxy(request: NextRequest) {
  return updateSession(request); // Refreshes the sign-in and passes the request on.
} // End of proxy.

// Which requests this runs for.
export const config = {
  matcher: [ // The address patterns:
    // Everything except static files and images.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)", // every address except built files, images and the icon.
  ], // (end of the list)
}; // End of the settings.
