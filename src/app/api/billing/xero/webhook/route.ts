import { createAdminClient } from "@/lib/supabase/admin";
import { xeroConfig } from "@/lib/billing/config";
import { getXeroInvoice, verifyXeroSignature } from "@/lib/billing/xero";

// Messages from Xero when an invoice changes (for example Carla approves
// one, or records a payment by hand). Xero needs a 401 for a bad
// signature and a 200 within 5 seconds for a good one.
export async function POST(request: Request) {
  const key = xeroConfig()?.webhookKey;
  const raw = await request.text();
  if (!key || !verifyXeroSignature(raw, request.headers.get("x-xero-signature"), key)) {
    return new Response(null, { status: 401 });
  }
  const body = JSON.parse(raw) as {
    events: { resourceId: string; eventCategory: string; eventType: string; eventDateUtc: string }[];
  };
  const db = createAdminClient();

  for (const ev of body.events ?? []) {
    if (ev.eventCategory !== "INVOICE") continue;
    const eventId = `${ev.resourceId}:${ev.eventDateUtc}`;
    const seen = await db.from("billing_webhook_events").insert({ provider: "xero", event_id: eventId, event_type: ev.eventType });
    if (seen.error) continue;

    const { data: inv } = await db
      .from("billing_invoices")
      .select("id, status, total_cents")
      .eq("xero_invoice_id", ev.resourceId)
      .maybeSingle();
    if (!inv) continue;
    try {
      const x = await getXeroInvoice(ev.resourceId);
      if (inv.status === "awaiting_approval" && ["AUTHORISED", "PAID"].includes(x.Status)) {
        await db.rpc("billing_approve_invoice", { p_invoice: inv.id });
      }
      if (["VOIDED", "DELETED"].includes(x.Status) && !["paid", "void"].includes(inv.status)) {
        await db.rpc("billing_void_invoice", { p_invoice: inv.id, p_reason: "Cancelled in Xero" });
      }
      // A payment entered by hand in Xero (not through Stripe). Skipped once
      // the app already has the invoice as paid, so a Stripe payment the app
      // itself sent to Xero is never counted twice.
      for (const p of inv.status === "paid" ? [] : (x.Payments ?? [])) {
        const { data: known } = await db.from("billing_payments").select("id").eq("xero_payment_id", p.PaymentID).maybeSingle();
        if (known) continue;
        await db.rpc("billing_record_payment", {
          p_invoice: inv.id,
          p_provider: "manual",
          p_ref: p.PaymentID,
          p_method: "none",
          p_amount_cents: Math.round(p.Amount * 100),
          p_status: "succeeded",
          p_message: "Recorded in Xero",
        });
        await db.from("billing_payments").update({ xero_payment_id: p.PaymentID }).eq("provider", "manual").eq("provider_ref", p.PaymentID);
      }
    } catch (e) {
      await db.from("billing_webhook_events").delete().eq("provider", "xero").eq("event_id", eventId);
      console.error("Xero message failed:", (e as Error).message);
    }
  }
  return new Response(null, { status: 200 });
}
