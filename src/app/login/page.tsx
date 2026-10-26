import { signIn } from "@/app/actions/auth";
import { ActionForm } from "@/components/action-form";
import { Card, Field, Page, TextLink } from "@/components/ui";

export default async function LoginPage({ searchParams }: PageProps<"/login">) {
  const { link } = await searchParams;
  return (
    <Page title="Sign in">
      <Card>
        {link === "expired" && (
          <p className="mb-4 text-sm text-red-700">
            That link has expired or was already used. Please request a new one. Links work once, for one hour.
          </p>
        )}
        {link === "other-device" && (
          <p className="mb-4 text-sm text-red-700">
            That link didn&apos;t work. Please open it on the same device and in the same browser you used to ask for
            it, or request a new one. Links work once, for one hour.
          </p>
        )}
        <ActionForm action={signIn} submitLabel="Sign in">
          <Field label="Email" name="email" type="email" autoComplete="email" required />
          <Field label="Password" name="password" type="password" autoComplete="current-password" required />
        </ActionForm>
        <p className="mt-4 space-x-4 text-sm">
          <TextLink href="/forgot-password">Forgot your password?</TextLink>
          <TextLink href="/signup">Create an account</TextLink>
        </p>
      </Card>
    </Page>
  );
}
