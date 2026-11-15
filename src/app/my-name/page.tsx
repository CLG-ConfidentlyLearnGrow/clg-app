// Summary: the "Your name" page, where anyone signed in sets or changes the
// first and last name that CLG shows to colleagues and families. Tutors and
// admins who haven't given one yet are sent here before their dashboard.
// See docs/features/staff-names.md.
//
import type { Metadata } from "next"; // The type for page details like the title.
import { setMyName } from "@/app/actions/names"; // The server action that saves the name.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Field, Page, TextLink } from "@/components/ui"; // The card, field, page frame and link styles.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { safeNextPath } from "@/lib/forms"; // Keeps "go to" addresses on this site.
import { readMyNameParts } from "@/lib/staff-name"; // Reads their first and last name.

export const metadata: Metadata = { title: "Your name" }; // The browser tab title.

// Shows the name form, filled in with what's saved (or a best guess).
export default async function MyNamePage({ searchParams }: PageProps<"/my-name">) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const { next } = await searchParams; // Where to go once saved, if they were sent here.
  const nextPath = typeof next === "string" ? safeNextPath(next) : ""; // Keeps it only if it's a page on this site.
  const parts = await readMyNameParts(viewer); // Their saved first and last name (or nothing if it couldn't be read).
  const missing = !parts?.first || !parts?.last; // True if either name hasn't been given yet.
  const guess = guessFromFullName(viewer.fullName, viewer.email); // A best guess from the name they have now (never from their email).
  const first = parts?.first || guess.first; // The first name to show in the box.
  const last = parts?.last || guess.last; // The last name to show in the box.
  const isStaff = viewer.roles.includes("tutor") || viewer.roles.includes("admin"); // True for tutors and admins.

  return ( // Shows:
    <Page title="Your name">{/* a page titled "Your name", */}
      <Card>{/* with a card: */}
        {missing && isStaff ? ( // Staff who haven't given a name yet see:
          <p className="mb-4 text-sm text-zinc-700">{/* a line: */}
            Please enter your first and last name. This is how you&apos;ll appear to the CLG team and to families
            across the app.{/* asking for it, and why. */}
          </p> // End of the line.
        ) : ( // Everyone else sees:
          <p className="mb-4 text-sm text-zinc-700">{/* a line: */}
            This is how your name appears across the CLG app. You can change it at any time.{/* explaining the page. */}
          </p> // End of the line.
        )}{/* End of the choice. */}
        <ActionForm action={setMyName} submitLabel={nextPath ? "Save and continue" : "Save"}>{/* A form that saves the name: */}
          {nextPath && <input type="hidden" name="next" value={nextPath} />}{/* where to go next (hidden), if sent here, */}
          <Field label="First name" name="first_name" autoComplete="given-name" required maxLength={100} defaultValue={first} />{/* the first name box, */}
          <Field label="Last name" name="last_name" autoComplete="family-name" required maxLength={100} defaultValue={last} />{/* and the last name box. */}
        </ActionForm>{/* End of the form. */}
        {!nextPath && ( // When not on the way to somewhere:
          <p className="mt-4 text-sm">{/* a line: */}
            <TextLink href="/dashboard">Back to home</TextLink>{/* with a link home. */}
          </p> // End of the line.
        )}{/* End of that part. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of MyNamePage.

// Splits the name someone has now into a first and last name, to save them
// typing. Gives blanks if the name is just the start of their email (like
// "amy.swann2000"), since that isn't a real name.
function guessFromFullName(fullName: string, email: string): { first: string; last: string } {
  const name = fullName.trim(); // The name without spaces at the ends.
  const emailStart = email.split("@")[0]?.toLowerCase() ?? ""; // The part of their email before the @.
  if (!name || name.toLowerCase() === emailStart || !name.includes(" ")) return { first: "", last: "" }; // Not a real-looking name: leave the boxes empty.
  const space = name.indexOf(" "); // Where the first space is.
  return { first: name.slice(0, space), last: name.slice(space + 1).trim() }; // First word as first name, the rest as last name.
} // End of guessFromFullName.
