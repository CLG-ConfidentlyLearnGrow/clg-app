// Summary: spam helpers for the public "Apply to tutor" form. A signed "form
// opened at" stamp proves the form came from CLG's own page and shows how
// long the person took to fill it in, and the sender's internet address is
// scrambled before it's used for the daily limit (the real address is never
// kept). See docs/features/tutor-applications.md.
//
// Stops this file ever being sent to the browser, because it uses the secret key.
import "server-only";
import { createHmac, timingSafeEqual } from "node:crypto"; // Makes and compares signatures without leaking timing clues.
import { MAX_FILL_HOURS, MIN_FILL_SECONDS } from "@/lib/tutor-applications"; // How quick and how old a form may be.

// The secret used to sign stamps and scramble addresses: the server's own
// database key, which is already set wherever the form can be saved.
function secret(): string {
  const key = process.env.SUPABASE_SECRET_KEY; // Reads the secret key from the app's settings.
  if (!key) throw new Error("Missing environment variable SUPABASE_SECRET_KEY. See .env.example."); // Stops with a plain message if it isn't set.
  return key; // Hands it back.
} // End of secret.

// Signs a piece of text with the secret, for a given purpose (so a stamp
// signature can never be reused as an address scramble or the other way round).
function sign(purpose: string, text: string): string {
  return createHmac("sha256", secret()).update(`${purpose}:${text}`).digest("hex"); // A 64-character signature.
} // End of sign.

// Makes the "form opened at" stamp put in the form as a hidden field.
export function makeFormStamp(now = Date.now()): string {
  const at = String(now); // The time the form was opened, in milliseconds.
  return `${at}.${sign("apply-form", at)}`; // The time and its signature, joined by a dot.
} // End of makeFormStamp.

// Checks a stamp sent back with the form. Gives back a plain problem, or
// null if it's fine: signed by CLG, opened long enough ago, and not too old.
export function checkFormStamp(stamp: string | null | undefined, now = Date.now()): string | null {
  const [at, signature] = String(stamp ?? "").split("."); // Splits it into the time and the signature.
  const expected = at ? sign("apply-form", at) : ""; // The signature it should have.
  const sameLength = Boolean(signature) && signature.length === expected.length; // Signatures must be the same length to compare safely.
  if (!sameLength || !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) { // Missing or wrong signature:
    return "This form has expired. Please refresh the page and try again."; // asks them to reload (a bot or a copied form).
  } // End of the signature check.
  const seconds = (now - Number(at)) / 1000; // How long the form was open.
  if (!Number.isFinite(seconds) || seconds < MIN_FILL_SECONDS) { // Filled in too fast to be a person:
    return "That was very quick. Please check your answers and press Send again."; // a gentle message (a person can simply press again).
  } // End of the speed check.
  if (seconds > MAX_FILL_HOURS * 3600) { // Opened more than a day ago:
    return "This form has expired. Please refresh the page and try again. Copy your longer answers first so you do not lose them."; // asks them to reload.
  } // End of the age check.
  return null; // All good.
} // End of checkFormStamp.

// Scrambles an internet address for the daily limit. The same address
// always gives the same result, but it can't be turned back into the address.
export function scrambleAddress(address: string | null): string | null {
  const clean = (address ?? "").trim(); // The address without spaces.
  return clean ? sign("apply-ip", clean) : null; // Its scrambled form, or nothing if unknown.
} // End of scrambleAddress.
