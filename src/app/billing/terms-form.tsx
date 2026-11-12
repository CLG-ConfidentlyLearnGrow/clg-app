// Summary: the form where a family agrees to CLG's payment terms.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { acceptBillingTerms } from "@/app/actions/billing"; // The server action that records the agreement.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.

// Shows the agree box and button for one family.
export function AcceptTermsForm({ familyId }: { familyId: string }) {
  return ( // Shows:
    <ActionForm action={acceptBillingTerms} submitLabel="Agree">{/* a form that records the agreement, with an "Agree" button: */}
      <input type="hidden" name="family_id" value={familyId} />{/* the family's id (hidden), */}
      <label className="flex items-start gap-2 text-sm">{/* a line holding: */}
        <input type="checkbox" name="agree" required className="mt-1" />{/* a tick box that must be ticked, */}
        <span>I agree to CLG&apos;s payment terms above.</span>{/* and its words. */}
      </label>{/* End of the line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AcceptTermsForm.
