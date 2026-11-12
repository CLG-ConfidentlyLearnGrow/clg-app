// Summary: the page where someone asks for a password reset link.
//
import { requestPasswordReset } from "@/app/actions/auth"; // The server action that sends the reset email.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Field, Page, TextLink } from "@/components/ui"; // The card, field, page frame and link styles.

// Shows the reset form.
export default function ForgotPasswordPage() {
  return ( // Shows:
    <Page title="Reset your password">{/* a page titled "Reset your password", */}
      <Card>{/* with a card: */}
        <p className="mb-4 text-sm">Resetting your password also unlocks a locked account.</p>{/* a note that resetting also unlocks an account, */}
        <ActionForm action={requestPasswordReset} submitLabel="Send reset link">{/* a form that sends the reset link: */}
          <Field label="Email" name="email" type="email" autoComplete="email" required />{/* the email box. */}
        </ActionForm>{/* End of the form. */}
        <p className="mt-4 text-sm">{/* A small line: */}
          <TextLink href="/login">Back to sign in</TextLink>{/* with a link back to sign in. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of ForgotPasswordPage.
