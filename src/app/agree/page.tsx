// Summary: the page where families agree to the privacy policy and terms, and to each child's consent.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { agreeToPolicies } from "@/app/actions/family-setup"; // The server action that records agreement to the policies.
import { agreeForChildren } from "@/app/actions/privacy"; // The server action that records consent for children.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Page, TextLink } from "@/components/ui"; // The card, page frame and link style.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { childrenNeedingConsent } from "@/lib/consent"; // Finds the children who need consent this year.
import { POLICY_VERSION } from "@/lib/forms"; // The current version of the policies.
import { plainDate } from "@/lib/privacy"; // Dates written in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Families agree to the privacy policy and terms here before using the app
// (if CLG set up their account), and parents agree for each child once a
// year. Each agreement is its own box: privacy law says consent must not be
// bundled or pre-ticked.
export default async function AgreePage() {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const supabase = await createClient(); // Connects to the database.
  const { data: agreed } = await supabase.rpc("my_policy_consent", { p_version: POLICY_VERSION }); // Asks whether they've agreed to this version.
  const children = viewer.roles.includes("parent") ? await childrenNeedingConsent() : []; // For parents, the children needing consent.
  if (agreed === true && children.length === 0) redirect("/dashboard"); // Nothing to agree to: goes to the dashboard.

  if (agreed !== true) { // Not agreed to the policies yet:
    return ( // shows:
      <Page title="Welcome to CLG">{/* a page titled "Welcome to CLG", */}
        <Card>{/* with a card: */}
          <p className="mb-4 text-sm">{/* a line: */}
            Before you start, please read how CLG looks after your information and the terms of our support.{/* asking them to read the policies. */}
          </p>{/* End of the line. */}
          <ActionForm action={agreeToPolicies} submitLabel="Agree and continue">{/* A form that records the agreement: */}
            <label className="flex items-start gap-2 text-sm">{/* a line holding: */}
              <input type="checkbox" name="accept" required className="mt-1" />{/* a tick box that must be ticked, */}
              <span>{/* (the words:) */}
                I agree to CLG&apos;s <TextLink href="/privacy">privacy policy and terms</TextLink>.{/* agreeing to the privacy policy and terms, with a link. */}
              </span>{/* (end of the words) */}
            </label>{/* End of the line. */}
            <label className="flex items-start gap-2 text-sm">{/* A line holding: */}
              <input type="checkbox" name="marketing" className="mt-1" />{/* an optional tick box for news and offers, */}
              <span>Send me CLG news and offers by email. (Optional. You can change this any time in Your privacy.)</span>{/* and its words. */}
            </label>{/* End of the line. */}
          </ActionForm>{/* End of the form. */}
        </Card>{/* End of the card. */}
      </Page> // End of the page.
    ); // End of what's shown.
  } // End of that case.

  const renewing = children.some((c) => c.last_given); // True if any child was agreed for before (so this is the yearly check).
  return ( // Shows:
    <Page title={renewing ? "Your yearly check" : "Your consent for your children"}>{/* a page, titled for a yearly check or first consent, */}
      <Card>{/* with a card: */}
        <p className="mb-4 text-sm">{/* a line: */}
          CLG needs your agreement, as parent or guardian, to keep and use each child&apos;s details for their learning
          support. We ask once a year so you stay in control. Read what we hold and why in the{" "}{/* why consent is needed, with a link to */}
          <TextLink href="/privacy">privacy policy</TextLink>. You can download it all or withdraw any time from{" "}{/* the privacy policy, and where to */}
          <TextLink href="/my-privacy">Your privacy</TextLink>.{/* download or withdraw. */}
        </p>{/* End of the line. */}
        <ActionForm action={agreeForChildren} submitLabel="Agree and continue">{/* A form that records consent: */}
          {children.map((c) => ( // for each child:
            <label key={c.student_id} className="flex items-start gap-2 text-sm">{/* a line holding: */}
              <input type="checkbox" name={`child_${c.student_id}`} required className="mt-1" />{/* a tick box for this child that must be ticked, */}
              <span>{/* (the words:) */}
                I am <strong>{c.full_name}</strong>&apos;s parent or legal guardian and I agree.{/* agreeing as their parent or guardian, */}
                {c.last_given && <span className="text-zinc-500"> (Last agreed {plainDate(c.last_given)}.)</span>}{/* and when they last agreed, if before. */}
              </span>{/* (end of the words) */}
            </label> // End of the line.
          ))}{/* End of the children loop. */}
        </ActionForm>{/* End of the form. */}
        <p className="mt-4 text-xs text-zinc-500">{/* A small grey note: */}
          If you don&apos;t want to agree, please <TextLink href="/my-privacy">send CLG a request</TextLink> and we&apos;ll
          talk about what happens next.{/* what to do if they don't want to agree. */}
        </p>{/* End of the note. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of AgreePage.
