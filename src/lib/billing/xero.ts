// Summary: the Xero connection. CLG's owner signs in to Xero once from the
// billing page; the app keeps the sign-in encrypted and refreshes it
// automatically. This file also sends invoices, payments, credit notes and
// payroll requests to Xero, and checks messages Xero sends back.

// Stops this file ever being sent to the browser, because it handles Xero sign-ins.
import "server-only";
// Tools for encrypting, decrypting, signing and comparing data safely.
import { createCipheriv, createDecipheriv, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
// The all-powerful database helper, used to store the Xero sign-in.
import { createAdminClient } from "@/lib/supabase/admin";
// The encryption key and Xero settings.
import { encryptionKey, xeroConfig } from "./config";

// Xero connection: CLG's owner signs in to Xero once from the billing page;
// the app keeps the sign-in encrypted and refreshes it automatically.

const AUTH_URL = "https://login.xero.com/identity/connect/authorize"; // Xero's sign-in page.
const TOKEN_URL = "https://identity.xero.com/connect/token"; // Where sign-in passes are swapped and refreshed.
const API = "https://api.xero.com"; // Xero's main web address for data.

// A Xero sign-in: the short-lived pass, the long-lived refresh pass, and seconds until the first runs out.
type Tokens = { access_token: string; refresh_token: string; expires_in: number };

// Locks text with the encryption key, so the stored Xero sign-in is unreadable without it.
function encrypt(text: string): string {
  const key = encryptionKey(); // Reads the encryption key.
  if (!key) throw new Error("BILLING_ENCRYPTION_KEY is missing, so the Xero sign-in can't be stored safely."); // No key: refuses to store it.
  const iv = randomBytes(12); // A fresh random starting value, so the same text never locks the same way twice.
  const cipher = createCipheriv("aes-256-gcm", key, iv); // Sets up strong AES-256-GCM encryption.
  const data = Buffer.concat([cipher.update(text, "utf8"), cipher.final()]); // Locks the text.
  return [iv, cipher.getAuthTag(), data].map((b) => b.toString("base64")).join("."); // Stores starting value, tamper seal and locked data, joined by dots.
} // End of encrypt.

// Unlocks text locked by encrypt (fails if anyone has tampered with it).
function decrypt(stored: string): string {
  const key = encryptionKey(); // Reads the encryption key.
  if (!key) throw new Error("BILLING_ENCRYPTION_KEY is missing."); // No key: can't unlock.
  const [iv, tag, data] = stored.split(".").map((p) => Buffer.from(p, "base64")); // Splits out starting value, tamper seal and locked data.
  const decipher = createDecipheriv("aes-256-gcm", key, iv); // Sets up the matching unlock.
  decipher.setAuthTag(tag); // Gives it the tamper seal to check.
  return Buffer.concat([decipher.update(data), decipher.final()]).toString("utf8"); // Unlocks and hands back the text.
} // End of decrypt.

// The Xero sign-in page address the owner is sent to.
export function xeroSignInUrl(redirectUri: string, state: string): string {
  const cfg = xeroConfig(); // Reads the Xero settings.
  if (!cfg) throw new Error("Xero isn't set up yet (XERO_CLIENT_ID and XERO_CLIENT_SECRET are missing)."); // Not set up: plain message.
  const params = new URLSearchParams({ // The details Xero needs:
    response_type: "code", // send back a one-time code,
    client_id: cfg.clientId, // for CLG's Xero app,
    redirect_uri: redirectUri, // to this app page,
    scope: cfg.scopes, // asking for these permissions,
    state, // with this random check value (stops forged sign-ins).
  }); // End of the details.
  return `${AUTH_URL}?${params}`; // The full sign-in address.
} // End of xeroSignInUrl.

// Asks Xero for sign-in passes (first sign-in or refresh).
async function tokenRequest(body: Record<string, string>): Promise<Tokens> {
  const cfg = xeroConfig(); // Reads the Xero settings.
  if (!cfg) throw new Error("Xero isn't set up yet."); // Not set up.
  const res = await fetch(TOKEN_URL, { // Sends the request:
    method: "POST", // as a new request,
    headers: { // with these headers:
      Authorization: `Basic ${Buffer.from(`${cfg.clientId}:${cfg.clientSecret}`).toString("base64")}`, // CLG's app id and password,
      "Content-Type": "application/x-www-form-urlencoded", // as form data.
    }, // End of the headers.
    body: new URLSearchParams(body), // The details, as form data.
    cache: "no-store", // Never reuses an old saved reply.
  }); // End of the request.
  if (!res.ok) throw new Error(`Xero sign-in failed (${res.status}). Please connect Xero again.`); // Refused: plain message.
  return res.json(); // Hands back the passes.
} // End of tokenRequest.

// Stores the Xero sign-in, encrypted, in the database.
async function saveTokens(tokens: Tokens, tenantId: string, tenantName: string | null, by: string | null) {
  const db = createAdminClient(); // Connects with full access.
  const { error } = await db.from("billing_xero_connection").upsert({ // Saves (or replaces) the one connection row:
    id: true, // there's only ever one row,
    tenant_id: tenantId, // CLG's Xero organisation id,
    tenant_name: tenantName, // its name,
    tokens_encrypted: encrypt(JSON.stringify({ access: tokens.access_token, refresh: tokens.refresh_token })), // both passes, locked,
    expires_at: new Date(Date.now() + (tokens.expires_in - 60) * 1000).toISOString(), // when the pass runs out (a minute early, to be safe),
    ...(by ? { connected_by: by, connected_at: new Date().toISOString() } : {}), // and who connected it and when (first sign-in only).
  }); // End of the save.
  if (error) throw new Error("Couldn't save the Xero connection."); // Save failed: plain message.
} // End of saveTokens.

// After the owner signs in to Xero: swap the code for tokens and pick the
// organisation (CLG connects one).
export async function finishXeroSignIn(code: string, redirectUri: string, by: string) {
  const tokens = await tokenRequest({ grant_type: "authorization_code", code, redirect_uri: redirectUri }); // Swaps the one-time code for passes.
  const res = await fetch(`${API}/connections`, { // Asks Xero which organisations were connected:
    headers: { Authorization: `Bearer ${tokens.access_token}` }, // using the new pass,
    cache: "no-store", // never reusing an old saved reply.
  }); // End of the request.
  const tenants = (await res.json()) as { tenantId: string; tenantName: string; tenantType: string }[]; // The list of connections.
  const org = tenants.find((t) => t.tenantType === "ORGANISATION"); // Picks the organisation (not a practice).
  if (!org) throw new Error("No Xero organisation was chosen."); // None chosen: plain message.
  await saveTokens(tokens, org.tenantId, org.tenantName, by); // Stores the sign-in.
  return org.tenantName; // Hands back the organisation's name to show.
} // End of finishXeroSignIn.

// Reads the stored Xero connection, or null if not connected.
export async function xeroConnection() {
  const db = createAdminClient(); // Connects with full access.
  const { data } = await db.from("billing_xero_connection").select("*").maybeSingle(); // Reads the one connection row, if any.
  return data as { tenant_id: string; tenant_name: string | null; tokens_encrypted: string; expires_at: string } | null; // Hands it back.
} // End of xeroConnection.

// A fresh Xero pass and the organisation id, refreshing the pass if it's run out.
async function accessToken(): Promise<{ token: string; tenant: string } | null> {
  const conn = await xeroConnection(); // Reads the stored connection.
  if (!conn || !xeroConfig()) return null; // Not connected or not set up.
  const saved = JSON.parse(decrypt(conn.tokens_encrypted)) as { access: string; refresh: string }; // Unlocks the stored passes.
  if (new Date(conn.expires_at).getTime() > Date.now()) { // The pass is still good:
    return { token: saved.access, tenant: conn.tenant_id }; // uses it.
  } // End of the still-good case.
  const fresh = await tokenRequest({ grant_type: "refresh_token", refresh_token: saved.refresh }); // Otherwise gets new passes with the refresh pass.
  await saveTokens(fresh, conn.tenant_id, conn.tenant_name, null); // Stores the new passes.
  return { token: fresh.access_token, tenant: conn.tenant_id }; // Uses the new pass.
} // End of accessToken.

// One call to Xero's accounting API. Waits and retries once when Xero says
// "too many requests" (it allows 60 a minute).
async function xero<T>(
  method: "GET" | "POST" | "PUT", // Read, change, or make.
  path: string, // Which Xero item, e.g. "Invoices".
  body?: unknown, // The content to send, if any.
  idempotencyKey?: string, // A key that stops a retry doing it twice.
  base = "api.xro/2.0", // Which part of Xero (accounting by default).
): Promise<T> {
  const auth = await accessToken(); // Gets a fresh pass.
  if (!auth) throw new Error("Xero isn't connected."); // Not connected: plain message.
  for (let attempt = 0; attempt < 2; attempt++) { // Tries up to twice.
    const res = await fetch(`${API}/${base}/${path}`, { // Sends the request:
      method, // with this action,
      headers: { // and these headers:
        Authorization: `Bearer ${auth.token}`, // the pass,
        "Xero-tenant-id": auth.tenant, // CLG's organisation,
        Accept: "application/json", // asking for JSON back,
        "Content-Type": "application/json", // sending JSON,
        ...(idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}), // and the never-twice key, if given.
      }, // End of the headers.
      body: body ? JSON.stringify(body) : undefined, // The content as JSON text, if any.
      cache: "no-store", // Never reuses an old saved reply.
    }); // End of the request.
    if (res.status === 429 && attempt === 0) { // Too many requests on the first try:
      const wait = Math.min(Number(res.headers.get("retry-after") ?? "5"), 30); // waits as long as Xero asks (5 sec if not said, 30 at most),
      await new Promise((r) => setTimeout(r, wait * 1000)); // pauses for that long,
      continue; // and tries again.
    } // End of the too-many case.
    const json = await res.json().catch(() => ({})); // Reads Xero's reply (empty if unreadable).
    if (!res.ok) { // Xero refused:
      const detail = // finds the clearest reason, trying in turn:
        json?.Elements?.[0]?.ValidationErrors?.[0]?.Message ?? // the first item's first problem,
        json?.[0]?.ValidationErrors?.[0]?.Message ?? // or the first problem in a list reply,
        json?.Message ?? // or Xero's general message,
        res.status; // or just the status number.
      throw new Error(`Xero said: ${detail}`); // Stops with that reason.
    } // End of the refusal check.
    return json as T; // Hands back Xero's reply.
  } // End of the attempts.
  throw new Error("Xero is busy. The app will try again on the next run."); // Still too busy after two tries.
} // End of xero.

// The family's Xero contact: found by email, or made from the bill payer's
// name and email (nothing about the child).
export async function findOrCreateContact(name: string, email: string): Promise<string> {
  const where = encodeURIComponent(`EmailAddress=="${email.replace(/"/g, "")}"`); // A search for this email (quote marks removed for safety).
  const found = await xero<{ Contacts: { ContactID: string }[] }>("GET", `Contacts?where=${where}`); // Looks for an existing contact.
  if (found.Contacts?.[0]) return found.Contacts[0].ContactID; // Found one: uses it.
  const made = await xero<{ Contacts: { ContactID: string }[] }>("POST", "Contacts", { // Otherwise makes one:
    Contacts: [{ Name: name, EmailAddress: email }], // with the payer's name and email.
  }); // End of making the contact.
  return made.Contacts[0].ContactID; // Hands back the new contact's id.
} // End of findOrCreateContact.

// An invoice ready to send to Xero.
export type InvoiceForXero = {
  id: string; // The invoice's id in CLG's database.
  number: string; // The invoice number.
  contactId: string; // The family's Xero contact.
  date: string; // The invoice date.
  dueDate: string; // When it's due.
  reference: string; // A reference shown on the invoice.
  awaitingApproval: boolean; // True in the pilot, so it waits for approval in Xero.
  lines: { description: string; hours: number; hourlyCents: number; gst: boolean }[]; // Each session line: words, hours, hourly price and GST.
  discountCents: number; // Any bank debit discount, in cents.
  idempotencyKey: string; // A key so it's never sent twice.
}; // End of the invoice shape.

// Sends an invoice to Xero. In the pilot it waits there for approval
// ("Awaiting approval"); later it is approved straight away.
export async function sendInvoiceToXero(inv: InvoiceForXero): Promise<string> {
  const cfg = xeroConfig()!; // Reads the Xero settings (known to be set by now).
  const lineItems = inv.lines.map((l) => ({ // Turns each line into Xero's format:
    Description: l.description, // the words,
    Quantity: l.hours, // hours as the quantity,
    UnitAmount: l.hourlyCents / 100, // the hourly price in dollars,
    AccountCode: cfg.salesAccount, // recorded against the sales account,
    TaxType: l.gst ? "OUTPUT" : "EXEMPTOUTPUT", // with GST or GST-free.
  })); // End of the lines.
  if (inv.discountCents > 0) { // If there's a bank debit discount:
    lineItems.push({ Description: "Bank debit discount", Quantity: 1, UnitAmount: -inv.discountCents / 100, AccountCode: cfg.salesAccount, TaxType: "EXEMPTOUTPUT" }); // adds it as a negative line.
  } // End of the discount.
  const res = await xero<{ Invoices: { InvoiceID: string }[] }>( // Sends to Xero:
    "PUT", // making or updating,
    "Invoices", // an invoice,
    { // with:
      Invoices: [ // one invoice:
        { // whose details are:
          Type: "ACCREC", // money owed to CLG,
          Contact: { ContactID: inv.contactId }, // the family's contact,
          Date: inv.date, // the invoice date,
          DueDate: inv.dueDate, // the due date,
          InvoiceNumber: inv.number, // CLG's invoice number,
          Reference: inv.reference, // the reference,
          LineAmountTypes: "Inclusive", // prices already include any GST,
          Status: inv.awaitingApproval ? "SUBMITTED" : "AUTHORISED", // waiting for approval, or approved,
          LineItems: lineItems, // and the lines.
        }, // End of the invoice.
      ], // End of the list.
    }, // End of the content.
    `invoice-${inv.idempotencyKey}`, // The never-twice key.
  ); // End of the request.
  return res.Invoices[0].InvoiceID; // Hands back Xero's id for it.
} // End of sendInvoiceToXero.

// Reads one invoice from Xero, including how much has been paid.
export async function getXeroInvoice(id: string) {
  const res = await xero<{ Invoices: { InvoiceID: string; Status: string; AmountPaid: number; AmountCredited?: number; Payments?: { PaymentID: string; Amount: number }[] }[] }>( // Asks Xero for:
    "GET", // a read of
    `Invoices/${id}`, // this invoice.
  ); // End of the request.
  return res.Invoices[0]; // Hands back the invoice.
} // End of getXeroInvoice.

// Records a Stripe payment against the invoice, into the Stripe clearing
// account, so the payout matches in Xero's bank feed.
export async function recordXeroPayment(xeroInvoiceId: string, amountCents: number, date: string, reference: string) {
  const cfg = xeroConfig()!; // Reads the Xero settings.
  if (!cfg.clearingAccount) throw new Error("XERO_STRIPE_CLEARING_ACCOUNT is missing."); // Needs the clearing account.
  const res = await xero<{ Payments: { PaymentID: string }[] }>( // Sends to Xero:
    "PUT", // making
    "Payments", // a payment,
    { // with:
      Payments: [ // one payment: against this invoice, into the clearing account, on this date, for this amount, with this reference.
        { Invoice: { InvoiceID: xeroInvoiceId }, Account: { Code: cfg.clearingAccount }, Date: date, Amount: amountCents / 100, Reference: reference },
      ], // End of the list.
    }, // End of the content.
    `payment-${reference}`, // The never-twice key.
  ); // End of the request.
  return res.Payments[0].PaymentID; // Hands back Xero's id for it.
} // End of recordXeroPayment.

// Checks that a message really came from Xero (x-xero-signature header).
export function verifyXeroSignature(rawBody: string, header: string | null, key: string): boolean {
  if (!header) return false; // No signature: not from Xero.
  const expected = createHmac("sha256", key).update(rawBody).digest(); // Works out what the signature should be.
  const given = Buffer.from(header, "base64"); // The signature that was sent, as bytes.
  return given.length === expected.length && timingSafeEqual(given, expected); // Same length and bytes (compared in constant time).
} // End of verifyXeroSignature.

// Xero Payroll (Australia). Kept in one place so the version can change
// without touching the rest of the app.
const PAYROLL_BASE = process.env.XERO_PAYROLL_BASE ?? "payroll.xro/1.0";

// One call to Xero Payroll (same as the accounting call, different part of Xero).
export function xeroPayroll<T>(method: "GET" | "POST", path: string, body?: unknown, idempotencyKey?: string) {
  return xero<T>(method, path, body, idempotencyKey, PAYROLL_BASE); // Uses the shared call with the payroll address.
} // End of xeroPayroll.

// A family's credit (for example a cancellation) as a credit note on their
// Xero contact, ready to apply to a later invoice.
export async function createCreditNote(opts: {
  contactId: string; // The family's Xero contact.
  date: string; // The credit date.
  description: string; // What the credit is for.
  amountCents: number; // How much, in cents.
  gst: boolean; // Whether GST applies.
  reference: string; // A reference (also used as the never-twice key).
}): Promise<string> {
  const cfg = xeroConfig()!; // Reads the Xero settings.
  const res = await xero<{ CreditNotes: { CreditNoteID: string }[] }>( // Sends to Xero:
    "PUT", // making
    "CreditNotes", // a credit note,
    { // with:
      CreditNotes: [ // one credit note:
        { // whose details are:
          Type: "ACCRECCREDIT", // credit owed to a family,
          Contact: { ContactID: opts.contactId }, // their contact,
          Date: opts.date, // the date,
          Status: "AUTHORISED", // approved,
          LineAmountTypes: "Inclusive", // amounts include any GST,
          Reference: opts.reference, // the reference,
          LineItems: [ // and one line:
            { // whose details are:
              Description: opts.description, // what it's for,
              Quantity: 1, // one,
              UnitAmount: opts.amountCents / 100, // the amount in dollars,
              AccountCode: cfg.salesAccount, // against the sales account,
              TaxType: opts.gst ? "OUTPUT" : "EXEMPTOUTPUT", // with GST or GST-free.
            }, // End of the line.
          ], // End of the lines.
        }, // End of the credit note.
      ], // End of the list.
    }, // End of the content.
    `credit-${opts.reference}`, // The never-twice key.
  ); // End of the request.
  return res.CreditNotes[0].CreditNoteID; // Hands back Xero's id for it.
} // End of createCreditNote.

// The contact's credit notes that still have credit left, oldest first.
export async function openCreditNotes(contactId: string) {
  const where = encodeURIComponent(`Contact.ContactID==guid("${contactId}") AND Status=="AUTHORISED" AND Type=="ACCRECCREDIT"`); // A search: this family's approved credit notes.
  const res = await xero<{ CreditNotes: { CreditNoteID: string; RemainingCredit: number; Date: string }[] }>( // Asks Xero for:
    "GET", // a read of
    `CreditNotes?where=${where}&order=Date`, // matching credit notes, oldest first.
  ); // End of the request.
  return (res.CreditNotes ?? []).filter((c) => c.RemainingCredit > 0); // Keeps only those with credit left.
} // End of openCreditNotes.

// Applies part of a credit note to an invoice.
export async function allocateCreditNote(creditNoteId: string, invoiceId: string, amountCents: number, date: string) {
  await xero("PUT", `CreditNotes/${creditNoteId}/Allocations`, { // Tells Xero to use this credit note:
    Allocations: [{ Invoice: { InvoiceID: invoiceId }, Amount: amountCents / 100, Date: date }], // against this invoice, for this amount, on this date.
  }); // End of the request.
} // End of allocateCreditNote.
