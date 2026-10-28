import { redirect } from "next/navigation";
import { agreeToPolicies } from "@/app/actions/family-setup";
import { ActionForm } from "@/components/action-form";
import { Card, Page, TextLink } from "@/components/ui";
import { requireViewer } from "@/lib/auth";
import { POLICY_VERSION } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// Families whose account CLG set up agree to the privacy policy and terms
// here before using the app.
export default async function AgreePage() {
  await requireViewer();
  const supabase = await createClient();
  const { data } = await supabase.rpc("my_policy_consent", { p_version: POLICY_VERSION });
  if (data === true) redirect("/dashboard");

  return (
    <Page title="Welcome to CLG">
      <Card>
        <p className="mb-4 text-sm">
          Before you start, please read how CLG looks after your information and the terms of our support. CLG set up
          your account with the details you gave us. You can check and change them on your dashboard.
        </p>
        <ActionForm action={agreeToPolicies} submitLabel="Agree and continue">
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" name="accept" required className="mt-1" />
            <span>
              I agree to CLG&apos;s <TextLink href="/privacy">privacy policy and terms</TextLink>.
            </span>
          </label>
        </ActionForm>
      </Card>
    </Page>
  );
}
