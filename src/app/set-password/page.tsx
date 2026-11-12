// Summary: the page for choosing a new password (after a reset or an invitation).
//
import { setNewPassword } from "@/app/actions/auth"; // The server action that saves the password.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Field, Page } from "@/components/ui"; // The card, field and page frame.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Reached from a password reset or invitation link.
export default async function SetPasswordPage() {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.

  // People who use two-step login must enter their code before Supabase
  // lets them change their password. A reset link only signs them in with
  // the first step, so we ask for the code here.
  let factorId: string | null = null; // Their authenticator app's id, if a code is needed.
  if (viewer.aal !== "aal2") { // If they haven't done two-step login yet:
    const supabase = await createClient(); // connects to the database,
    const factors = await supabase.auth.mfa.listFactors(); // lists their authenticator apps,
    factorId = (factors.data?.totp ?? []).find((f) => f.status === "verified")?.id ?? null; // and takes the confirmed one's id (or none).
  } // End of that check.

  return ( // Shows:
    <Page title="Choose a password">{/* a page titled "Choose a password", */}
      <Card>{/* with a card: */}
        <ActionForm action={setNewPassword} submitLabel="Save password">{/* a form that saves the password: */}
          <Field // the new password box:
            label="New password" // its label,
            name="password" // its field name,
            type="password" // hidden as typed,
            autoComplete="new-password" // lets password managers suggest one,
            required // that must be filled in,
            minLength={12} // at least 12 characters,
            hint="At least 12 characters, with upper and lowercase letters and a number." // and a hint about the rules.
          />{/* (end of the box) */}
          <Field label="Type it again" name="confirm" type="password" autoComplete="new-password" required />{/* The box to type it again. */}
          {factorId && ( // If they have an authenticator app:
            <>{/* (a group:) */}
              <input type="hidden" name="factorId" value={factorId} />{/* which app (hidden), */}
              <Field // the code box:
                label="6-digit code from your authenticator app" // its label,
                name="code" // its field name,
                inputMode="numeric" // a number keypad on phones,
                autoComplete="one-time-code" // lets phones fill in the code,
                pattern="\d{6}" // 6 digits only,
                required // that must be filled in.
              />{/* (end of the box) */}
            </> // (end of the group)
          )}{/* End of the code part. */}
        </ActionForm>{/* End of the form. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of SetPasswordPage.
