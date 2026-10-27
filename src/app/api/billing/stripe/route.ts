import { createAdminClient } from "@/lib/supabase/admin";
import { stripeWebhookSecret } from "@/lib/billing/config";
import { recordPaymentIntent, recordSavedPaymentMethod } from "@/lib/billing/run";
import { verifyStripeSignature, type PaymentIntent } from "@/lib/billing/stripe";

// Messages from Stripe: a saved card or bank debit, and payment results.
// Each message is checked against Stripe's signature and handled once.
export async function POST(request: Request) {
  const secret = stripeWebhookSecret();
  const raw = await request.text();
  if (!secret || !verifyStripeSignature(raw, request.headers.get("stripe-signature"), secret)) {
    return new Response("Signature check failed", { status: 400 });
  }
  const event = JSON.parse(raw) as { id: string; type: string; data: { object: Record<string, unknown> } };

  const db = createAdminClient();
  const seen = await db
    .from("billing_webhook_events")
    .insert({ provider: "stripe", event_id: event.id, event_type: event.type })
    .select("event_id");
  if (seen.error) {
    // Already handled (or the log is unavailable): don't act twice.
    return new Response("Already handled", { status: 200 });
  }

  try {
    const obj = event.data.object;
    if (event.type === "checkout.session.completed" && obj.mode === "setup" && typeof obj.setup_intent === "string") {
      await recordSavedPaymentMethod(obj.setup_intent);
    } else if (
      event.type === "payment_intent.succeeded" ||
      event.type === "payment_intent.processing" ||
      event.type === "payment_intent.payment_failed"
    ) {
      await recordPaymentIntent(obj as unknown as PaymentIntent);
    }
  } catch (e) {
    // Let Stripe send it again later.
    await db.from("billing_webhook_events").delete().eq("provider", "stripe").eq("event_id", event.id);
    console.error("Stripe message failed:", (e as Error).message);
    return new Response("Try again", { status: 500 });
  }
  return new Response("OK", { status: 200 });
}
