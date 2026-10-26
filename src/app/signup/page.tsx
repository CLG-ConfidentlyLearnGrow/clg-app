import { Card, Page, TextLink } from "@/components/ui";
import { SignupForm } from "./signup-form";

export default function SignupPage() {
  return (
    <Page title="Create an account">
      <Card>
        <p className="mb-4 text-sm text-zinc-600 dark:text-zinc-400">
          Students under 18 use CLG through a parent&apos;s account. Tutors join by invitation from CLG.
        </p>
        <SignupForm />
        <p className="mt-4 text-sm">
          Already have an account? <TextLink href="/login">Sign in</TextLink>
        </p>
      </Card>
    </Page>
  );
}
