"use client";

import { acceptBillingTerms } from "@/app/actions/billing";
import { ActionForm } from "@/components/action-form";

export function AcceptTermsForm({ familyId }: { familyId: string }) {
  return (
    <ActionForm action={acceptBillingTerms} submitLabel="Agree">
      <input type="hidden" name="family_id" value={familyId} />
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" name="agree" required className="mt-1" />
        <span>I agree to CLG&apos;s payment terms above.</span>
      </label>
    </ActionForm>
  );
}
