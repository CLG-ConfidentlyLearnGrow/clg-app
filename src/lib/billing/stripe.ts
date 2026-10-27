import "server-only";
import { createHmac, timingSafeEqual } from "node:crypto";
import { stripeKey } from "./config";

// A small Stripe client using Stripe's web API directly. Card and bank
// details are always typed into Stripe's own pages; this code only ever
// handles Stripe's references (cus_..., pm_..., pi_...).

type Params = Record<string, string | number | boolean | null | undefined | string[] | Record<string, string>>;

// Stripe expects form encoding with brackets for nested values.
function encode(params: Params): string {
  const out = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === null || value === undefined) continue;
    if (Array.isArray(value)) {
      value.forEach((v, i) => out.append(`${key}[${i}]`, v));
    } else if (typeof value === "object") {
      for (const [k, v] of Object.entries(value)) out.append(`${key}[${k}]`, v);
    } else {
      out.append(key, String(value));
    }
  }
  return out.toString();
}

export class StripeError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly body: { error?: { code?: string; decline_code?: string; payment_intent?: { id: string; status: string } } },
  ) {
    super(message);
  }
}

async function call<T>(method: "GET" | "POST", path: string, params: Params = {}, idempotencyKey?: string): Promise<T> {
  const key = stripeKey();
  if (!key) throw new Error("Stripe isn't connected yet (STRIPE_SECRET_KEY is missing).");
  const body = encode(params);
  const url = `https://api.stripe.com/v1/${path}${method === "GET" && body ? `?${body}` : ""}`;
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/x-www-form-urlencoded",
      ...(idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}),
    },
    body: method === "POST" ? body : undefined,
    cache: "no-store",
  });
  const json = await res.json();
  if (!res.ok) {
    throw new StripeError(json?.error?.message ?? `Stripe error ${res.status}`, res.status, json);
  }
  return json as T;
}

export type StripeCustomer = { id: string };
export type CheckoutSession = { id: string; url: string; mode: string; setup_intent?: string | null; metadata?: Record<string, string> };
export type SetupIntent = {
  id: string;
  customer: string;
  mandate: string | null;
  payment_method: { id: string; type: string } | null;
  metadata?: Record<string, string>;
};
export type PaymentIntent = {
  id: string;
  status: string;
  amount: number;
  payment_method_types: string[];
  last_payment_error?: { message?: string } | null;
  metadata?: Record<string, string>;
};

// The family's Stripe customer: the bill payer's name and email only.
export function createCustomer(name: string, email: string, familyId: string) {
  return call<StripeCustomer>("POST", "customers", { name, email, metadata: { family_id: familyId } }, `customer-${familyId}`);
}

// Stripe's page where a family saves a card or signs a bank debit
// agreement once. Weekly families can only save a card.
export function createSetupPage(opts: {
  customer: string;
  familyId: string;
  allowBankDebit: boolean;
  returnUrl: string;
}) {
  return call<CheckoutSession>("POST", "checkout/sessions", {
    mode: "setup",
    currency: "aud",
    customer: opts.customer,
    payment_method_types: opts.allowBankDebit ? ["card", "au_becs_debit"] : ["card"],
    success_url: `${opts.returnUrl}?setup=done`,
    cancel_url: `${opts.returnUrl}?setup=cancelled`,
    metadata: { family_id: opts.familyId },
    "setup_intent_data[metadata][family_id]": opts.familyId,
  });
}

// Stripe's page to pay one invoice now (for families without automatic
// payment, or after a failed payment).
export function createPayNowPage(opts: {
  customer: string | null;
  invoiceId: string;
  invoiceNumber: string;
  familyId: string;
  amountCents: number;
  returnUrl: string;
}) {
  return call<CheckoutSession>("POST", "checkout/sessions", {
    mode: "payment",
    customer: opts.customer ?? undefined,
    payment_method_types: ["card", "au_becs_debit"],
    "line_items[0][quantity]": 1,
    "line_items[0][price_data][currency]": "aud",
    "line_items[0][price_data][unit_amount]": opts.amountCents,
    "line_items[0][price_data][product_data][name]": `CLG invoice ${opts.invoiceNumber}`,
    "payment_intent_data[metadata][invoice_id]": opts.invoiceId,
    "payment_intent_data[metadata][family_id]": opts.familyId,
    success_url: `${opts.returnUrl}?paid=${opts.invoiceNumber}`,
    cancel_url: opts.returnUrl,
  });
}

export function getSetupIntent(id: string) {
  return call<SetupIntent>("GET", `setup_intents/${id}`, { "expand[0]": "payment_method" });
}

// Charges a saved card or bank debit for an invoice. The invoice's own
// key means a retry can never charge twice.
export function chargeSaved(opts: {
  customer: string;
  paymentMethod: string;
  mandate: string | null;
  bankDebit: boolean;
  amountCents: number;
  invoiceId: string;
  familyId: string;
  invoiceNumber: string;
  idempotencyKey: string;
}) {
  return call<PaymentIntent>(
    "POST",
    "payment_intents",
    {
      amount: opts.amountCents,
      currency: "aud",
      customer: opts.customer,
      payment_method: opts.paymentMethod,
      payment_method_types: [opts.bankDebit ? "au_becs_debit" : "card"],
      mandate: opts.bankDebit ? opts.mandate : undefined,
      off_session: opts.bankDebit ? undefined : true,
      confirm: true,
      description: `CLG invoice ${opts.invoiceNumber}`,
      metadata: { invoice_id: opts.invoiceId, family_id: opts.familyId },
    },
    `charge-${opts.idempotencyKey}`,
  );
}

// Checks that a message really came from Stripe (Stripe-Signature header)
// and is less than 5 minutes old.
export function verifyStripeSignature(rawBody: string, header: string | null, secret: string, now = Date.now()): boolean {
  if (!header) return false;
  const parts = Object.fromEntries(
    header.split(",").map((p) => {
      const i = p.indexOf("=");
      return [p.slice(0, i), p.slice(i + 1)];
    }),
  );
  const t = Number(parts.t);
  if (!t || Math.abs(now / 1000 - t) > 300) return false;
  const expected = createHmac("sha256", secret).update(`${t}.${rawBody}`).digest("hex");
  const signatures = header
    .split(",")
    .filter((p) => p.startsWith("v1="))
    .map((p) => p.slice(3));
  return signatures.some((sig) => {
    const a = Buffer.from(sig, "hex");
    const b = Buffer.from(expected, "hex");
    return a.length === b.length && timingSafeEqual(a, b);
  });
}
