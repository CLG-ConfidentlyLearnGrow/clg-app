// Summary: the "one more step" page that email links open, with one button to carry on.
//
import { continueEmailLink } from "@/app/actions/auth"; // The server action that uses the email link.
import { Card, Page } from "@/components/ui"; // The card and page frame.
import { SubmitOnce } from "@/components/submit-once"; // A button that can only be pressed once.
import { isEmailLinkType } from "@/lib/email-links"; // Checks the link's kind is one we know.
import { safeNextPath } from "@/lib/forms"; // Makes sure the "next page" is inside the app.
import { redirect } from "next/navigation"; // Sends the person to another page.

// Email links land here and wait for a button press. Email security scanners
// open links automatically; without this step they would use the link up
// before the person clicks it.
export default async function ContinuePage({ searchParams }: PageProps<"/auth/continue">) {
  const { token_hash, type, next } = await searchParams; // Reads the link's code, kind and next page from the address.
  if (typeof token_hash !== "string" || !isEmailLinkType(type)) redirect("/login?link=expired"); // Missing code or unknown kind: sends them to sign in with a note.

  const label = type === "recovery" ? "Reset my password" : type === "invite" ? "Accept invitation" : "Continue"; // The button's words: reset, accept, or continue.
  return ( // Shows:
    <Page title="One more step">{/* a page titled "One more step", */}
      <Card>{/* with a card: */}
        <p className="mb-4 text-sm">Press the button once to carry on. It can take a few seconds.</p>{/* telling them to press the button once, */}
        <form action={continueEmailLink}>{/* a form that uses the link: */}
          <input type="hidden" name="token_hash" value={token_hash} />{/* the link's code (hidden), */}
          <input type="hidden" name="type" value={type} />{/* the link's kind (hidden), */}
          <input type="hidden" name="next" value={safeNextPath(typeof next === "string" ? next : null)} />{/* the page to go to next, kept inside the app (hidden), */}
          <SubmitOnce label={label} />{/* and the button. */}
        </form>{/* End of the form. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of ContinuePage.
