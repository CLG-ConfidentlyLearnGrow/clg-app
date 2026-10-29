import type { Metadata } from "next";
import { joinAsStaff } from "@/app/actions/auth";
import { ActionForm } from "@/components/action-form";
import { Card, Field, Page, TextLink } from "@/components/ui";
import { createClient } from "@/lib/supabase/server";

// Where a staff invite link opens. Opening it changes nothing (so email
// virus scanners that open links can't use it up). The person chooses their
// name and password, and joins as the role they were invited for.

// The link is secret, so don't pass it on to other websites.
export const metadata: Metadata = { title: "Join CLG", referrer: "no-referrer" };

type InviteDetails = { email: string; role: "tutor" | "admin"; expires_at: string; status: "open" | "used" | "expired" };

export default async function JoinPage({ searchParams }: PageProps<"/join">) {
  const { t } = await searchParams;
  const token = typeof t === "string" && /^[0-9a-f]{64}$/.test(t) ? t : null;

  let invite: InviteDetails | undefined;
  if (token) {
    const supabase = await createClient();
    const { data } = await supabase.rpc("staff_invite_link_details", { p_token: token });
    invite = ((data ?? []) as InviteDetails[])[0];
  }

  if (!token || !invite) {
    return (
      <Page title="Join CLG">
        <Card>
          <p className="text-sm">
            This invitation link doesn&apos;t work. It may be incomplete, or CLG may have sent you a newer one. Please
            use the newest invitation email, or ask CLG for a new link.
          </p>
          <p className="mt-4 text-sm">
            Already joined? <TextLink href="/login">Sign in</TextLink>
          </p>
        </Card>
      </Page>
    );
  }

  if (invite.status === "used") {
    return (
      <Page title="Join CLG">
        <Card>
          <p className="text-sm">This invitation has already been used, so your account is set up.</p>
          <p className="mt-4 text-sm">
            <TextLink href="/login">Sign in</TextLink>
          </p>
        </Card>
      </Page>
    );
  }

  if (invite.status === "expired") {
    return (
      <Page title="Join CLG">
        <Card>
          <p className="text-sm">
            This invitation has expired. Invitations work for 7 days. Please ask CLG to send you a new link.
          </p>
        </Card>
      </Page>
    );
  }

  const roleWords = invite.role === "admin" ? "an admin" : "a tutor";
  return (
    <Page title={`Join CLG as ${roleWords}`}>
      <Card>
        <p className="mb-4 text-sm text-zinc-600">
          CLG has invited <strong>{invite.email}</strong> to join as {roleWords}. Choose your name and a password to
          finish. Next, you&apos;ll set up two-step login with an authenticator app.
          {invite.role === "tutor" &&
            " Then add your checks (Working with Children Check, RRHAN-EC and first aid) on your dashboard. CLG confirms them before you're matched with students."}
        </p>
        <ActionForm action={joinAsStaff} submitLabel="Join CLG">
          <input type="hidden" name="t" value={token} />
          <Field label="Your full name" name="full_name" autoComplete="name" required maxLength={200} />
          <Field
            label="Password"
            name="password"
            type="password"
            autoComplete="new-password"
            required
            minLength={12}
            hint="At least 12 characters, with a lowercase letter, an uppercase letter and a number."
          />
        </ActionForm>
        <p className="mt-4 text-sm text-zinc-500">
          Not {invite.email}? Please don&apos;t use this link. It only works for the person it was sent to.
        </p>
      </Card>
    </Page>
  );
}
