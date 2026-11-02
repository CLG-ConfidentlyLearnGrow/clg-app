import "server-only";
import { createHash, timingSafeEqual } from "node:crypto";
import { cronSecret } from "@/lib/billing/config";

// True only when the request carries "Authorization: Bearer <CRON_SECRET>",
// which Vercel (and the database's email timer) send. The comparison takes
// the same time whether the guess is close or not, so the secret can't be
// worked out by timing many tries.
export function isCronRequest(request: Request): boolean {
  const secret = cronSecret();
  if (!secret) return false;
  const given = request.headers.get("authorization") ?? "";
  const a = createHash("sha256").update(given).digest();
  const b = createHash("sha256").update(`Bearer ${secret}`).digest();
  return timingSafeEqual(a, b);
}
