import { redirect } from "next/navigation";
import { agreeToPolicies } from "@/app/actions/family-setup";
import { agreeForChildren } from "@/app/actions/privacy";
import { ActionForm } from "@/components/action-form";
import { Card, Page, TextLink } from "@/components/ui";
import { requireViewer } from "@/lib/auth";
import { childrenNeedingConsent } from "@/lib/consent";
import { POLICY_VERSION } from "@/lib/forms";
import { plainDate } from "@/lib/privacy";
import { createClient } from "@/lib/supabase/server";

// Families agree to the privacy policy and terms here before using the app
// (if CLG set up their account), and parents agree for each child once a
// year. Each agreement is its own box: privacy law says consent must not be
// bundled or pre-ticked.
export default async function AgreePage() {
  const viewer = await requireViewer();
  const supabase = await createClient();
  const { data: agreed } = await supabase.rpc("my_policy_consent", { p_version: POLICY_VERSION });
  const children = viewer.roles.includes("parent") ? await childrenNeedingConsent() : [];
  if (agreed === true && children.length === 0) redirect("/dashboard");

  if (agreed !== true) {
    return (
      <Page title="Welcome to CLG">
        <Card>
          <p className="mb-4 text-sm">
            Before you start, please read how CLG looks after your information and the terms of our support.
          </p>
          <ActionForm action={agreeToPolicies} submitLabel="Agree and continue">
            <label className="flex items-start gap-2 text-sm">
              <input type="checkbox" name="accept" required className="mt-1" />
              <span>
                I agree to CLG&apos;s <TextLink href="/privacy">privacy policy and terms</TextLink>.
              </span>
            </label>
            <label className="flex items-start gap-2 text-sm">
              <input type="checkbox" name="marketing" className="mt-1" />
              <span>Send me CLG news and offers by email. (Optional. You can change this any time in Your privacy.)</span>
            </label>
          </ActionForm>
        </Card>
      </Page>
    );
  }

  const renewing = children.some((c) => c.last_given);
  return (
    <Page title={renewing ? "Your yearly check" : "Your consent for your children"}>
      <Card>
        <p className="mb-4 text-sm">
          CLG needs your agreement, as parent or guardian, to keep and use each child&apos;s details for their learning
          support. We ask once a year so you stay in control. Read what we hold and why in the{" "}
          <TextLink href="/privacy">privacy policy</TextLink>. You can download it all or withdraw any time from{" "}
          <TextLink href="/my-privacy">Your privacy</TextLink>.
        </p>
        <ActionForm action={agreeForChildren} submitLabel="Agree and continue">
          {children.map((c) => (
            <label key={c.student_id} className="flex items-start gap-2 text-sm">
              <input type="checkbox" name={`child_${c.student_id}`} required className="mt-1" />
              <span>
                I am <strong>{c.full_name}</strong>&apos;s parent or legal guardian and I agree.
                {c.last_given && <span className="text-zinc-500"> (Last agreed {plainDate(c.last_given)}.)</span>}
              </span>
            </label>
          ))}
        </ActionForm>
        <p className="mt-4 text-xs text-zinc-500">
          If you don&apos;t want to agree, please <TextLink href="/my-privacy">send CLG a request</TextLink> and we&apos;ll
          talk about what happens next.
        </p>
      </Card>
    </Page>
  );
}
