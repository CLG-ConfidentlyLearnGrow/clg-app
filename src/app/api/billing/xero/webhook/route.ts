// Summary: receives messages from Xero when an invoice changes.
//
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).
import { xeroConfig } from "@/lib/billing/config"; // Xero's settings.
import { getXeroInvoice, verifyXeroSignature } from "@/lib/billing/xero"; // Reads an invoice from Xero, and checks Xero's signature.

// Messages from Xero when an invoice changes (for example Carla approves
// one, or records a payment by hand). Xero needs a 401 for a bad
// signature and a 200 within 5 seconds for a good one.
export async function POST(request: Request) {
  const key = xeroConfig()?.webhookKey; // The key used to check Xero's messages.
  const raw = await request.text(); // The message exactly as sent.
  if (!key || !verifyXeroSignature(raw, request.headers.get("x-xero-signature"), key)) { // No key, or the signature doesn't match:
    return new Response(null, { status: 401 }); // refuses it, as Xero requires.
  } // End of the check.
  const body = JSON.parse(raw) as { // Reads the message:
    events: { resourceId: string; eventCategory: string; eventType: string; eventDateUtc: string }[]; // a list of changes, each with its invoice id, kind, change and time.
  }; // (end of the shape)
  const db = createAdminClient(); // Connects with full access.

  for (const ev of body.events ?? []) { // For each change:
    if (ev.eventCategory !== "INVOICE") continue; // skips anything that isn't an invoice.
    const eventId = `${ev.resourceId}:${ev.eventDateUtc}`; // A unique id for this change.
    const seen = await db.from("billing_webhook_events").insert({ provider: "xero", event_id: eventId, event_type: ev.eventType }); // Logs it as seen.
    if (seen.error) continue; // Already seen: skips it.

    const { data: inv } = await db // Finds the app's invoice:
      .from("billing_invoices") // in the invoices table,
      .select("id, status, total_cents") // its id, status and total,
      .eq("xero_invoice_id", ev.resourceId) // matching the Xero invoice,
      .maybeSingle(); // (one at most).
    if (!inv) continue; // Not one of ours: skips it.
    try { // Tries:
      const x = await getXeroInvoice(ev.resourceId); // reads the invoice from Xero.
      if (inv.status === "awaiting_approval" && ["AUTHORISED", "PAID"].includes(x.Status)) { // Approved (or paid) in Xero while waiting for approval here:
        await db.rpc("billing_approve_invoice", { p_invoice: inv.id }); // approves it here too.
      } // End of that case.
      if (["VOIDED", "DELETED"].includes(x.Status) && !["paid", "void"].includes(inv.status)) { // Cancelled in Xero, and not already paid or cancelled here:
        await db.rpc("billing_void_invoice", { p_invoice: inv.id, p_reason: "Cancelled in Xero" }); // cancels it here too.
      } // End of that case.
      // A payment entered by hand in Xero (not through Stripe). Skipped once
      // the app already has the invoice as paid, so a Stripe payment the app
      // itself sent to Xero is never counted twice.
      for (const p of inv.status === "paid" ? [] : (x.Payments ?? [])) { // For each payment in Xero (none if already paid here):
        const { data: known } = await db.from("billing_payments").select("id").eq("xero_payment_id", p.PaymentID).maybeSingle(); // looks for it among known payments.
        if (known) continue; // Already known: skips it.
        await db.rpc("billing_record_payment", { // Records it:
          p_invoice: inv.id, // on this invoice,
          p_provider: "manual", // entered by hand,
          p_ref: p.PaymentID, // with Xero's payment id,
          p_method: "none", // no payment method,
          p_amount_cents: Math.round(p.Amount * 100), // the amount in cents,
          p_status: "succeeded", // as succeeded,
          p_message: "Recorded in Xero", // with a note.
        }); // End of the record.
        await db.from("billing_payments").update({ xero_payment_id: p.PaymentID }).eq("provider", "manual").eq("provider_ref", p.PaymentID); // Links the payment to Xero's id.
      } // End of the payments loop.
    } catch (e) { // If something went wrong:
      await db.from("billing_webhook_events").delete().eq("provider", "xero").eq("event_id", eventId); // removes the change from the log so it can be tried again,
      console.error("Xero message failed:", (e as Error).message); // and notes why in the server log.
    } // End of the try.
  } // End of the changes loop.
  return new Response(null, { status: 200 }); // Tells Xero it was received.
} // End of POST.
