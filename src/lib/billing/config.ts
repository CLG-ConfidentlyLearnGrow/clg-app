// Summary: billing settings that come from Vercel's secret settings (Stripe,
// Xero, the encryption key and the timed-job secret). Each one is optional so
// the rest of the app works before billing is connected; the billing pages
// say plainly what is missing.

// Stops this file ever being sent to the browser, because it reads secrets.
import "server-only";

// Billing settings that come from Vercel's secret settings. Each one is
// optional so the rest of the app works before billing is connected; the
// billing pages say plainly what is missing.

// The secret key for talking to Stripe (payments), or null if not set.
export function stripeKey(): string | null {
  const key = process.env.STRIPE_SECRET_KEY; // Reads the Stripe key setting.
  if (!key) return null; // Not set, so billing with Stripe is off.
  // Safety: a live key only works once live payments are switched on, so
  // testing can never charge a real card.
  const live = key.startsWith("sk_live_") || key.startsWith("rk_live_"); // True if this is a real-money key.
  if (live && process.env.BILLING_LIVE_PAYMENTS !== "on") { // Real key but live payments not switched on:
    throw new Error( // Stops with a plain explanation.
      "A live Stripe key is set but live payments are not switched on. Set BILLING_LIVE_PAYMENTS=on when CLG is ready to take real payments.",
    ); // End of the error.
  } // End of the safety check.
  return key; // Hands back the key.
} // End of stripeKey.

// True when Stripe is in test mode (no real money moves).
export function stripeIsTestMode(): boolean {
  const key = process.env.STRIPE_SECRET_KEY ?? ""; // Reads the Stripe key (blank if not set).
  return !key.includes("_live_"); // Anything that isn't a live key counts as test mode.
} // End of stripeIsTestMode.

// The secret Stripe uses to sign its messages to the app, or null if not set.
export const stripeWebhookSecret = () => process.env.STRIPE_WEBHOOK_SECRET ?? null;

// The settings needed to connect to Xero (accounting).
export type XeroConfig = {
  clientId: string; // CLG's Xero app id.
  clientSecret: string; // CLG's Xero app password.
  webhookKey: string | null; // The key Xero uses to sign its messages, if set.
  scopes: string; // What the app is allowed to do in Xero.
  salesAccount: string; // The account code invoices are recorded against.
  clearingAccount: string; // The account code Stripe payments land in.
}; // End of the Xero settings shape.

// Reads the Xero settings, or null if Xero isn't set up yet.
export function xeroConfig(): XeroConfig | null {
  const clientId = process.env.XERO_CLIENT_ID; // Reads the Xero app id.
  const clientSecret = process.env.XERO_CLIENT_SECRET; // Reads the Xero app password.
  if (!clientId || !clientSecret) return null; // Either missing means Xero is off.
  return { // Hands back the settings:
    clientId, // the app id,
    clientSecret, // the app password,
    webhookKey: process.env.XERO_WEBHOOK_KEY ?? null, // the message-signing key (if set),
    // Xero apps made after 2 March 2026 use the newer, narrower scopes.
    scopes: // the permissions asked for, which are either
      process.env.XERO_SCOPES ?? // the ones set in Vercel, or else this default list:
      "openid profile email offline_access accounting.invoices accounting.payments accounting.contacts accounting.settings.read payroll.employees.read payroll.settings.read payroll.timesheets",
    // Account codes in CLG's Xero chart of accounts.
    salesAccount: process.env.XERO_SALES_ACCOUNT ?? "200", // the sales account (200 if not set),
    clearingAccount: process.env.XERO_STRIPE_CLEARING_ACCOUNT ?? "", // and the Stripe clearing account (blank if not set).
  }; // End of the settings.
} // End of xeroConfig.

// Key for storing the Xero sign-in encrypted (32 random bytes, base64).
export function encryptionKey(): Buffer | null {
  const raw = process.env.BILLING_ENCRYPTION_KEY; // Reads the key setting.
  if (!raw) return null; // Not set.
  const key = Buffer.from(raw, "base64"); // Turns the text back into raw bytes.
  if (key.length !== 32) throw new Error("BILLING_ENCRYPTION_KEY must be 32 bytes, base64 encoded."); // Wrong length means it was copied wrongly.
  return key; // Hands back the key.
} // End of encryptionKey.

// Vercel sends this with its scheduled calls to the daily billing run.
export const cronSecret = () => process.env.CRON_SECRET ?? null;
