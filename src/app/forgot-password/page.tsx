import { requestPasswordReset } from "@/app/actions/auth";
import { ActionForm } from "@/components/action-form";
import { Card, Field, Page, TextLink } from "@/components/ui";

export default function ForgotPasswordPage() {
  return (
    <Page title="Reset your password">
      <Card>
        <p className="mb-4 text-sm">Resetting your password also unlocks a locked account.</p>
        <ActionForm action={requestPasswordReset} submitLabel="Send reset link">
          <Field label="Email" name="email" type="email" autoComplete="email" required />
        </ActionForm>
        <p className="mt-4 text-sm">
          <TextLink href="/login">Back to sign in</TextLink>
        </p>
      </Card>
    </Page>
  );
}
