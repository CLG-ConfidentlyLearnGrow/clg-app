import { Card, Page, TextLink } from "@/components/ui";

export default function Home() {
  return (
    <Page title="CLG Tutoring">
      <Card>
        <p className="mb-4">
          Tutoring, homework and learning support, all in one place for students, parents and tutors.
        </p>
        <p className="space-x-4">
          <TextLink href="/login">Sign in</TextLink>
          <TextLink href="/signup">Create an account</TextLink>
        </p>
      </Card>
    </Page>
  );
}
