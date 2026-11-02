import { Card, Page, TextLink } from "@/components/ui";
import { POLICY_VERSION } from "@/lib/forms";
import { BackLink } from "@/components/back-link";

// CLG's privacy notice, written to meet the notice rules of Australia (APP 1
// and APP 5), New Zealand (IPP 3 and 3A), the UK and EU (GDPR Articles 13
// and 14), Canada (PIPEDA, Quebec Law 25) and the US (COPPA). Draft until a
// lawyer has reviewed it. Bump POLICY_VERSION in src/lib/forms.ts when the
// wording changes: everyone is then asked to agree again.
// See docs/features/privacy-laws-baseline.md.

// CLG's privacy email, set in Vercel as NEXT_PUBLIC_PRIVACY_EMAIL.
const PRIVACY_EMAIL = process.env.NEXT_PUBLIC_PRIVACY_EMAIL?.trim() || null;

const SERVICES = [
  { name: "Supabase", does: "Stores the app's information and files", where: "Sydney, Australia" },
  { name: "Vercel", does: "Runs the app's web pages", where: "Sydney, Australia (company in the United States)" },
  { name: "Resend", does: "Sends the app's emails (your email address and the short message only)", where: "United States" },
  { name: "Stripe", does: "Takes payments (card or bank details go straight to Stripe; CLG never sees them)", where: "Australia and the United States" },
  { name: "Xero", does: "Invoices and accounts (names, emails, invoice lines)", where: "Australia, New Zealand and the United States" },
  { name: "Microsoft 365", does: "Teams links for online sessions, and CLG's email", where: "Australia" },
];

export default function PrivacyPage() {
  return (
    <Page title="Privacy policy" intro="How CLG Tutoring looks after information about you and your children.">
      <p className="mb-4 text-sm">
        <BackLink />
      </p>
      <Card>
        <p className="text-sm text-zinc-500">
          Draft version {POLICY_VERSION}. This draft is being reviewed by a lawyer before CLG works with families outside
          Australia.
        </p>
      </Card>

      <Card title="For children and teenagers">
        <ul className="list-disc space-y-2 pl-5 text-sm">
          <li>CLG keeps your name, school, year level and notes about your learning, so your tutor can help you.</li>
          <li>Your parent or carer usually gives us this information and agrees for you. We ask them again every year.</li>
          <li>Only you, your parent or carer, your tutor and a few CLG staff can see it.</li>
          <li>We never sell it, never use it for ads and never share it to make money.</li>
          <li>You can ask us to show you, fix or delete it. Ask your parent or carer, or email us.</li>
          <li>If something worries you, tell a parent, a teacher or CLG. You can also call Kids Helpline on 1800 55 1800.</li>
        </ul>
      </Card>

      <Card title="Who we are and how to reach us">
        <p className="text-sm">
          CLG Tutoring (Confidently Learn Grow), South Australia. CLG&apos;s privacy officer is the owner, Carla. Contact
          her through <TextLink href="/my-privacy">Your privacy</TextLink> in the app
          {PRIVACY_EMAIL ? (
            <>
              , or by email at <a href={`mailto:${PRIVACY_EMAIL}`} className="underline">{PRIVACY_EMAIL}</a>
            </>
          ) : null}
          . CLG follows the Australian Privacy Act in full, even though small businesses can be exempt.
        </p>
      </Card>

      <Card title="What we collect, and why">
        <ul className="list-disc space-y-2 pl-5 text-sm">
          <li>
            <strong>Parents and adult learners:</strong> name, email, phone, address for in-person sessions, payment
            arrangements and invoices. To provide and bill for support.
          </li>
          <li>
            <strong>Students:</strong> name, date of birth, state, school, year level, subjects, goals, session notes,
            progress and work samples, and any learning needs you choose to share. To match a suitable tutor and teach well.
          </li>
          <li>
            <strong>Tutors and staff:</strong> contact details, child safety checks and their expiry dates, subjects,
            availability, pay rates and hours. To meet child safety law and pay staff.
          </li>
          <li>
            <strong>Security records:</strong> sign-in times, failed sign-ins and an activity log of who changed what (not
            the content). To keep accounts safe and investigate problems.
          </li>
          <li>
            <strong>Location:</strong> only tutors, only when signing on to an in-person session, asked each time. Only the
            result (at the session or not) is kept. Students&apos; location is never tracked.
          </li>
        </ul>
        <p className="mt-3 text-sm">
          The legal reasons: to carry out our agreement with you, to meet legal duties (such as child safety, tax and pay
          law), and your consent (for children&apos;s information and for news emails). Where a parent gives us a
          child&apos;s information, we tell the child through this notice and through their parent.
        </p>
      </Card>

      <Card title="What we never do">
        <ul className="list-disc space-y-2 pl-5 text-sm">
          <li>Sell or rent information, or use it for advertising or profiling.</li>
          <li>Send news or offers unless you turn them on in Your privacy. Session, invoice and safety messages always come.</li>
          <li>Let tutors see students they don&apos;t teach, or parents see other families.</li>
          <li>Let tutors and children message each other privately. Contact goes through CLG and the family.</li>
        </ul>
      </Card>

      <Card title="Decisions the app makes automatically">
        <ul className="list-disc space-y-2 pl-5 text-sm">
          <li>
            <strong>Pausing support when a payment is overdue.</strong> The app pauses a family&apos;s sessions when Stripe
            reports an overdue payment, and restarts them when it is paid. CLG staff can review and override a pause: ask
            through Your privacy or contact CLG.
          </li>
          <li>
            <strong>Suggesting tutors.</strong> The app lists tutors who hold the right child safety checks, subjects and
            times. A CLG staff member always makes the final match.
          </li>
          <li>
            <strong>Deleting old records</strong> on the timetable below.
          </li>
        </ul>
      </Card>

      <Card title="Where it is kept and who helps us">
        <p className="mb-3 text-sm">
          The app&apos;s information is stored in Sydney, Australia, encrypted while stored and while travelling. Some
          services CLG uses are based overseas. Each has a contract that requires it to protect the information.
        </p>
        <ul className="list-disc space-y-1 pl-5 text-sm">
          {SERVICES.map((s) => (
            <li key={s.name}>
              <strong>{s.name}</strong>: {s.does}. {s.where}.
            </li>
          ))}
        </ul>
        <p className="mt-3 text-sm">
          For families in the UK or EU, information sent outside those places is protected by the services&apos; standard
          contract clauses. CLG will tell you before any new overseas service is used for your information.
        </p>
      </Card>

      <Card title="How long we keep it">
        <ul className="list-disc space-y-1 pl-5 text-sm">
          <li>Student records: 2 years after the last session or enrolment, then deleted automatically.</li>
          <li>Accounts never used: 12 months after the last sign-in.</li>
          <li>Invoices and payment records: 7 years (tax law).</li>
          <li>Tutor records and child safety checks: 7 years after the tutor leaves.</li>
          <li>The activity log, privacy requests and breach records: 7 years.</li>
          <li>Failed sign-in records: 90 days.</li>
        </ul>
      </Card>

      <Card title="Your rights">
        <p className="mb-3 text-sm">Wherever you live, you can:</p>
        <ul className="list-disc space-y-1 pl-5 text-sm">
          <li>download your information, and your children&apos;s, at any time from Your privacy;</li>
          <li>ask to see anything else we hold, and to fix anything that is wrong;</li>
          <li>ask us to delete information (some records must be kept by law, such as invoices);</li>
          <li>object to, or ask us to limit, a use of your information;</li>
          <li>withdraw a consent at any time (this does not undo what was done before);</li>
          <li>complain to CLG, and then to a privacy regulator.</li>
        </ul>
        <p className="mt-3 text-sm">
          Send any of these through <TextLink href="/my-privacy">Your privacy</TextLink>. CLG replies within 28 days. If a
          request is complex we may need longer; we will tell you why before the 28 days end.
        </p>
      </Card>

      <Card title="If something goes wrong">
        <p className="text-sm">
          If information is lost or seen by someone who shouldn&apos;t see it, CLG acts straight away to contain it, decides
          within 72 hr whether serious harm is likely, and if so tells the people affected and the privacy regulator.
        </p>
      </Card>

      <Card title="Complaints to a regulator">
        <ul className="list-disc space-y-1 pl-5 text-sm">
          <li>
            Australia: <TextLink href="https://www.oaic.gov.au/privacy/privacy-complaints">Office of the Australian Information Commissioner</TextLink>
          </li>
          <li>
            New Zealand: <TextLink href="https://privacy.org.nz/your-rights/making-a-complaint/">Office of the Privacy Commissioner</TextLink>
          </li>
          <li>
            United Kingdom: <TextLink href="https://ico.org.uk/make-a-complaint/">Information Commissioner&apos;s Office</TextLink>
          </li>
          <li>European Union: the data protection authority in your country</li>
          <li>
            Canada: <TextLink href="https://www.priv.gc.ca/en/report-a-concern/">Office of the Privacy Commissioner of Canada</TextLink>
          </li>
          <li>
            United States: <TextLink href="https://reportfraud.ftc.gov/">Federal Trade Commission</TextLink> or your state attorney general
          </li>
        </ul>
      </Card>
      <p className="mt-6 text-sm">
        <BackLink label="Back to where I was" />
      </p>
    </Page>
  );
}
