import { Card, Page } from "@/components/ui";
import { POLICY_VERSION } from "@/lib/forms";

// Placeholder until CLG's privacy policy and terms are finalised and
// reviewed by a lawyer. Bump POLICY_VERSION when the wording changes.
export default function PrivacyPage() {
  return (
    <Page title="Privacy policy and terms">
      <Card>
        <p className="mb-3 text-sm text-zinc-500">Draft version {POLICY_VERSION}. The full policy will be published before launch.</p>
        <ul className="list-disc space-y-2 pl-5 text-sm">
          <li>CLG collects only what it needs to provide tutoring and learning support.</li>
          <li>Your information is stored in Australia and protected with encryption.</li>
          <li>Emails from the app are sent by Resend, an email service based in the United States. It handles your email address and the short message (such as a session reminder), not your learning records.</li>
          <li>Tutors see only the students they currently teach. Parents see only their own children.</li>
          <li>You can ask to see, correct or delete your information at any time.</li>
          <li>Learning records are deleted two years after a student&apos;s last lesson or enrolment.</li>
          <li>CLG does not sell your information or use it for advertising.</li>
        </ul>
      </Card>
    </Page>
  );
}
