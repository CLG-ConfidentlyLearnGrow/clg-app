// Summary: the sign-up page for parents and students aged 16 or over.
//
import { Card, Page, TextLink } from "@/components/ui"; // The page frame, card and link styles.
import { SignupForm } from "./signup-form"; // The sign-up form itself.

// Shows the sign-up page.
export default function SignupPage() {
  return ( // Shows:
    <Page title="Create an account">{/* a page titled "Create an account", */}
      <Card>{/* with a card: */}
        <p className="mb-4 text-sm text-zinc-600">{/* a short note: */}
          Parents, and students aged 16 or over, can create an account here straight away. Students under 16 use CLG through a parent&apos;s account. Tutors and admins join using the invitation link CLG emails them.{/* who can sign up here, and how others join. */}
        </p>{/* End of the note. */}
        <SignupForm />{/* The sign-up form. */}
        <p className="mt-4 text-sm">{/* A small line: */}
          Already have an account? <TextLink href="/login">Sign in</TextLink>{/* with a link to sign in instead. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of SignupPage.
