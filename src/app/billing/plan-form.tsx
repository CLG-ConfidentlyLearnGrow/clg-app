// Summary: the form where a family chooses how often to pay.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { chooseBillingPlan } from "@/app/actions/billing"; // The server action that saves the choice.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.

// What each plan means, in the family's words.
const CHOICES = [ // The choices:
  { value: "weekly", label: "Weekly", note: "An invoice each week, paid automatically by saved card." }, // weekly,
  { value: "monthly", label: "Monthly", note: "An invoice each month, paid automatically by card or bank debit." }, // monthly,
  { value: "term", label: "Per term", note: "One invoice for the school term, due 1 week before it starts. School holidays are invoiced separately." }, // per term,
  { value: "upfront", label: "All upfront", note: "Pay for a longer booking in one go." }, // all upfront.
] as const; // End of the choices (fixed).

// Shows the plan choices, with the current one ticked.
export function ChoosePlanForm({ familyId, plan, chosen }: { familyId: string; plan: string; chosen: boolean }) {
  return ( // Shows:
    <ActionForm action={chooseBillingPlan} submitLabel={chosen ? "Save change" : "Save my choice"}>{/* a form that saves the choice, with the right button words: */}
      <input type="hidden" name="family_id" value={familyId} />{/* the family's id (hidden), */}
      <fieldset className="space-y-3">{/* a group of choices: */}
        <legend className="sr-only">How often would you like to pay?</legend>{/* its heading, for screen readers only, */}
        {CHOICES.map((c) => ( // for each choice:
          <label key={c.value} className="flex items-start gap-2 text-sm">{/* a line holding: */}
            <input type="radio" name="plan" value={c.value} required defaultChecked={chosen && plan === c.value} className="mt-1" />{/* a round button for this choice, ticked if it's the current plan, */}
            <span>{/* the words: */}
              <strong>{c.label}</strong>{/* the plan's name in bold, */}
              <span className="block text-zinc-600">{c.note}</span>{/* and its note below. */}
            </span>{/* End of the words. */}
          </label> // End of the line.
        ))}{/* End of the choices loop. */}
      </fieldset>{/* End of the group. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of ChoosePlanForm.
