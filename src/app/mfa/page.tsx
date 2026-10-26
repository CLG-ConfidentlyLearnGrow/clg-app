import { verifyTwoStep } from "@/app/actions/mfa";
import { ActionForm } from "@/components/action-form";
import { Card, Field, Page } from "@/components/ui";
import { requireViewer } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { EnrollTwoStep } from "./enroll";

export default async function TwoStepPage() {
  const viewer = await requireViewer();
  if (viewer.aal === "aal2") redirect("/dashboard");

  const supabase = await createClient();
  const factors = await supabase.auth.mfa.listFactors();
  const verified = (factors.data?.totp ?? []).find((f) => f.status === "verified");

  return (
    <Page title="Two-step login">
      <Card>
        {verified ? (
          <ActionForm action={verifyTwoStep} submitLabel="Continue">
            <p className="text-sm">Enter the 6-digit code from your authenticator app.</p>
            <input type="hidden" name="factorId" value={verified.id} />
            <Field label="6-digit code" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="\d{6}" required />
          </ActionForm>
        ) : (
          <EnrollTwoStep />
        )}
      </Card>
    </Page>
  );
}
