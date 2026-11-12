// Summary: the sign-in page.
//
import { signIn } from "@/app/actions/auth"; // The server action that signs the person in.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Field, Page, TextLink } from "@/components/ui"; // The card, field, page frame and link styles.

// Shows the sign-in page, with a note when a link didn't work.
export default async function LoginPage({ searchParams }: PageProps<"/login">) {
  const { link } = await searchParams; // Reads the "link" note from the address.
  return ( // Shows:
    <Page title="Sign in">{/* a page titled "Sign in", */}
      <Card>{/* with a card: */}
        {link === "expired" && ( // if a link expired:
          <p className="mb-4 text-sm text-red-700">{/* a red line: */}
            That link has expired or was already used. Please request a new one. Links work once, for one hour.{/* saying it expired and to ask for a new one. */}
          </p> // End of the line.
        )}{/* End of that note. */}
        {link === "other-device" && ( // if a link was opened on another device:
          <p className="mb-4 text-sm text-red-700">{/* a red line: */}
            That link didn&apos;t work. Please request a new one with &quot;Forgot your password?&quot; below. Links
            work once, for one hour.{/* saying it didn't work and to ask for a new one. */}
          </p> // End of the line.
        )}{/* End of that note. */}
        <ActionForm action={signIn} submitLabel="Sign in">{/* A form that signs them in: */}
          <Field label="Email" name="email" type="email" autoComplete="email" required />{/* the email box, */}
          <Field label="Password" name="password" type="password" autoComplete="current-password" required />{/* the password box. */}
        </ActionForm>{/* End of the form. */}
        <p className="mt-4 space-x-4 text-sm">{/* A line of links: */}
          <TextLink href="/forgot-password">Forgot your password?</TextLink>{/* to reset a password, */}
          <TextLink href="/signup">Create an account</TextLink>{/* and to create an account. */}
        </p>{/* End of the line. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of LoginPage.
