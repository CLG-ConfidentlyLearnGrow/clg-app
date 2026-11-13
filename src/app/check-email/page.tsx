// Summary: the page shown after signing up, asking the person to confirm their email.
//
import { Card, Page, TextLink } from "@/components/ui"; // The page frame, card and link styles.

// Shows the "check your email" message.
export default function CheckEmailPage() {
  return ( // Shows:
    <Page title="Check your email">{/* a page titled "Check your email", */}
      <Card>{/* with a card: */}
        <p>We&apos;ve sent you a link to confirm your email address. Open it to finish creating your account.</p>{/* explaining the confirmation link, */}
        <p className="mt-3 text-sm">If this email already has a CLG account, we&apos;ve sent a link to set a new password and sign in instead. It can take a few minutes, so please check your junk or spam folder too.</p>{/* explaining what happens if they already have an account, and to check junk. */}
        <p className="mt-4 text-sm">{/* and a small line: */}
          <TextLink href="/login">Back to sign in</TextLink>{/* with a link back to sign in. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of CheckEmailPage.
