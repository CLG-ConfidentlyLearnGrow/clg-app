// Summary: receives messages from Stripe about saved payment methods and payments.
//
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).
import { stripeWebhookSecret } from "@/lib/billing/config"; // The secret used to check Stripe's messages.
import { recordPaymentIntent, recordSavedPaymentMethod } from "@/lib/billing/run"; // Records a saved card or bank debit, and a payment's result.
import { verifyStripeSignature, type PaymentIntent } from "@/lib/billing/stripe"; // Checks Stripe's signature, and the type of a payment.

// Messages from Stripe: a saved card or bank debit, and payment results.
// Each message is checked against Stripe's signature and handled once.
export async function POST(request: Request) {
  const secret = stripeWebhookSecret(); // The secret.
  const raw = await request.text(); // The message exactly as sent.
  if (!secret || !verifyStripeSignature(raw, request.headers.get("stripe-signature"), secret)) { // No secret, or the signature doesn't match:
    return new Response("Signature check failed", { status: 400 }); // refuses it.
  } // End of the check.
  const event = JSON.parse(raw) as { id: string; type: string; data: { object: Record<string, unknown> } }; // Reads the message.

  const db = createAdminClient(); // Connects with full access.
  const seen = await db // Logs the message as seen:
    .from("billing_webhook_events") // in the messages log,
    .insert({ provider: "stripe", event_id: event.id, event_type: event.type }) // from Stripe, with its id and type,
    .select("event_id"); // and reads it back.
  if (seen.error) { // Couldn't log it:
    // Already handled (or the log is unavailable): don't act twice.
    return new Response("Already handled", { status: 200 }); // says it's already handled.
  } // End of that case.

  try { // Tries:
    const obj = event.data.object; // the thing the message is about.
    if (event.type === "checkout.session.completed" && obj.mode === "setup" && typeof obj.setup_intent === "string") { // A finished set-up of a saved payment method:
      await recordSavedPaymentMethod(obj.setup_intent); // records it.
    } else if ( // Otherwise, if it's a payment:
      event.type === "payment_intent.succeeded" || // that succeeded,
      event.type === "payment_intent.processing" || // is in progress,
      event.type === "payment_intent.payment_failed" // or failed:
    ) { // (end of the check)
      await recordPaymentIntent(obj as unknown as PaymentIntent); // records the result.
    } // End of the choice.
  } catch (e) { // If something went wrong:
    // Let Stripe send it again later.
    await db.from("billing_webhook_events").delete().eq("provider", "stripe").eq("event_id", event.id); // removes it from the log,
    console.error("Stripe message failed:", (e as Error).message); // notes why in the server log,
    return new Response("Try again", { status: 500 }); // and asks Stripe to try again.
  } // End of the try.
  return new Response("OK", { status: 200 }); // Says it's done.
} // End of POST.
