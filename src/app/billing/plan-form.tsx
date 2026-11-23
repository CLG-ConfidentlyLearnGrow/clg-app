// Summary: the forms where a family chooses how often to pay, and cancels a
// plan change they booked for their next invoice.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { cancelBillingPlanChange, chooseBillingPlan } from "@/app/actions/billing"; // The server actions that save the choice and cancel a booked change.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { dollars } from "@/lib/billing/money"; // Shows cents as dollars, for the plan fees.

// What each plan means, in the family's words.
const CHOICES = [ // The choices:
  { value: "weekly", label: "Weekly", note: "An invoice each week, paid automatically by saved card." }, // weekly,
  { value: "monthly", label: "Monthly", note: "An invoice each month, paid automatically by card or bank debit." }, // monthly,
  { value: "term", label: "Per term", note: "One invoice for the school term, due 1 week before it starts. School holidays are invoiced separately." }, // per term,
  { value: "upfront", label: "All upfront", note: "Pay for a longer booking in one go." }, // all upfront.
] as const; // End of the choices (fixed).

// The plan fee note for a plan (Carla, 22 Nov 2026), or nothing when there is no fee.
function feeNote(value: string, fees: { monthly: number; weekly: number }): string { // Takes the plan and the fees in cents.
  const cents = value === "monthly" ? fees.monthly : value === "weekly" ? fees.weekly : 0; // The fee for this plan (none for per term or all upfront).
  return cents > 0 ? ` A ${dollars(cents)} payment plan fee is added to each invoice, however you pay.` : ""; // The note, or nothing.
} // End of feeNote.

// Shows the plan choices, with the current one ticked, and any plan fee.
export function ChoosePlanForm({ familyId, plan, chosen, fees }: { familyId: string; plan: string; chosen: boolean; fees: { monthly: number; weekly: number } }) {
  return ( // Shows:
    <ActionForm action={chooseBillingPlan} submitLabel={chosen ? "Save change" : "Save my choice"}>{/* a form that saves the choice, with the right button words: */}
      <input type="hidden" name="family_id" value={familyId} />{/* the family's id (hidden), */}
      <fieldset className="space-y-3">{/* a group of choices: */}
        <legend className="sr-only">How often would you like to pay?</legend>{/* its heading, for screen readers only, */}
        {CHOICES.map((c) => ( // for each choice:
          <label key={c.value} className="flex items-start gap-2 text-sm">{/* a line holding: */}
            <input type="radio" name="plan" value={c.value} required defaultChecked={chosen && plan === c.value} className="mt-1" />{/* a round button for this choice, ticked if it is the current plan, */}
            <span>{/* the words: */}
              <strong>{c.label}</strong>{/* the plan's name in bold, */}
              <span className="block text-zinc-600">{c.note}{feeNote(c.value, fees)}</span>{/* and its note below, with any plan fee. */}
            </span>{/* End of the words. */}
          </label> // End of the line.
        ))}{/* End of the choices loop. */}
      </fieldset>{/* End of the group. */}
    </ActionForm> // End of the form.
  ); // End of what is shown.
} // End of ChoosePlanForm.

// A button that cancels a plan change booked for the next invoice.
export function CancelPlanChangeForm({ familyId }: { familyId: string }) { // Takes the family's id.
  return ( // Shows:
    <ActionForm action={cancelBillingPlanChange} submitLabel="Cancel this change">{/* a form that cancels the booked change, */}
      <input type="hidden" name="family_id" value={familyId} />{/* with the family's id (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what is shown.
} // End of CancelPlanChangeForm.
