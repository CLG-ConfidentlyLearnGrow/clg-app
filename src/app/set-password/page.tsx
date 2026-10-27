import { setNewPassword } from "@/app/actions/auth";
import { ActionForm } from "@/components/action-form";
import { Card, Field, Page } from "@/components/ui";
import { requireViewer } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

// Reached from a password reset or invitation link.
export default async function SetPasswordPage() {
  const viewer = await requireViewer();

  // People who use two-step login must enter their code before Supabase
  // lets them change their password. A reset link only signs them in with
  // the first step, so we ask for the code here.
  let factorId: string | null = null;
  if (viewer.aal !== "aal2") {
    const supabase = await createClient();
    const factors = await supabase.auth.mfa.listFactors();
    factorId = (factors.data?.totp ?? []).find((f) => f.status === "verified")?.id ?? null;
  }

  return (
    <Page title="Choose a password">
      <Card>
        <ActionForm action={setNewPassword} submitLabel="Save password">
          <Field
            label="New password"
            name="password"
            type="password"
            autoComplete="new-password"
            required
            minLength={12}
            hint="At least 12 characters, with upper and lowercase letters and a number."
          />
          <Field label="Type it again" name="confirm" type="password" autoComplete="new-password" required />
          {factorId && (
            <>
              <input type="hidden" name="factorId" value={factorId} />
              <Field
                label="6-digit code from your authenticator app"
                name="code"
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="\d{6}"
                required
              />
            </>
          )}
        </ActionForm>
      </Card>
    </Page>
  );
}
