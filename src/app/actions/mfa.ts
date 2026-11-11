// Summary: setting up and checking two-step login with an authenticator app.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { redirect } from "next/navigation"; // Lets the code send someone to another page.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

export type Enrollment = { factorId: string; qrCode: string; secret: string } | { error: string }; // Either the details to show (QR code and secret) or an error.

// Starts setting up an authenticator app. Clears any half-finished setup first.
export async function startEnrollment(): Promise<Enrollment> {
  await requireViewer(); // Makes sure someone is signed in.
  const supabase = await createClient(); // Connects to the database as the signed-in person.

  const factors = await supabase.auth.mfa.listFactors(); // Lists this person's two-step login methods.
  for (const factor of factors.data?.all ?? []) { // Goes through each one:
    if (factor.factor_type === "totp" && factor.status === "unverified") { // an authenticator setup that was never finished:
      await supabase.auth.mfa.unenroll({ factorId: factor.id }); // removes it, so it doesn't get in the way.
    } // End of that case.
  } // End of the loop.

  const { data, error } = await supabase.auth.mfa.enroll({ // Starts a new authenticator setup:
    factorType: "totp", // a time-based code app,
    friendlyName: `Authenticator ${new Date().toISOString().slice(0, 10)}`, // named with today's date so it's easy to recognise.
  }); // End of the request.
  if (error || !data) return { error: "We couldn't start two-step login setup. Please try again." }; // Failed: plain message.
  return { factorId: data.id, qrCode: data.totp.qr_code, secret: data.totp.secret }; // Hands back what the page needs to show.
} // End of startEnrollment.

// The rules for the code form:
const verifySchema = z.object({
  factorId: z.string().uuid(), // which setup (a proper id),
  code: z.string().trim().regex(/^\d{6}$/, "Enter the 6-digit code from your authenticator app."), // and a 6-digit code.
}); // End of the rules.

// Checks the 6-digit code to finish two-step login.
export async function verifyTwoStep(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = verifySchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.auth.mfa.challengeAndVerify({ // Asks Supabase to check the code:
    factorId: parsed.data.factorId, // for this setup,
    code: parsed.data.code, // with this code.
  }); // End of the check.
  if (error) return { error: "That code didn't work. Codes change every 30 seconds, so try the newest one." }; // Wrong code: explains codes change every 30 seconds.

  redirect("/dashboard"); // Worked: goes to the dashboard.
} // End of verifyTwoStep.
