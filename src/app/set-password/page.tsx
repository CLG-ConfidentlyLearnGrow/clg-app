import { setNewPassword } from "@/app/actions/auth";
import { ActionForm } from "@/components/action-form";
import { Card, Field, Page } from "@/components/ui";
import { requireViewer } from "@/lib/auth";

// Reached from a password reset or invitation link.
export default async function SetPasswordPage() {
  await requireViewer();
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
        </ActionForm>
      </Card>
    </Page>
  );
}
