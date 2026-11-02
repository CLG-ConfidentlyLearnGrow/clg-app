"use client";

import { chooseBillingPlan } from "@/app/actions/billing";
import { ActionForm } from "@/components/action-form";

// What each plan means, in the family's words.
const CHOICES = [
  { value: "weekly", label: "Weekly", note: "An invoice each week, paid automatically by saved card." },
  { value: "monthly", label: "Monthly", note: "An invoice each month, paid automatically by card or bank debit." },
  { value: "term", label: "Per term", note: "One invoice for the school term, due 1 week before it starts. School holidays are invoiced separately." },
  { value: "upfront", label: "All upfront", note: "Pay for a longer booking in one go." },
] as const;

export function ChoosePlanForm({ familyId, plan, chosen }: { familyId: string; plan: string; chosen: boolean }) {
  return (
    <ActionForm action={chooseBillingPlan} submitLabel={chosen ? "Save change" : "Save my choice"}>
      <input type="hidden" name="family_id" value={familyId} />
      <fieldset className="space-y-3">
        <legend className="sr-only">How often would you like to pay?</legend>
        {CHOICES.map((c) => (
          <label key={c.value} className="flex items-start gap-2 text-sm">
            <input type="radio" name="plan" value={c.value} required defaultChecked={chosen && plan === c.value} className="mt-1" />
            <span>
              <strong>{c.label}</strong>
              <span className="block text-zinc-600">{c.note}</span>
            </span>
          </label>
        ))}
      </fieldset>
    </ActionForm>
  );
}
