"use client";

import { useState } from "react";
import { signUp } from "@/app/actions/auth";
import { ActionForm } from "@/components/action-form";
import { Field, TextLink } from "@/components/ui";

export function SignupForm() {
  const [kind, setKind] = useState<"parent" | "learner">("parent");
  return (
    <ActionForm action={signUp} submitLabel="Create account">
      <fieldset className="space-y-2">
        <legend className="text-sm font-medium">I am signing up as</legend>
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" name="signup_as" value="parent" checked={kind === "parent"} onChange={() => setKind("parent")} />
          A parent or carer (you can add your children next)
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" name="signup_as" value="learner" checked={kind === "learner"} onChange={() => setKind("learner")} />
          An adult learner (18 or over)
        </label>
      </fieldset>
      <Field label="Full name" name="full_name" autoComplete="name" required maxLength={200} />
      <Field label="Email" name="email" type="email" autoComplete="email" required />
      <Field
        label="Password"
        name="password"
        type="password"
        autoComplete="new-password"
        required
        minLength={12}
        hint="At least 12 characters, with upper and lowercase letters and a number."
      />
      {kind === "learner" && <Field label="Date of birth" name="date_of_birth" type="date" required />}
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" name="accept" required className="mt-1" />
        <span>
          I agree to CLG&apos;s <TextLink href="/privacy">privacy policy and terms</TextLink>.
        </span>
      </label>
    </ActionForm>
  );
}
