// Summary: checks that a request to one of the timed background jobs (daily
// billing, emails, Teams links, progress tidy-up) really came from Vercel or
// the database timer, by checking a secret password in the request.

// Stops this file ever being sent to the browser, because it handles a secret.
import "server-only";
// Tools for scrambling text (hashing) and comparing it safely.
import { createHash, timingSafeEqual } from "node:crypto";
// Reads the timed-job secret (CRON_SECRET) from the app's settings.
import { cronSecret } from "@/lib/billing/config";

// True only when the request carries "Authorization: Bearer <CRON_SECRET>",
// which Vercel (and the database's email timer) send. The comparison takes
// the same time whether the guess is close or not, so the secret can't be
// worked out by timing many tries.
export function isCronRequest(request: Request): boolean {
  const secret = cronSecret(); // Gets the secret set in Vercel's settings.
  if (!secret) return false; // No secret set means nobody may run the jobs.
  const given = request.headers.get("authorization") ?? ""; // The password the caller sent (or nothing).
  const a = createHash("sha256").update(given).digest(); // Scrambles what was sent into a fixed-length code.
  const b = createHash("sha256").update(`Bearer ${secret}`).digest(); // Scrambles what should have been sent the same way.
  return timingSafeEqual(a, b); // Compares the two codes in constant time; true only if they match.
} // End of isCronRequest.
