// Summary: the page a staff invite link opens, where the person chooses a name and password.
//
import type { Metadata } from "next"; // The type for page details like the title.
import { joinAsStaff } from "@/app/actions/auth"; // The server action that creates the staff account.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Field, Page, TextLink } from "@/components/ui"; // The card, field, page frame and link styles.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Where a staff invite link opens. Opening it changes nothing (so email
// virus scanners that open links can't use it up). The person chooses their
// name and password, and joins as the role they were invited for.

// The link is secret, so don't pass it on to other websites.
export const metadata: Metadata = { title: "Join CLG", referrer: "no-referrer" }; // Page title, and don't share the address with other sites.

type InviteDetails = { email: string; role: "tutor" | "admin"; expires_at: string; status: "open" | "used" | "expired" }; // The invitation's details: email, role, expiry and whether it's open, used or expired.

// Shows the join form, or a note if the link doesn't work.
export default async function JoinPage({ searchParams }: PageProps<"/join">) {
  const { t } = await searchParams; // Reads the link's secret code from the address.
  const token = typeof t === "string" && /^[0-9a-f]{64}$/.test(t) ? t : null; // Keeps it only if it looks right (64 letters and numbers).

  let invite: InviteDetails | undefined; // The invitation's details (none until found).
  if (token) { // If there's a code:
    const supabase = await createClient(); // connects to the database,
    const { data } = await supabase.rpc("staff_invite_link_details", { p_token: token }); // looks up the invitation,
    invite = ((data ?? []) as InviteDetails[])[0]; // and takes the first match.
  } // End of the lookup.

  if (!token || !invite) { // No code or no invitation:
    return ( // shows:
      <Page title="Join CLG">{/* a page titled "Join CLG", */}
        <Card>{/* with a card: */}
          <p className="text-sm">{/* a line: */}
            This invitation link doesn&apos;t work. It may be incomplete, or CLG may have sent you a newer one. Please
            use the newest invitation email, or ask CLG for a new link.{/* saying the link doesn't work and what to do. */}
          </p>{/* End of the line. */}
          <p className="mt-4 text-sm">{/* A line: */}
            Already joined? <TextLink href="/login">Sign in</TextLink>{/* with a link to sign in. */}
          </p>{/* End of the line. */}
        </Card>{/* End of the card. */}
      </Page> // End of the page.
    ); // End of what's shown.
  } // End of that case.

  if (invite.status === "used") { // Already used:
    return ( // shows:
      <Page title="Join CLG">{/* a page titled "Join CLG", */}
        <Card>{/* with a card: */}
          <p className="text-sm">This invitation has already been used, so your account is set up.</p>{/* saying it's been used, */}
          <p className="mt-4 text-sm">{/* a line: */}
            <TextLink href="/login">Sign in</TextLink>{/* with a link to sign in. */}
          </p>{/* End of the line. */}
        </Card>{/* End of the card. */}
      </Page> // End of the page.
    ); // End of what's shown.
  } // End of that case.

  if (invite.status === "expired") { // Expired:
    return ( // shows:
      <Page title="Join CLG">{/* a page titled "Join CLG", */}
        <Card>{/* with a card: */}
          <p className="text-sm">{/* a line: */}
            This invitation has expired. Invitations work for 7 days. Please ask CLG to send you a new link.{/* saying it expired and to ask for a new one. */}
          </p>{/* End of the line. */}
        </Card>{/* End of the card. */}
      </Page> // End of the page.
    ); // End of what's shown.
  } // End of that case.

  const roleWords = invite.role === "admin" ? "an admin" : "a tutor"; // The role in words.
  return ( // Shows:
    <Page title={`Join CLG as ${roleWords}`}>{/* a page titled with the role, */}
      <Card>{/* with a card: */}
        <p className="mb-4 text-sm text-zinc-600">{/* a grey line: */}
          CLG has invited <strong>{invite.email}</strong> to join as {roleWords}. Choose your name and a password to
          finish. Next, you&apos;ll set up two-step login with an authenticator app.{/* who was invited, and what happens next, */}
          {invite.role === "tutor" && // for tutors:
            " Then add your checks (Working with Children Check, RRHAN-EC and first aid) on your dashboard. CLG confirms them before you're matched with students."}{/* also about adding their checks. */}
        </p>{/* End of the line. */}
        <ActionForm action={joinAsStaff} submitLabel="Join CLG">{/* A form that creates the account: */}
          <input type="hidden" name="t" value={token} />{/* the link's code (hidden), */}
          <Field label="Your full name" name="full_name" autoComplete="name" required maxLength={200} />{/* their full name, */}
          <Field // the password box:
            label="Password" // its label,
            name="password" // its field name,
            type="password" // hidden as typed,
            autoComplete="new-password" // lets password managers suggest one,
            required // that must be filled in,
            minLength={12} // at least 12 characters,
            hint="At least 12 characters, with a lowercase letter, an uppercase letter and a number." // and a hint about the rules.
          />{/* (end of the box) */}
        </ActionForm>{/* End of the form. */}
        <p className="mt-4 text-sm text-zinc-500">{/* A grey line: */}
          Not {invite.email}? Please don&apos;t use this link. It only works for the person it was sent to.{/* telling anyone else not to use the link. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of JoinPage.
