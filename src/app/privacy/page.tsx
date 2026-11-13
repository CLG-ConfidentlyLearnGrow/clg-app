// Summary: CLG's privacy policy page.
//
import { Card, Page, TextLink } from "@/components/ui"; // The card, page frame and link style.
import { POLICY_VERSION } from "@/lib/forms"; // The current version of the policies.
import { BackLink } from "@/components/back-link"; // A link back to the page the person came from.

// CLG's privacy notice, written to meet the notice rules of Australia (APP 1
// and APP 5), New Zealand (IPP 3 and 3A), the UK and EU (GDPR Articles 13
// and 14), Canada (PIPEDA, Quebec Law 25) and the US (COPPA). Draft until a
// lawyer has reviewed it. Bump POLICY_VERSION in src/lib/forms.ts when the
// wording changes: everyone is then asked to agree again.
// See docs/features/privacy-laws-baseline.md.

// CLG's privacy email, set in Vercel as NEXT_PUBLIC_PRIVACY_EMAIL.
const PRIVACY_EMAIL = process.env.NEXT_PUBLIC_PRIVACY_EMAIL?.trim() || null; // The privacy email, if set.

const SERVICES = [ // The outside services CLG uses, what each does and where:
  { name: "Supabase", does: "Stores the app's information and files", where: "Sydney, Australia" }, // Supabase,
  { name: "Vercel", does: "Runs the app's web pages", where: "Sydney, Australia (company in the United States)" }, // Vercel,
  { name: "Resend", does: "Sends the app's emails (your email address and the short message only)", where: "United States" }, // Resend,
  { name: "Stripe", does: "Takes payments (card or bank details go straight to Stripe; CLG never sees them)", where: "Australia and the United States" }, // Stripe,
  { name: "Xero", does: "Invoices and accounts (names, emails, invoice lines)", where: "Australia, New Zealand and the United States" }, // Xero,
  { name: "Microsoft 365", does: "Teams links for online sessions, and CLG's email", where: "Australia" }, // Microsoft 365.
]; // End of the list.

// Shows the privacy policy.
export default function PrivacyPage() {
  return ( // Shows:
    <Page title="Privacy policy" intro="How CLG Tutoring looks after information about you and your children.">{/* a page titled "Privacy policy": */}
      <p className="mb-4 text-sm">{/* a line: */}
        <BackLink />{/* with a back link. */}
      </p>{/* End of the line. */}
      <Card>{/* A card: */}
        <p className="text-sm text-zinc-500">{/* a grey line: */}
          Draft version {POLICY_VERSION}. This draft is being reviewed by a lawyer before CLG works with families outside
          Australia.{/* the draft version and lawyer review. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}

      <Card title="For children and teenagers">{/* A card for children and teenagers: */}
        <ul className="list-disc space-y-2 pl-5 text-sm">{/* a bulleted list: */}
          <li>CLG keeps your name, school, year level and notes about your learning, so your tutor can help you.</li>{/* what CLG keeps, */}
          <li>Your parent or carer usually gives us this information and agrees for you. We ask them again every year.</li>{/* who gives it, */}
          <li>Only you, your parent or carer, your tutor and a few CLG staff can see it.</li>{/* who can see it, */}
          <li>We never sell it, never use it for ads and never share it to make money.</li>{/* what CLG never does, */}
          <li>You can ask us to show you, fix or delete it. Ask your parent or carer, or email us.</li>{/* how to ask about it, */}
          <li>If something worries you, tell a parent, a teacher or CLG. You can also call Kids Helpline on 1800 55 1800.</li>{/* and where to get help. */}
        </ul>{/* End of the list. */}
      </Card>{/* End of the card. */}

      <Card title="Who we are and how to reach us">{/* A card on who CLG is: */}
        <p className="text-sm">{/* a line: */}
          CLG Tutoring (Confidently Learn Grow), South Australia. CLG&apos;s privacy officer is the owner, Carla. Contact
          her through <TextLink href="/my-privacy">Your privacy</TextLink> in the app{/* how to contact the privacy officer, */}
          {PRIVACY_EMAIL ? ( // if there's a privacy email:
            <>{/* (a group:) */}
              , or by email at <a href={`mailto:${PRIVACY_EMAIL}`} className="underline">{PRIVACY_EMAIL}</a>{/* the email address as a link, */}
            </> // (end of the group)
          ) : null}{/* otherwise nothing. */}
          . CLG follows the Australian Privacy Act in full, even though small businesses can be exempt.{/* and that CLG follows the Privacy Act in full. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}

      <Card title="What we collect, and why">{/* A card on what's collected and why: */}
        <ul className="list-disc space-y-2 pl-5 text-sm">{/* a bulleted list: */}
          <li>{/* point: */}
            <strong>Parents and adult learners:</strong> name, email, phone, address for in-person sessions, payment
            arrangements and invoices. To provide and bill for support.{/* parents and adult learners. */}
          </li>{/* (end of point) */}
          <li>{/* Point: */}
            <strong>Students:</strong> name, date of birth, state, school, year level, subjects, goals, session notes,
            progress and work samples, and any learning needs you choose to share. To match a suitable tutor and teach well.{/* students. */}
          </li>{/* (end of point) */}
          <li>{/* Point: */}
            <strong>Tutors and staff:</strong> contact details, child safety checks and their expiry dates, subjects,
            availability, pay rates and hours. To meet child safety law and pay staff.{/* tutors and staff. */}
          </li>{/* (end of point) */}
          <li>{/* Point: */}
            <strong>Security records:</strong> sign-in times, failed sign-ins and an activity log of who changed what (not
            the content). To keep accounts safe and investigate problems.{/* security records. */}
          </li>{/* (end of point) */}
          <li>{/* Point: */}
            <strong>Location:</strong> only tutors, only when signing on to an in-person session, asked each time. Only the
            result (at the session or not) is kept. Students&apos; location is never tracked.{/* location. */}
          </li>{/* (end of point) */}
        </ul>{/* End of the list. */}
        <p className="mt-3 text-sm">{/* A line: */}
          The legal reasons: to carry out our agreement with you, to meet legal duties (such as child safety, tax and pay
          law), and your consent (for children&apos;s information and for news emails). Where a parent gives us a
          child&apos;s information, we tell the child through this notice and through their parent.{/* the legal reasons, and how children are told. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}

      <Card title="What we never do">{/* A card on what CLG never does: */}
        <ul className="list-disc space-y-2 pl-5 text-sm">{/* a bulleted list: */}
          <li>Sell or rent information, or use it for advertising or profiling.</li>{/* sell or advertise, */}
          <li>Send news or offers unless you turn them on in Your privacy. Session, invoice and safety messages always come.</li>{/* send news unless turned on, */}
          <li>Let tutors see students they don&apos;t teach, or parents see other families.</li>{/* show other people's children, */}
          <li>Let tutors and children message each other privately. Contact goes through CLG and the family.</li>{/* allow private tutor-child messages. */}
        </ul>{/* End of the list. */}
      </Card>{/* End of the card. */}

      <Card title="Decisions the app makes automatically">{/* A card on automatic decisions: */}
        <ul className="list-disc space-y-2 pl-5 text-sm">{/* a bulleted list: */}
          <li>{/* point: */}
            <strong>Pausing support when a payment is overdue.</strong> The app pauses a family&apos;s sessions when Stripe
            reports an overdue payment, and restarts them when it is paid. CLG staff can review and override a pause: ask
            through Your privacy or contact CLG.{/* pausing support when payment is overdue. */}
          </li>{/* (end of point) */}
          <li>{/* Point: */}
            <strong>Suggesting tutors.</strong> The app lists tutors who hold the right child safety checks, subjects and
            times. A CLG staff member always makes the final match.{/* suggesting tutors. */}
          </li>{/* (end of point) */}
          <li>{/* Point (Carla, 13 Nov 2026): */}
            <strong>Checking writing for child safety.</strong> To keep children safe, the app checks what is written in it
            for words that may point to a risk to a child. A match is seen only by CLG&apos;s Child Safety Officer or
            deputy, who decide whether any action is needed. The app never acts on a match by itself.{/* checking writing for child safety. */}
          </li>{/* (end of point) */}
          <li>{/* Point: */}
            <strong>Deleting old records</strong> on the timetable below.{/* deleting old records. */}
          </li>{/* (end of point) */}
        </ul>{/* End of the list. */}
      </Card>{/* End of the card. */}

      <Card title="Where it is kept and who helps us">{/* A card on where it's kept: */}
        <p className="mb-3 text-sm">{/* a line: */}
          The app&apos;s information is stored in Sydney, Australia, encrypted while stored and while travelling. Some
          services CLG uses are based overseas. Each has a contract that requires it to protect the information.{/* stored in Sydney, encrypted, with overseas services under contract. */}
        </p>{/* End of the line. */}
        <ul className="list-disc space-y-1 pl-5 text-sm">{/* A bulleted list: */}
          {SERVICES.map((s) => ( // for each service:
            <li key={s.name}>{/* a list item: */}
              <strong>{s.name}</strong>: {s.does}. {s.where}.{/* its name, what it does, and where. */}
            </li> // (end of the item)
          ))}{/* End of the loop. */}
        </ul>{/* End of the list. */}
        <p className="mt-3 text-sm">{/* A line: */}
          For families in the UK or EU, information sent outside those places is protected by the services&apos; standard
          contract clauses. CLG will tell you before any new overseas service is used for your information.{/* protection for UK and EU families. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}

      <Card title="How long we keep it">{/* A card on how long it's kept: */}
        <ul className="list-disc space-y-1 pl-5 text-sm">{/* a bulleted list: */}
          <li>Student records: 2 years after the last session or enrolment, then deleted automatically.</li>{/* student records, */}
          <li>Accounts never used: 12 months after the last sign-in.</li>{/* unused accounts, */}
          <li>Invoices and payment records: 7 years (tax law).</li>{/* invoices, */}
          <li>Tutor records and child safety checks: 7 years after the tutor leaves.</li>{/* tutor records, */}
          <li>The activity log, privacy requests and breach records: 7 years.</li>{/* activity log and privacy records, */}
          <li>Failed sign-in records: 90 days.</li>{/* failed sign-ins. */}
        </ul>{/* End of the list. */}
      </Card>{/* End of the card. */}

      <Card title="Your rights">{/* A card on your rights: */}
        <p className="mb-3 text-sm">Wherever you live, you can:</p>{/* "Wherever you live, you can:", */}
        <ul className="list-disc space-y-1 pl-5 text-sm">{/* a bulleted list: */}
          <li>download your information, and your children&apos;s, at any time from Your privacy;</li>{/* download, */}
          <li>ask to see anything else we hold, and to fix anything that is wrong;</li>{/* see and fix, */}
          <li>ask us to delete information (some records must be kept by law, such as invoices);</li>{/* delete, */}
          <li>object to, or ask us to limit, a use of your information;</li>{/* object or limit, */}
          <li>withdraw a consent at any time (this does not undo what was done before);</li>{/* withdraw consent, */}
          <li>complain to CLG, and then to a privacy regulator.</li>{/* complain. */}
        </ul>{/* End of the list. */}
        <p className="mt-3 text-sm">{/* A line: */}
          Send any of these through <TextLink href="/my-privacy">Your privacy</TextLink>. CLG replies within 28 days. If a
          request is complex we may need longer; we will tell you why before the 28 days end.{/* how to send a request, and the 28-day reply time. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}

      <Card title="If something goes wrong">{/* A card on breaches: */}
        <p className="text-sm">{/* a line: */}
          If information is lost or seen by someone who shouldn&apos;t see it, CLG acts straight away to contain it, decides
          within 72 hr whether serious harm is likely, and if so tells the people affected and the privacy regulator.{/* what CLG does if information is lost or seen. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}

      <Card title="Complaints to a regulator">{/* A card on regulators: */}
        <ul className="list-disc space-y-1 pl-5 text-sm">{/* a bulleted list: */}
          <li>{/* point: */}
            Australia: <TextLink href="https://www.oaic.gov.au/privacy/privacy-complaints">Office of the Australian Information Commissioner</TextLink>{/* Australia's OAIC. */}
          </li>{/* (end of point) */}
          <li>{/* Point: */}
            New Zealand: <TextLink href="https://privacy.org.nz/your-rights/making-a-complaint/">Office of the Privacy Commissioner</TextLink>{/* New Zealand's commissioner. */}
          </li>{/* (end of point) */}
          <li>{/* Point: */}
            United Kingdom: <TextLink href="https://ico.org.uk/make-a-complaint/">Information Commissioner&apos;s Office</TextLink>{/* the UK's ICO. */}
          </li>{/* (end of point) */}
          <li>European Union: the data protection authority in your country</li>{/* The EU's authorities. */}
          <li>{/* Point: */}
            Canada: <TextLink href="https://www.priv.gc.ca/en/report-a-concern/">Office of the Privacy Commissioner of Canada</TextLink>{/* Canada's commissioner. */}
          </li>{/* (end of point) */}
          <li>{/* Point: */}
            United States: <TextLink href="https://reportfraud.ftc.gov/">Federal Trade Commission</TextLink> or your state attorney general{/* the US FTC or state attorney general. */}
          </li>{/* (end of point) */}
        </ul>{/* End of the list. */}
      </Card>{/* End of the card. */}
      <p className="mt-6 text-sm">{/* A line: */}
        <BackLink label="Back to where I was" />{/* with a back link. */}
      </p>{/* End of the line. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of PrivacyPage.
