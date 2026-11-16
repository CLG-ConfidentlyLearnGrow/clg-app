// Summary: the public "Apply to tutor" page. Anyone can open it without
// signing in. It explains CLG's child-safe commitment, what happens after
// applying and how applicants' information is handled, then shows the form.
// See docs/features/tutor-applications.md.
//
import type { Metadata } from "next"; // The type for the page's title settings.
import { connection } from "next/server"; // Makes the page build fresh for each visit (so the form's time stamp is current).
import { Card, Page, TextLink } from "@/components/ui"; // The page frame, cards and link style.
import { makeFormStamp } from "@/lib/apply-token"; // Makes the signed "form opened at" stamp (spam check).
import { ApplyForm } from "./apply-form"; // The form itself.

// The browser tab's title.
export const metadata: Metadata = { title: "Apply to tutor with CLG" };

// Shows the page.
export default async function ApplyPage() {
  await connection(); // Waits for a real visit, so the stamp below is made now (not when the app was built).
  const started = makeFormStamp(); // The signed "form opened at" stamp.
  return ( // Shows:
    <Page // the page:
      title="Apply to tutor with CLG" // its heading,
      intro="CLG Tutoring gives students in South Australia, and online, one-to-one support that builds confidence and skills. If you love helping young people learn, we'd like to hear from you." // and its introduction.
    >{/* (end of the page settings) */}
      <Card title="Our commitment to children's safety">{/* A card on child safety: */}
        <p className="text-sm text-zinc-700">{/* a paragraph: */}
          CLG is a child safe organisation. Keeping children and young people safe comes first in everything we do, including who we employ. Every application goes through the same checks: an interview, two referee checks, and a Working with Children Check verified with the state before anyone works with students.{/* the commitment, and the checks everyone goes through. */}
        </p>{/* End of the paragraph. */}
      </Card>{/* End of the card. */}
      <Card title="What happens next">{/* A card on the steps: */}
        <ol className="list-decimal space-y-1 pl-5 text-sm text-zinc-700">{/* numbered steps: */}
          <li>You send this form. It takes about 15 minutes.</li>{/* step 1, */}
          <li>We read every application and reply, usually within two weeks.</li>{/* step 2, */}
          <li>If you&apos;re shortlisted, we invite you to an interview and contact your two referees.</li>{/* step 3, */}
          <li>If you&apos;re successful, we email you a link to join the CLG app, where you add your checks and complete CLG&apos;s training.</li>{/* step 4. */}
        </ol>{/* End of the steps. */}
      </Card>{/* End of the card. */}
      <Card title="Your information">{/* A card with the collection notice (APP 5): */}
        <p className="text-sm text-zinc-700">{/* a paragraph: */}
          CLG Tutoring collects this information to decide whether to offer you a tutoring role, including contacting your referees and verifying your checks. Only CLG&apos;s owner and operations staff can see it. The app stores it in Sydney, Australia. If you aren&apos;t offered a role, we delete it 12 months after our decision. If you are, we keep it with your staff records. You can ask to see or correct it at any time. Read our <TextLink href="/privacy">privacy policy</TextLink> for more, including how to complain.{/* why it's collected, who sees it, where it's stored, how long, and the policy link. */}
        </p>{/* End of the paragraph. */}
      </Card>{/* End of the card. */}
      <Card title="Your application">{/* The form's card: */}
        <ApplyForm started={started} />{/* the form. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of ApplyPage.
