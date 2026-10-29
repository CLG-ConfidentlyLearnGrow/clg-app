import { Card, Page, TextLink } from "@/components/ui";
import { SignupForm } from "./signup-form";

export default function SignupPage() {
  return (
    <Page title="Create an account">
      <Card>
        <p className="mb-4 text-sm text-zinc-600">
          Parents, and students aged 16 or over, can create an account here straight away. Students under 16 use CLG through a parent&apos;s account. Tutors and admins join using the invitation link CLG emails them.
        </p>
        <SignupForm />
        <p className="mt-4 text-sm">
          Already have an account? <TextLink href="/login">Sign in</TextLink>
        </p>
      </Card>
    </Page>
  );
}
