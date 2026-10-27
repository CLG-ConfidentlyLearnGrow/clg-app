"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { requireViewer } from "@/lib/auth";
import { siteUrl, supabasePublishableKey, supabaseUrl } from "@/lib/env";
import { STATES } from "@/lib/checks";
import { YEAR_LEVELS } from "@/lib/students";
import { isEmailLinkType } from "@/lib/email-links";
import { POLICY_VERSION, safeNextPath, type FormState } from "@/lib/forms";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { createClient as createPlainClient } from "@supabase/supabase-js";

const LOCKED =
  "This account is locked for 30 minutes after too many attempts. Reset your password to unlock it now, or contact CLG.";

const email = z.email("Enter a valid email address.").trim().toLowerCase();
const newPassword = z
  .string()
  .min(12, "Use at least 12 characters.")
  .max(128, "Use 128 characters or fewer.")
  .regex(/[a-z]/, "Include a lowercase letter.")
  .regex(/[A-Z]/, "Include an uppercase letter.")
  .regex(/[0-9]/, "Include a number.");

function yearsAgo(years: number): Date {
  const d = new Date();
  d.setFullYear(d.getFullYear() - years);
  return d;
}

const signUpSchema = z
  .object({
    signup_as: z.enum(["parent", "learner"]),
    full_name: z.string().trim().min(1, "Enter your name.").max(200),
    email,
    password: newPassword,
    date_of_birth: z.string().optional(),
    state: z.enum(STATES).optional(),
    year_level: z.enum(YEAR_LEVELS).optional(),
    school: z.string().trim().max(200).optional(),
    accept: z.literal("on", { message: "Please agree to the privacy policy and terms." }),
  })
  .refine(
    (v) =>
      v.signup_as !== "learner" ||
      (!!v.date_of_birth && new Date(v.date_of_birth) <= yearsAgo(16)),
    {
      message: "Students under 16 join through a parent's account. Ask a parent to sign up.",
      path: ["date_of_birth"],
    },
  )
  .refine((v) => v.signup_as !== "learner" || !!v.state, {
    message: "Choose the state you live in.",
    path: ["state"],
  })
  .refine((v) => v.signup_as !== "learner" || !!v.year_level, {
    message: "Choose your year level or stage of study. CLG uses it to match the right tutor.",
    path: ["year_level"],
  })
  .refine((v) => v.signup_as !== "learner" || !!v.school, {
    message: "Enter your school, university or TAFE.",
    path: ["school"],
  });

export async function signUp(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = signUpSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };
  const v = parsed.data;

  const supabase = await createClient();
  const { error } = await supabase.auth.signUp({
    email: v.email,
    password: v.password,
    options: {
      emailRedirectTo: `${siteUrl()}/auth/confirm?next=/dashboard`,
      data: {
        signup_as: v.signup_as,
        full_name: v.full_name,
        date_of_birth: v.signup_as === "learner" ? v.date_of_birth : undefined,
        state: v.signup_as === "learner" ? v.state : undefined,
        year_level: v.signup_as === "learner" ? v.year_level : undefined,
        school: v.signup_as === "learner" ? v.school : undefined,
        accepted_policies_version: POLICY_VERSION,
      },
    },
  });

  if (error) {
    if (error.code === "weak_password") {
      return { error: "That password is too easy to guess or has appeared in a data breach. Please choose another." };
    }
    // Includes emails with a pending staff invitation, which the database refuses.
    return {
      error:
        "We couldn't create that account. If CLG invited you, please use the link in your invitation email.",
    };
  }

  redirect("/check-email");
}

const signInSchema = z.object({ email, password: z.string().min(1).max(128) });

export async function signIn(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = signInSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: "Enter your email and password." };
  const { email: address, password } = parsed.data;

  const admin = createAdminClient();
  const lock = await admin.rpc("login_lock_status", { p_email: address });
  if (lock.data) return { error: LOCKED };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email: address, password });

  if (error) {
    const attempt = await admin.rpc("record_login_attempt", { p_email: address, p_succeeded: false });
    if (attempt.data) return { error: LOCKED };
    if (error.code === "email_not_confirmed") {
      return { error: "Please confirm your email address first, using the link we sent you." };
    }
    return { error: "That email and password don't match. Please try again." };
  }

  await admin.rpc("record_login_attempt", { p_email: address, p_succeeded: true });
  redirect("/dashboard");
}

export async function requestPasswordReset(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = email.safeParse(formData.get("email"));
  if (!parsed.success) return { error: "Enter a valid email address." };

  // The reset link must work on any device or browser, including when it
  // was asked for in the installed app and opens in a browser. So it carries
  // its own sign-in in the address (after the "#"), which EmailLinkCatcher
  // picks up, instead of needing a secret saved in the asking browser.
  // (Our own email templates, once set up in Supabase, use /auth/continue.)
  const supabase = createPlainClient(supabaseUrl(), supabasePublishableKey(), {
    auth: { flowType: "implicit", persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  await supabase.auth.resetPasswordForEmail(parsed.data, {
    redirectTo: `${siteUrl()}/login`,
  });

  // Same answer whether or not the account exists, so the form can't be
  // used to discover who has an account.
  return { message: "If that email has an account, a reset link is on its way. It works for one hour." };
}

const setPasswordSchema = z
  .object({ password: newPassword, confirm: z.string() })
  .refine((v) => v.password === v.confirm, { message: "The two passwords don't match.", path: ["confirm"] });

export async function setNewPassword(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireViewer();
  const parsed = setPasswordSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const supabase = await createClient();

  // Two-step login users confirm their code first (see the set-password page).
  const factorId = formData.get("factorId");
  if (typeof factorId === "string" && factorId) {
    const code = String(formData.get("code") ?? "").trim();
    if (!/^\d{6}$/.test(code)) return { error: "Enter the 6-digit code from your authenticator app." };
    const verified = await supabase.auth.mfa.challengeAndVerify({ factorId, code });
    if (verified.error) {
      return { error: "That code didn't work. Codes change every 30 seconds, so try the newest one." };
    }
  }

  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) {
    // The code shows in the Vercel logs, so we can see what went wrong.
    console.error("Password update failed:", error.code ?? error.name, error.message);
    if (error.code === "insufficient_aal") {
      return { error: "Please enter the 6-digit code from your authenticator app, then save again." };
    }
    if (error.code === "session_not_found" || error.code === "session_expired" || error.name === "AuthSessionMissingError") {
      return { error: "Your reset link has run out. Please request a new one." };
    }
    if (error.code === "weak_password") {
      return { error: "That password is too easy to guess or has appeared in a data breach. Please choose another." };
    }
    if (error.code === "same_password") {
      return { error: "Please choose a password you haven't used here before." };
    }
    return { error: "We couldn't update your password. Please request a new link and try again." };
  }

  await createAdminClient().rpc("clear_login_lock", { p_email: viewer.email });
  redirect("/dashboard");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}

// The button on /auth/continue: uses the one-time link from an email.
export async function continueEmailLink(formData: FormData) {
  const tokenHash = String(formData.get("token_hash") ?? "");
  const type = formData.get("type");
  const next = safeNextPath(String(formData.get("next") ?? ""));
  if (!tokenHash || !isEmailLinkType(type)) redirect("/login?link=expired");

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
  if (error) redirect("/login?link=expired");
  redirect(type === "recovery" || type === "invite" ? "/set-password" : next);
}

// Signs in from a reset or invitation link that carries its sign-in after
// the "#" in the address (see requestPasswordReset). The tokens are checked
// with Supabase before they are used.
export async function signInFromEmailLink(accessToken: string, refreshToken: string, type: string) {
  if (!accessToken || !refreshToken) redirect("/login?link=expired");
  const supabase = await createClient();
  const { error } = await supabase.auth.setSession({ access_token: accessToken, refresh_token: refreshToken });
  if (error) redirect("/login?link=expired");
  redirect(type === "recovery" || type === "invite" ? "/set-password" : "/dashboard");
}
