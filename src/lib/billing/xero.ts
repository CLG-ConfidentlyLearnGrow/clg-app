import "server-only";
import { createCipheriv, createDecipheriv, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { createAdminClient } from "@/lib/supabase/admin";
import { encryptionKey, xeroConfig } from "./config";

// Xero connection: CLG's owner signs in to Xero once from the billing page;
// the app keeps the sign-in encrypted and refreshes it automatically.

const AUTH_URL = "https://login.xero.com/identity/connect/authorize";
const TOKEN_URL = "https://identity.xero.com/connect/token";
const API = "https://api.xero.com";

type Tokens = { access_token: string; refresh_token: string; expires_in: number };

function encrypt(text: string): string {
  const key = encryptionKey();
  if (!key) throw new Error("BILLING_ENCRYPTION_KEY is missing, so the Xero sign-in can't be stored safely.");
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const data = Buffer.concat([cipher.update(text, "utf8"), cipher.final()]);
  return [iv, cipher.getAuthTag(), data].map((b) => b.toString("base64")).join(".");
}

function decrypt(stored: string): string {
  const key = encryptionKey();
  if (!key) throw new Error("BILLING_ENCRYPTION_KEY is missing.");
  const [iv, tag, data] = stored.split(".").map((p) => Buffer.from(p, "base64"));
  const decipher = createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString("utf8");
}

export function xeroSignInUrl(redirectUri: string, state: string): string {
  const cfg = xeroConfig();
  if (!cfg) throw new Error("Xero isn't set up yet (XERO_CLIENT_ID and XERO_CLIENT_SECRET are missing).");
  const params = new URLSearchParams({
    response_type: "code",
    client_id: cfg.clientId,
    redirect_uri: redirectUri,
    scope: cfg.scopes,
    state,
  });
  return `${AUTH_URL}?${params}`;
}

async function tokenRequest(body: Record<string, string>): Promise<Tokens> {
  const cfg = xeroConfig();
  if (!cfg) throw new Error("Xero isn't set up yet.");
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${cfg.clientId}:${cfg.clientSecret}`).toString("base64")}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(body),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`Xero sign-in failed (${res.status}). Please connect Xero again.`);
  return res.json();
}

async function saveTokens(tokens: Tokens, tenantId: string, tenantName: string | null, by: string | null) {
  const db = createAdminClient();
  const { error } = await db.from("billing_xero_connection").upsert({
    id: true,
    tenant_id: tenantId,
    tenant_name: tenantName,
    tokens_encrypted: encrypt(JSON.stringify({ access: tokens.access_token, refresh: tokens.refresh_token })),
    expires_at: new Date(Date.now() + (tokens.expires_in - 60) * 1000).toISOString(),
    ...(by ? { connected_by: by, connected_at: new Date().toISOString() } : {}),
  });
  if (error) throw new Error("Couldn't save the Xero connection.");
}

// After the owner signs in to Xero: swap the code for tokens and pick the
// organisation (CLG connects one).
export async function finishXeroSignIn(code: string, redirectUri: string, by: string) {
  const tokens = await tokenRequest({ grant_type: "authorization_code", code, redirect_uri: redirectUri });
  const res = await fetch(`${API}/connections`, {
    headers: { Authorization: `Bearer ${tokens.access_token}` },
    cache: "no-store",
  });
  const tenants = (await res.json()) as { tenantId: string; tenantName: string; tenantType: string }[];
  const org = tenants.find((t) => t.tenantType === "ORGANISATION");
  if (!org) throw new Error("No Xero organisation was chosen.");
  await saveTokens(tokens, org.tenantId, org.tenantName, by);
  return org.tenantName;
}

export async function xeroConnection() {
  const db = createAdminClient();
  const { data } = await db.from("billing_xero_connection").select("*").maybeSingle();
  return data as { tenant_id: string; tenant_name: string | null; tokens_encrypted: string; expires_at: string } | null;
}

async function accessToken(): Promise<{ token: string; tenant: string } | null> {
  const conn = await xeroConnection();
  if (!conn || !xeroConfig()) return null;
  const saved = JSON.parse(decrypt(conn.tokens_encrypted)) as { access: string; refresh: string };
  if (new Date(conn.expires_at).getTime() > Date.now()) {
    return { token: saved.access, tenant: conn.tenant_id };
  }
  const fresh = await tokenRequest({ grant_type: "refresh_token", refresh_token: saved.refresh });
  await saveTokens(fresh, conn.tenant_id, conn.tenant_name, null);
  return { token: fresh.access_token, tenant: conn.tenant_id };
}

// One call to Xero's accounting API. Waits and retries once when Xero says
// "too many requests" (it allows 60 a minute).
async function xero<T>(
  method: "GET" | "POST" | "PUT",
  path: string,
  body?: unknown,
  idempotencyKey?: string,
  base = "api.xro/2.0",
): Promise<T> {
  const auth = await accessToken();
  if (!auth) throw new Error("Xero isn't connected.");
  for (let attempt = 0; attempt < 2; attempt++) {
    const res = await fetch(`${API}/${base}/${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${auth.token}`,
        "Xero-tenant-id": auth.tenant,
        Accept: "application/json",
        "Content-Type": "application/json",
        ...(idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      cache: "no-store",
    });
    if (res.status === 429 && attempt === 0) {
      const wait = Math.min(Number(res.headers.get("retry-after") ?? "5"), 30);
      await new Promise((r) => setTimeout(r, wait * 1000));
      continue;
    }
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const detail =
        json?.Elements?.[0]?.ValidationErrors?.[0]?.Message ??
        json?.[0]?.ValidationErrors?.[0]?.Message ??
        json?.Message ??
        res.status;
      throw new Error(`Xero said: ${detail}`);
    }
    return json as T;
  }
  throw new Error("Xero is busy. The app will try again on the next run.");
}

// The family's Xero contact: found by email, or made from the bill payer's
// name and email (nothing about the child).
export async function findOrCreateContact(name: string, email: string): Promise<string> {
  const where = encodeURIComponent(`EmailAddress=="${email.replace(/"/g, "")}"`);
  const found = await xero<{ Contacts: { ContactID: string }[] }>("GET", `Contacts?where=${where}`);
  if (found.Contacts?.[0]) return found.Contacts[0].ContactID;
  const made = await xero<{ Contacts: { ContactID: string }[] }>("POST", "Contacts", {
    Contacts: [{ Name: name, EmailAddress: email }],
  });
  return made.Contacts[0].ContactID;
}

export type InvoiceForXero = {
  id: string;
  number: string;
  contactId: string;
  date: string;
  dueDate: string;
  reference: string;
  awaitingApproval: boolean;
  lines: { description: string; hours: number; hourlyCents: number; gst: boolean }[];
  discountCents: number;
  idempotencyKey: string;
};

// Sends an invoice to Xero. In the pilot it waits there for approval
// ("Awaiting approval"); later it is approved straight away.
export async function sendInvoiceToXero(inv: InvoiceForXero): Promise<string> {
  const cfg = xeroConfig()!;
  const lineItems = inv.lines.map((l) => ({
    Description: l.description,
    Quantity: l.hours,
    UnitAmount: l.hourlyCents / 100,
    AccountCode: cfg.salesAccount,
    TaxType: l.gst ? "OUTPUT" : "EXEMPTOUTPUT",
  }));
  if (inv.discountCents > 0) {
    lineItems.push({ Description: "Bank debit discount", Quantity: 1, UnitAmount: -inv.discountCents / 100, AccountCode: cfg.salesAccount, TaxType: "EXEMPTOUTPUT" });
  }
  const res = await xero<{ Invoices: { InvoiceID: string }[] }>(
    "PUT",
    "Invoices",
    {
      Invoices: [
        {
          Type: "ACCREC",
          Contact: { ContactID: inv.contactId },
          Date: inv.date,
          DueDate: inv.dueDate,
          InvoiceNumber: inv.number,
          Reference: inv.reference,
          LineAmountTypes: "Inclusive",
          Status: inv.awaitingApproval ? "SUBMITTED" : "AUTHORISED",
          LineItems: lineItems,
        },
      ],
    },
    `invoice-${inv.idempotencyKey}`,
  );
  return res.Invoices[0].InvoiceID;
}

export async function getXeroInvoice(id: string) {
  const res = await xero<{ Invoices: { InvoiceID: string; Status: string; AmountPaid: number; AmountCredited?: number; Payments?: { PaymentID: string; Amount: number }[] }[] }>(
    "GET",
    `Invoices/${id}`,
  );
  return res.Invoices[0];
}

// Records a Stripe payment against the invoice, into the Stripe clearing
// account, so the payout matches in Xero's bank feed.
export async function recordXeroPayment(xeroInvoiceId: string, amountCents: number, date: string, reference: string) {
  const cfg = xeroConfig()!;
  if (!cfg.clearingAccount) throw new Error("XERO_STRIPE_CLEARING_ACCOUNT is missing.");
  const res = await xero<{ Payments: { PaymentID: string }[] }>(
    "PUT",
    "Payments",
    {
      Payments: [
        { Invoice: { InvoiceID: xeroInvoiceId }, Account: { Code: cfg.clearingAccount }, Date: date, Amount: amountCents / 100, Reference: reference },
      ],
    },
    `payment-${reference}`,
  );
  return res.Payments[0].PaymentID;
}

// Checks that a message really came from Xero (x-xero-signature header).
export function verifyXeroSignature(rawBody: string, header: string | null, key: string): boolean {
  if (!header) return false;
  const expected = createHmac("sha256", key).update(rawBody).digest();
  const given = Buffer.from(header, "base64");
  return given.length === expected.length && timingSafeEqual(given, expected);
}

// Xero Payroll (Australia). Kept in one place so the version can change
// without touching the rest of the app.
const PAYROLL_BASE = process.env.XERO_PAYROLL_BASE ?? "payroll.xro/1.0";

export function xeroPayroll<T>(method: "GET" | "POST", path: string, body?: unknown, idempotencyKey?: string) {
  return xero<T>(method, path, body, idempotencyKey, PAYROLL_BASE);
}

// A family's credit (for example a cancellation) as a credit note on their
// Xero contact, ready to apply to a later invoice.
export async function createCreditNote(opts: {
  contactId: string;
  date: string;
  description: string;
  amountCents: number;
  gst: boolean;
  reference: string;
}): Promise<string> {
  const cfg = xeroConfig()!;
  const res = await xero<{ CreditNotes: { CreditNoteID: string }[] }>(
    "PUT",
    "CreditNotes",
    {
      CreditNotes: [
        {
          Type: "ACCRECCREDIT",
          Contact: { ContactID: opts.contactId },
          Date: opts.date,
          Status: "AUTHORISED",
          LineAmountTypes: "Inclusive",
          Reference: opts.reference,
          LineItems: [
            {
              Description: opts.description,
              Quantity: 1,
              UnitAmount: opts.amountCents / 100,
              AccountCode: cfg.salesAccount,
              TaxType: opts.gst ? "OUTPUT" : "EXEMPTOUTPUT",
            },
          ],
        },
      ],
    },
    `credit-${opts.reference}`,
  );
  return res.CreditNotes[0].CreditNoteID;
}

// The contact's credit notes that still have credit left, oldest first.
export async function openCreditNotes(contactId: string) {
  const where = encodeURIComponent(`Contact.ContactID==guid("${contactId}") AND Status=="AUTHORISED" AND Type=="ACCRECCREDIT"`);
  const res = await xero<{ CreditNotes: { CreditNoteID: string; RemainingCredit: number; Date: string }[] }>(
    "GET",
    `CreditNotes?where=${where}&order=Date`,
  );
  return (res.CreditNotes ?? []).filter((c) => c.RemainingCredit > 0);
}

// Applies part of a credit note to an invoice.
export async function allocateCreditNote(creditNoteId: string, invoiceId: string, amountCents: number, date: string) {
  await xero("PUT", `CreditNotes/${creditNoteId}/Allocations`, {
    Allocations: [{ Invoice: { InvoiceID: invoiceId }, Amount: amountCents / 100, Date: date }],
  });
}
