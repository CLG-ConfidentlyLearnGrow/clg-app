// Summary: the two-step login page: enter a code, or set up an authenticator app.
//
import { verifyTwoStep } from "@/app/actions/mfa"; // The server action that checks the code.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Field, Page } from "@/components/ui"; // The card, field and page frame.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { EnrollTwoStep } from "./enroll"; // The set-up steps for a new authenticator app.

// Shows the code box, or the set-up steps if they have no app yet.
export default async function TwoStepPage() {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (viewer.aal === "aal2") redirect("/dashboard"); // Already done two-step login: goes to the dashboard.

  const supabase = await createClient(); // Connects to the database.
  const factors = await supabase.auth.mfa.listFactors(); // Lists their authenticator apps.
  const verified = (factors.data?.totp ?? []).find((f) => f.status === "verified"); // The first one that's been confirmed.

  return ( // Shows:
    <Page title="Two-step login">{/* a page titled "Two-step login", */}
      <Card>{/* with a card: */}
        {verified ? ( // if they have an app:
          <ActionForm action={verifyTwoStep} submitLabel="Continue">{/* a form that checks the code: */}
            <p className="text-sm">Enter the 6-digit code from your authenticator app.</p>{/* asking for the 6-digit code, */}
            <input type="hidden" name="factorId" value={verified.id} />{/* which app (hidden), */}
            <Field label="6-digit code" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="\d{6}" required />{/* the code box (6 digits only). */}
          </ActionForm> // End of the form.
        ) : ( // Otherwise:
          <EnrollTwoStep /> // the set-up steps.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of TwoStepPage.
