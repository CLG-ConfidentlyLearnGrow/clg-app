import { Card, Page, TextLink } from "@/components/ui";

export default function CheckEmailPage() {
  return (
    <Page title="Check your email">
      <Card>
        <p>We&apos;ve sent you a link to confirm your email address. Open it to finish creating your account.</p>
        <p className="mt-4 text-sm">
          <TextLink href="/login">Back to sign in</TextLink>
        </p>
      </Card>
    </Page>
  );
}
