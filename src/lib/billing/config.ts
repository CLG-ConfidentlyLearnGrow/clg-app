import "server-only";

// Billing settings that come from Vercel's secret settings. Each one is
// optional so the rest of the app works before billing is connected; the
// billing pages say plainly what is missing.

export function stripeKey(): string | null {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) return null;
  // Safety: a live key only works once live payments are switched on, so
  // testing can never charge a real card.
  const live = key.startsWith("sk_live_") || key.startsWith("rk_live_");
  if (live && process.env.BILLING_LIVE_PAYMENTS !== "on") {
    throw new Error(
      "A live Stripe key is set but live payments are not switched on. Set BILLING_LIVE_PAYMENTS=on when CLG is ready to take real payments.",
    );
  }
  return key;
}

export function stripeIsTestMode(): boolean {
  const key = process.env.STRIPE_SECRET_KEY ?? "";
  return !key.includes("_live_");
}

export const stripeWebhookSecret = () => process.env.STRIPE_WEBHOOK_SECRET ?? null;

export type XeroConfig = {
  clientId: string;
  clientSecret: string;
  webhookKey: string | null;
  scopes: string;
  salesAccount: string;
  clearingAccount: string;
};

export function xeroConfig(): XeroConfig | null {
  const clientId = process.env.XERO_CLIENT_ID;
  const clientSecret = process.env.XERO_CLIENT_SECRET;
  if (!clientId || !clientSecret) return null;
  return {
    clientId,
    clientSecret,
    webhookKey: process.env.XERO_WEBHOOK_KEY ?? null,
    // Xero apps made after 2 March 2026 use the newer, narrower scopes.
    scopes:
      process.env.XERO_SCOPES ??
      "openid profile email offline_access accounting.invoices accounting.payments accounting.contacts accounting.settings.read",
    // Account codes in CLG's Xero chart of accounts.
    salesAccount: process.env.XERO_SALES_ACCOUNT ?? "200",
    clearingAccount: process.env.XERO_STRIPE_CLEARING_ACCOUNT ?? "",
  };
}

// Key for storing the Xero sign-in encrypted (32 random bytes, base64).
export function encryptionKey(): Buffer | null {
  const raw = process.env.BILLING_ENCRYPTION_KEY;
  if (!raw) return null;
  const key = Buffer.from(raw, "base64");
  if (key.length !== 32) throw new Error("BILLING_ENCRYPTION_KEY must be 32 bytes, base64 encoded.");
  return key;
}

// Vercel sends this with its scheduled calls to the daily billing run.
export const cronSecret = () => process.env.CRON_SECRET ?? null;
