// Summary: a small Stripe client using Stripe's web API directly. Card and
// bank details are always typed into Stripe's own pages; this code only ever
// handles Stripe's references (cus_..., pm_..., pi_...).

// Stops this file ever being sent to the browser, because it uses the Stripe key.
import "server-only";
// Tools for checking a signed message and comparing codes safely.
import { createHmac, timingSafeEqual } from "node:crypto";
// Reads the Stripe secret key.
import { stripeKey } from "./config";

// The kinds of values that can be sent to Stripe.
type Params = Record<string, string | number | boolean | null | undefined | string[] | Record<string, string>>;

// Stripe expects form encoding with brackets for nested values.
function encode(params: Params): string {
  const out = new URLSearchParams(); // The form data being built.
  for (const [key, value] of Object.entries(params)) { // Goes through each value to send.
    if (value === null || value === undefined) continue; // Skips empty values.
    if (Array.isArray(value)) { // A list:
      value.forEach((v, i) => out.append(`${key}[${i}]`, v)); // sends each item as key[0], key[1] and so on.
    } else if (typeof value === "object") { // A group of named values:
      for (const [k, v] of Object.entries(value)) out.append(`${key}[${k}]`, v); // sends each as key[name].
    } else { // A single value:
      out.append(key, String(value)); // sends it as text.
    } // End of the value kinds.
  } // End of the loop.
  return out.toString(); // Hands back the finished form text.
} // End of encode.

// A Stripe problem, keeping Stripe's status number and full reply for checks.
export class StripeError extends Error {
  constructor( // Makes a new Stripe error from:
    message: string, // the plain message,
    public readonly status: number, // Stripe's status number,
    public readonly body: { error?: { code?: string; decline_code?: string; payment_intent?: { id: string; status: string } } }, // and Stripe's reply.
  ) { // Then:
    super(message); // sets the message like any error.
  } // End of the constructor.
} // End of StripeError.

// Sends one request to Stripe and returns its reply, or throws a StripeError.
async function call<T>(method: "GET" | "POST", path: string, params: Params = {}, idempotencyKey?: string): Promise<T> {
  const key = stripeKey(); // Reads the Stripe key.
  if (!key) throw new Error("Stripe isn't connected yet (STRIPE_SECRET_KEY is missing)."); // No key: plain message.
  const body = encode(params); // Turns the values into Stripe's form format.
  const url = `https://api.stripe.com/v1/${path}${method === "GET" && body ? `?${body}` : ""}`; // The address (GET requests carry values after "?").
  const res = await fetch(url, { // Sends the request:
    method, // GET to read, POST to make or change,
    headers: { // with these headers:
      Authorization: `Bearer ${key}`, // the Stripe key,
      "Content-Type": "application/x-www-form-urlencoded", // saying it's form data,
      ...(idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}), // and, if given, a key that stops a retry doing it twice.
    }, // End of the headers.
    body: method === "POST" ? body : undefined, // POST requests carry the values in the body.
    cache: "no-store", // Never reuses an old saved reply.
  }); // End of the request.
  const json = await res.json(); // Reads Stripe's reply.
  if (!res.ok) { // Stripe refused:
    throw new StripeError(json?.error?.message ?? `Stripe error ${res.status}`, res.status, json); // stops with Stripe's message.
  } // End of the refusal check.
  return json as T; // Hands back the reply.
} // End of call.

// A Stripe customer (just its id is needed).
export type StripeCustomer = { id: string };
// A Stripe-hosted page (checkout session): its id, web address, kind, and any saved details.
export type CheckoutSession = { id: string; url: string; mode: string; setup_intent?: string | null; metadata?: Record<string, string> };
// A saved payment method setup, as Stripe describes it.
export type SetupIntent = {
  id: string; // Stripe's id for it.
  customer: string; // Whose it is.
  mandate: string | null; // The bank debit agreement, if any.
  payment_method: { id: string; type: string } | null; // The saved card or bank account.
  metadata?: Record<string, string>; // CLG's own notes (family id and so on).
}; // End of the setup shape.
// A payment, as Stripe describes it.
export type PaymentIntent = {
  id: string; // Stripe's id for the payment.
  status: string; // Where it's up to (succeeded, processing, failed...).
  amount: number; // How much, in cents.
  payment_method_types: string[]; // Card or bank debit.
  last_payment_error?: { message?: string } | null; // Why it last failed, if it did.
  metadata?: Record<string, string>; // CLG's own notes (invoice id and so on).
}; // End of the payment shape.

// The family's Stripe customer: the bill payer's name and email only. A
// second payer sharing the invoices gets their own customer.
export function createCustomer(name: string, email: string, familyId: string, payerId?: string) {
  return call<StripeCustomer>( // Asks Stripe to make a customer:
    "POST", // as a new item,
    "customers", // in the customers list,
    { name, email, metadata: payerId ? { family_id: familyId, payer_id: payerId } : { family_id: familyId } }, // with name, email, and the family (and payer) ids,
    payerId ? `customer-${familyId}-${payerId}` : `customer-${familyId}`, // and a key so a retry can't make a duplicate.
  ); // End of the request.
} // End of createCustomer.

// Stripe's page where a family saves a card or signs a bank debit
// agreement once. Weekly families can only save a card.
export function createSetupPage(opts: {
  customer: string; // The family's Stripe customer.
  familyId: string; // The family's id in CLG's database.
  payerId?: string; // The payer's id, if the bill is split.
  allowBankDebit: boolean; // Whether bank debit is offered.
  returnUrl: string; // The app page to come back to.
}) {
  return call<CheckoutSession>("POST", "checkout/sessions", { // Asks Stripe for a setup page:
    mode: "setup", // to save a method, not to pay,
    currency: "aud", // in Australian dollars,
    customer: opts.customer, // for this customer,
    payment_method_types: opts.allowBankDebit ? ["card", "au_becs_debit"] : ["card"], // offering card (and bank debit if allowed),
    success_url: `${opts.returnUrl}?setup=done`, // coming back here when done,
    cancel_url: `${opts.returnUrl}?setup=cancelled`, // or here if cancelled,
    metadata: { family_id: opts.familyId }, // noting the family,
    "setup_intent_data[metadata][family_id]": opts.familyId, // and noting the family on the saved method,
    "setup_intent_data[metadata][payer_id]": opts.payerId, // plus the payer, if any.
  }); // End of the request.
} // End of createSetupPage.

// Stripe's page to pay one invoice now (for families without automatic
// payment, or after a failed payment).
export function createPayNowPage(opts: {
  customer: string | null; // The family's Stripe customer, if they have one.
  invoiceId: string; // The invoice's id in CLG's database.
  invoiceNumber: string; // The invoice number shown to the family.
  familyId: string; // The family's id.
  payerId?: string; // The payer's id, if the bill is split.
  amountCents: number; // How much to pay, in cents.
  returnUrl: string; // The app page to come back to.
}) {
  return call<CheckoutSession>("POST", "checkout/sessions", { // Asks Stripe for a payment page:
    mode: "payment", // to pay now,
    customer: opts.customer ?? undefined, // for this customer, if known,
    payment_method_types: ["card", "au_becs_debit"], // by card or bank debit,
    "line_items[0][quantity]": 1, // one item,
    "line_items[0][price_data][currency]": "aud", // in Australian dollars,
    "line_items[0][price_data][unit_amount]": opts.amountCents, // for this amount,
    "line_items[0][price_data][product_data][name]": `CLG invoice ${opts.invoiceNumber}`, // named after the invoice,
    "payment_intent_data[metadata][invoice_id]": opts.invoiceId, // noting the invoice,
    "payment_intent_data[metadata][family_id]": opts.familyId, // the family,
    "payment_intent_data[metadata][payer_id]": opts.payerId, // and the payer, if any,
    success_url: `${opts.returnUrl}?paid=${opts.invoiceNumber}`, // coming back here when paid,
    cancel_url: opts.returnUrl, // or here if cancelled.
  }); // End of the request.
} // End of createPayNowPage.

// Reads a saved payment method setup from Stripe, including the method's details.
export function getSetupIntent(id: string) {
  return call<SetupIntent>("GET", `setup_intents/${id}`, { "expand[0]": "payment_method" }); // "expand" asks for the full method, not just its id.
} // End of getSetupIntent.

// Charges a saved card or bank debit for an invoice. The invoice's own
// key means a retry can never charge twice.
export function chargeSaved(opts: {
  customer: string; // The Stripe customer.
  paymentMethod: string; // The saved card or bank account.
  mandate: string | null; // The bank debit agreement, if any.
  bankDebit: boolean; // True for bank debit, false for card.
  amountCents: number; // How much, in cents.
  invoiceId: string; // The invoice's id.
  familyId: string; // The family's id.
  payerId?: string; // The payer's id, if split.
  invoiceNumber: string; // The invoice number shown to the family.
  idempotencyKey: string; // The invoice's own key, so it's never charged twice.
}) {
  return call<PaymentIntent>( // Asks Stripe to take a payment:
    "POST", // as a new item,
    "payment_intents", // in the payments list,
    { // with these details:
      amount: opts.amountCents, // the amount,
      currency: "aud", // in Australian dollars,
      customer: opts.customer, // from this customer,
      payment_method: opts.paymentMethod, // using this saved method,
      payment_method_types: [opts.bankDebit ? "au_becs_debit" : "card"], // which is bank debit or card,
      mandate: opts.bankDebit ? opts.mandate : undefined, // with the debit agreement (bank debit only),
      off_session: opts.bankDebit ? undefined : true, // marked "family not present" (card only),
      confirm: true, // taking the payment straight away,
      description: `CLG invoice ${opts.invoiceNumber}`, // described by invoice number,
      metadata: opts.payerId // and noting
        ? { invoice_id: opts.invoiceId, family_id: opts.familyId, payer_id: opts.payerId } // the invoice, family and payer,
        : { invoice_id: opts.invoiceId, family_id: opts.familyId }, // or just the invoice and family.
    }, // End of the details.
    opts.payerId ? `charge-${opts.idempotencyKey}-${opts.payerId}` : `charge-${opts.idempotencyKey}`, // The never-twice key.
  ); // End of the request.
} // End of chargeSaved.

// Checks that a message really came from Stripe (Stripe-Signature header)
// and is less than 5 minutes old.
export function verifyStripeSignature(rawBody: string, header: string | null, secret: string, now = Date.now()): boolean {
  if (!header) return false; // No signature: not from Stripe.
  const parts = Object.fromEntries( // Splits the header "t=...,v1=..." into named parts:
    header.split(",").map((p) => { // for each comma-separated piece,
      const i = p.indexOf("="); // finds the "=",
      return [p.slice(0, i), p.slice(i + 1)]; // and splits it into name and value.
    }), // End of the split.
  ); // End of the named parts.
  const t = Number(parts.t); // When Stripe sent it (seconds since 1970).
  if (!t || Math.abs(now / 1000 - t) > 300) return false; // Missing, or more than 5 minutes off: refuses (stops replays).
  const expected = createHmac("sha256", secret).update(`${t}.${rawBody}`).digest("hex"); // Works out what the signature should be using the shared secret.
  const signatures = header // Collects every signature Stripe sent:
    .split(",") // splits the header into pieces,
    .filter((p) => p.startsWith("v1=")) // keeps the "v1=" signature pieces,
    .map((p) => p.slice(3)); // and drops the "v1=" label.
  return signatures.some((sig) => { // True if any signature matches:
    const a = Buffer.from(sig, "hex"); // the one sent, as bytes,
    const b = Buffer.from(expected, "hex"); // the expected one, as bytes,
    return a.length === b.length && timingSafeEqual(a, b); // same length and same bytes (compared in constant time).
  }); // End of the match check.
} // End of verifyStripeSignature.
