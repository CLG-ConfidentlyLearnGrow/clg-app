// Summary: signing up, joining as staff, signing in (with a lock after too
// many tries), password resets, setting a new password, signing out, and
// finishing sign-in from email links.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { redirect } from "next/navigation"; // Lets the code send someone to another page.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { siteUrl, supabasePublishableKey, supabaseUrl } from "@/lib/env"; // The app's web address, and the database's address and public key.
import { STATES } from "@/lib/checks"; // The list of Australian states.
import { YEAR_LEVELS } from "@/lib/students"; // The list of year levels.
import { isEmailLinkType } from "@/lib/email-links"; // Checks a link kind is one Supabase sends.
import { POLICY_VERSION, safeNextPath, type FormState } from "@/lib/forms"; // The policy version, the safe "go to" check, and the form reply shape.
import { createAdminClient } from "@/lib/supabase/admin"; // The all-powerful database helper (secret key).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { createClient as createPlainClient } from "@supabase/supabase-js"; // A plain Supabase connection (used for password reset emails).

const LOCKED = // The message shown when an account is locked:
  "This account is locked for 30 minutes after too many attempts. Reset your password to unlock it now, or contact CLG."; // (the words)

const email = z.email("Enter a valid email address.").trim().toLowerCase(); // The rule for an email address (tidied to lower case).
const newPassword = z // The rules for a new password:
  .string() // text,
  .min(12, "Use at least 12 characters.") // at least 12 letters,
  .max(128, "Use 128 characters or fewer.") // at most 128,
  .regex(/[a-z]/, "Include a lowercase letter.") // with a lower-case letter,
  .regex(/[A-Z]/, "Include an uppercase letter.") // an upper-case letter,
  .regex(/[0-9]/, "Include a number."); // and a number.

// The date this many years ago (to check ages).
function yearsAgo(years: number): Date {
  const d = new Date(); // Today.
  d.setFullYear(d.getFullYear() - years); // Moves back that many years.
  return d; // Hands it back.
} // End of yearsAgo.

// The rules for the sign-up form:
const signUpSchema = z
  .object({ // (the fields:)
    signup_as: z.enum(["parent", "learner"]), // signing up as a parent or a learner,
    full_name: z.string().trim().min(1, "Enter your name.").max(200), // name (required),
    email, // email,
    password: newPassword, // password (the new password rules),
    date_of_birth: z.string().optional(), // date of birth (learners),
    state: z.enum(STATES).optional(), // state (learners),
    year_level: z.enum(YEAR_LEVELS).optional(), // year level (learners),
    school: z.string().trim().max(200).optional(), // school (learners),
    accept: z.literal("on", { message: "Please agree to the privacy policy and terms." }), // the agree box must be ticked.
  }) // (end of the fields)
  .refine( // Learners must be 16 or over:
    (v) => // true when:
      v.signup_as !== "learner" || // not a learner,
      (!!v.date_of_birth && new Date(v.date_of_birth) <= yearsAgo(16)), // or the date of birth is at least 16 years ago.
    { // (the message and where it shows)
      message: "Students under 16 join through a parent's account. Ask a parent to sign up.", // the message,
      path: ["date_of_birth"], // shown by the date of birth field.
    }, // (end)
  ) // End of the age check.
  .refine((v) => v.signup_as !== "learner" || !!v.state, { // Learners need a state:
    message: "Choose the state you live in.", // the message,
    path: ["state"], // shown by the state field.
  }) // End of the state check.
  .refine((v) => v.signup_as !== "learner" || !!v.year_level, { // Learners need a year level:
    message: "Choose your year level or stage of study. CLG uses it to match the right tutor.", // the message,
    path: ["year_level"], // shown by the year level field.
  }) // End of the year level check.
  .refine((v) => v.signup_as !== "learner" || !!v.school, { // Learners need a school:
    message: "Enter your school, university or TAFE.", // the message,
    path: ["school"], // shown by the school field.
  }); // End of the rules.

// Makes a new parent or learner account.
export async function signUp(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = signUpSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.auth.signUp({ // Asks Supabase to make the account:
    email: v.email, // with this email,
    password: v.password, // and password,
    options: { // and these options:
      emailRedirectTo: `${siteUrl()}/auth/confirm?next=/dashboard`, // the link in the confirmation email goes to the dashboard,
      data: { // plus these details saved with the account:
        signup_as: v.signup_as, // parent or learner,
        full_name: v.full_name, // name,
        date_of_birth: v.signup_as === "learner" ? v.date_of_birth : undefined, // date of birth (learners only),
        state: v.signup_as === "learner" ? v.state : undefined, // state (learners only),
        year_level: v.signup_as === "learner" ? v.year_level : undefined, // year level (learners only),
        school: v.signup_as === "learner" ? v.school : undefined, // school (learners only),
        accepted_policies_version: POLICY_VERSION, // and the policy version they agreed to.
      }, // End of the details.
    }, // End of the options.
  }); // End of the request.

  if (error) { // It failed:
    if (error.code === "weak_password") { // password too weak or found in a breach:
      return { error: "That password is too easy to guess or has appeared in a data breach. Please choose another." }; // asks for another.
    } // End of that case.
    return { // Otherwise:
      error: // (the message)
        "We couldn't create that account. If CLG invited you to join as staff, please use the link in your invitation email.", // suggests invited staff use their invitation link.
    }; // End of the message.
  } // End of the failure case.

  // If this email already has a confirmed account, Supabase quietly makes
  // nothing and sends no email (so sign-up can't be used to find out who has
  // an account). It shows this by returning a user with no sign-in methods.
  // Without help the person waits for an email that never comes, so we send
  // them a password reset link instead. The page they see is the same either
  // way, which keeps who has an account private.
  if (data.user && data.user.identities?.length === 0) { // The email already has an account:
    await sendPasswordResetEmail(v.email); // sends them a link to set a new password and sign in.
  } // End of the existing-account case.

  redirect("/check-email"); // Worked: asks them to check their email.
} // End of signUp.

// Joining CLG as a tutor or admin through an invite link (/join). The link
// was only sent to the invited email, so using it proves the person owns
// that inbox: the account is made with the email already confirmed, and the
// database gives the invited role straight away. No approval step.
// The rules for the join form:
const joinSchema = z.object({
  t: z.string().regex(/^[0-9a-f]{64}$/, "This invitation link isn't complete. Please open it again from your email."), // the invitation's secret code (64 letters and numbers),
  full_name: z.string().trim().min(1, "Enter your name.").max(200), // name (required),
  password: newPassword, // password (the new password rules).
}); // End of the rules.

type InviteDetails = { email: string; role: "tutor" | "admin"; expires_at: string; status: "open" | "used" | "expired" }; // The invitation's details: email, role, expiry and status.

// Makes a tutor or admin account from an invitation link.
export async function joinAsStaff(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = joinSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.

  // Check the link again here: it may have been used or replaced since the
  // page was opened.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const details = await supabase.rpc("staff_invite_link_details", { p_token: v.t }); // Looks up the invitation.
  const invite = ((details.data ?? []) as InviteDetails[])[0]; // Its details (if found).
  if (details.error) return { error: "We couldn't check your invitation. Please try again." }; // Lookup failed: plain message.
  if (!invite) return { error: "This invitation link no longer works. A newer one may have been sent. Please ask CLG for a new link." }; // Not found: may have been replaced.
  if (invite.status === "used") return { error: "This invitation has already been used. Please sign in instead." }; // Already used: sign in instead.
  if (invite.status === "expired") return { error: "This invitation has expired. Please ask CLG to send a new link." }; // Expired: ask for a new link.

  const admin = createAdminClient(); // Connects with full access.
  const made = await admin.auth.admin.createUser({ // Makes the account with full access:
    email: invite.email, // the invited email,
    password: v.password, // the chosen password,
    email_confirm: true, // email already confirmed (the link proves it),
    user_metadata: { full_name: v.full_name }, // with their name.
  }); // End of making the account.
  if (made.error) { // It failed:
    console.error("Joining as staff failed:", made.error.code ?? made.error.name, made.error.message); // notes why in the server log,
    if (made.error.code === "weak_password") { // password too weak:
      return { error: "That password is too easy to guess or has appeared in a data breach. Please choose another." }; // asks for another.
    } // End of that case.
    if (made.error.code === "email_exists") { // Email already has an account:
      // If they once started signing up but never confirmed their email, that
      // half-made account blocked joining. The invite link proves they own
      // the inbox, so we finish that account instead: set the chosen password
      // and confirm the email. Confirming hands over the invitation's role
      // (the database does this whenever an email is first confirmed).
      const finished = await finishUnconfirmedAccount(invite.email, v.password, v.full_name); // Tries to finish the half-made account.
      if (finished) { // It worked:
        const again = await supabase.auth.signInWithPassword({ email: invite.email, password: v.password }); // signs them in,
        if (again.error) redirect("/login"); // (couldn't: goes to the login page)
        redirect("/mfa"); // and goes to set up two-step login.
      } // End of the finished case.
      return { // explains:
        error: // (the message)
          "This email already has a CLG account. Please sign in. If you never finished setting that account up, use \"Forgot your password?\" on the sign-in page, and your invitation is added when you do.", // sign in, or reset the password to finish setting up.
      }; // End of the message.
    } // End of that case.
    return { error: "We couldn't set up your account. Please try again, or ask CLG for a new link." }; // Anything else: plain message.
  } // End of the failure case.

  const signedIn = await supabase.auth.signInWithPassword({ email: invite.email, password: v.password }); // Signs them in.
  if (signedIn.error) redirect("/login"); // Couldn't: goes to the login page.
  // Staff must set up two-step login before they can see anything else.
  redirect("/mfa"); // Goes to set up two-step login.
} // End of joinAsStaff.

// Finishes an account that was started on the sign-up page but never
// confirmed: sets the password and name, and confirms the email. Returns
// false (changing nothing) if the account is already confirmed or can't be
// found, so a confirmed account can never be taken over this way.
async function finishUnconfirmedAccount(address: string, password: string, fullName: string): Promise<boolean> {
  const admin = createAdminClient(); // Connects with full access.
  const row = await admin.from("account_private").select("account_id").eq("email", address.toLowerCase()).maybeSingle(); // Finds the account id from the email.
  if (!row.data) return false; // Not found: nothing to finish.
  const user = await admin.auth.admin.getUserById(row.data.account_id as string); // Reads the sign-in account.
  if (user.error || !user.data.user || user.data.user.email_confirmed_at) return false; // Can't read it, or already confirmed: leave it alone.
  const updated = await admin.auth.admin.updateUserById(row.data.account_id as string, { // Finishes it:
    password, // with the chosen password,
    email_confirm: true, // the email confirmed (the invite link proves it),
    user_metadata: { ...user.data.user.user_metadata, full_name: fullName }, // and their name, keeping other saved details.
  }); // End of the update.
  if (updated.error) { // It failed:
    console.error("Finishing unconfirmed account failed:", updated.error.code ?? updated.error.name, updated.error.message); // notes why in the server log,
    return false; // and reports it didn't work.
  } // End of the failure case.
  return true; // It worked.
} // End of finishUnconfirmedAccount.

const signInSchema = z.object({ email, password: z.string().min(1).max(128) }); // The rules for signing in: email and password.

// Signs someone in, locking the account for 30 minutes after too many tries.
export async function signIn(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = signInSchema.safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: "Enter your email and password." }; // Problem: asks for both.
  const { email: address, password } = parsed.data; // The checked email and password.

  const admin = createAdminClient(); // Connects with full access.
  const lock = await admin.rpc("login_lock_status", { p_email: address }); // Checks whether this account is locked.
  if (lock.data) return { error: LOCKED }; // Locked: says so.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.auth.signInWithPassword({ email: address, password }); // Tries to sign in.

  if (error) { // Wrong details:
    const attempt = await admin.rpc("record_login_attempt", { p_email: address, p_succeeded: false }); // records the failed try (and finds out if that locked it),
    if (attempt.data) return { error: LOCKED }; // now locked: says so.
    if (error.code === "email_not_confirmed") { // Email not confirmed yet:
      return { error: "Please confirm your email address first, using the link we sent you." }; // asks them to confirm it first.
    } // End of that case.
    return { error: "That email and password don't match. Please try again." }; // Otherwise: plain message.
  } // End of the failure case.

  await admin.rpc("record_login_attempt", { p_email: address, p_succeeded: true }); // Records the successful sign-in (clears failed tries).
  redirect("/dashboard"); // Goes to the dashboard.
} // End of signIn.

// Asks Supabase to email a password reset link to this address. Used by the
// "Forgot your password?" form, and by sign-up when the email already has an
// account. Kept out of the exported actions so it can't be called directly.
async function sendPasswordResetEmail(address: string): Promise<void> {
  // The reset link must work on any device or browser, including when it
  // was asked for in the installed app and opens in a browser. So it carries
  // its own sign-in in the address (after the "#"), which EmailLinkCatcher
  // picks up, instead of needing a secret saved in the asking browser.
  // (Our own email templates, once set up in Supabase, use /auth/continue.)
  const supabase = createPlainClient(supabaseUrl(), supabasePublishableKey(), { // Makes a plain connection:
    auth: { flowType: "implicit", persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }, // that puts the sign-in in the link itself, and saves nothing here.
  }); // End of the connection.
  const { error } = await supabase.auth.resetPasswordForEmail(address, { // Asks Supabase to send the reset email:
    redirectTo: `${siteUrl()}/login`, // the link lands on the login page.
  }); // End of the request.
  if (error) console.error("Password reset email failed:", error.code ?? error.name, error.message); // Notes a failure in the server log (the person still sees the same message).
} // End of sendPasswordResetEmail.

// Sends a password reset email.
export async function requestPasswordReset(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = email.safeParse(formData.get("email")); // Checks the email.
  if (!parsed.success) return { error: "Enter a valid email address." }; // Problem: asks for a valid email.

  await sendPasswordResetEmail(parsed.data); // Asks Supabase to send the reset email.

  // Same answer whether or not the account exists, so the form can't be
  // used to discover who has an account.
  return { message: "If that email has an account, a reset link is on its way. It works for one hour." }; // Same message either way.
} // End of requestPasswordReset.

// The rules for setting a new password:
const setPasswordSchema = z
  .object({ password: newPassword, confirm: z.string() }) // the password (new password rules) and the repeat,
  .refine((v) => v.password === v.confirm, { message: "The two passwords don't match.", path: ["confirm"] }); // which must match.

// Saves a new password (after a reset link, or when signed in).
export async function setNewPassword(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const parsed = setPasswordSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database as the signed-in person.

  // Two-step login users confirm their code first (see the set-password page).
  const factorId = formData.get("factorId"); // The two-step login setup, if they have one.
  if (typeof factorId === "string" && factorId) { // If they have one:
    const code = String(formData.get("code") ?? "").trim(); // reads the code typed,
    if (!/^\d{6}$/.test(code)) return { error: "Enter the 6-digit code from your authenticator app." }; // must be 6 digits.
    const verified = await supabase.auth.mfa.challengeAndVerify({ factorId, code }); // Checks the code.
    if (verified.error) { // Wrong code:
      return { error: "That code didn't work. Codes change every 30 seconds, so try the newest one." }; // explains codes change every 30 seconds.
    } // End of that case.
  } // End of the two-step check.

  const { error } = await supabase.auth.updateUser({ password: parsed.data.password }); // Saves the new password.
  if (error) { // It failed:
    // The code shows in the Vercel logs, so we can see what went wrong.
    console.error("Password update failed:", error.code ?? error.name, error.message); // notes why in the server log,
    if (error.code === "insufficient_aal") { // two-step code needed:
      return { error: "Please enter the 6-digit code from your authenticator app, then save again." }; // asks for it.
    } // End of that case.
    if (error.code === "session_not_found" || error.code === "session_expired" || error.name === "AuthSessionMissingError") { // The reset link ran out:
      return { error: "Your reset link has run out. Please request a new one." }; // asks for a new one.
    } // End of that case.
    if (error.code === "weak_password") { // Password too weak:
      return { error: "That password is too easy to guess or has appeared in a data breach. Please choose another." }; // asks for another.
    } // End of that case.
    if (error.code === "same_password") { // Same as before:
      return { error: "Please choose a password you haven't used here before." }; // asks for a different one.
    } // End of that case.
    return { error: "We couldn't update your password. Please request a new link and try again." }; // Anything else: plain message.
  } // End of the failure case.

  await createAdminClient().rpc("clear_login_lock", { p_email: viewer.email }); // Unlocks the account in case it was locked.
  redirect("/dashboard"); // Goes to the dashboard.
} // End of setNewPassword.

// Signs the person out.
export async function signOut() {
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.auth.signOut(); // Signs out (clears the login cookies).
  redirect("/"); // Goes to the home page.
} // End of signOut.

// The button on /auth/continue: uses the one-time link from an email.
export async function continueEmailLink(formData: FormData) {
  const tokenHash = String(formData.get("token_hash") ?? ""); // The one-time code from the email.
  const type = formData.get("type"); // The kind of link.
  const next = safeNextPath(String(formData.get("next") ?? "")); // Where to go afterwards (only pages on this site).
  if (!tokenHash || !isEmailLinkType(type)) redirect("/login?link=expired"); // Missing or unknown: back to login saying the link expired.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash }); // Asks Supabase to check the one-time code.
  if (error) { // It failed:
    // The code shows in the Vercel logs, so we can see why a link failed.
    console.error("Email link failed:", type, error.code ?? error.name, error.message); // notes why in the server log,
    redirect("/login?link=expired"); // and goes back to login saying the link expired.
  } // End of the failure case.
  redirect(type === "recovery" || type === "invite" ? "/set-password" : next); // Reset and invite links go to choose a password; others go on.
} // End of continueEmailLink.

// Signs in from a reset or invitation link that carries its sign-in after
// the "#" in the address (see requestPasswordReset). The tokens are checked
// with Supabase before they are used.
export async function signInFromEmailLink(accessToken: string, refreshToken: string, type: string) {
  if (!accessToken || !refreshToken) redirect("/login?link=expired"); // Missing passes: back to login saying the link expired.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.auth.setSession({ access_token: accessToken, refresh_token: refreshToken }); // Signs in with the passes (Supabase checks them).
  if (error) redirect("/login?link=expired"); // Failed: back to login saying the link expired.
  redirect(type === "recovery" || type === "invite" ? "/set-password" : "/dashboard"); // Reset and invite links go to choose a password; others to the dashboard.
} // End of signInFromEmailLink.
