// Summary: the sign-up form, for a parent or a student aged 16 or over.
//
"use client"; // Runs in the browser, so the form can change as choices are made.

import { useState } from "react"; // Lets the form remember who is signing up.
import { DOB_HINT } from "@/lib/students"; // The hint shown under date of birth.
import { signUp } from "@/app/actions/auth"; // The server action that creates the account.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { StateSelect } from "@/components/state-select"; // A list to pick the state.
import { Field, TextLink } from "@/components/ui"; // A labelled input box and the link style.
import { YearLevelSelect } from "@/components/year-level-select"; // A list to pick the year level.

// Shows the sign-up form; students see extra boxes.
export function SignupForm() {
  const [kind, setKind] = useState<"parent" | "learner">("parent"); // Who is signing up (parent to start).
  return ( // Shows:
    <ActionForm action={signUp} submitLabel="Create account">{/* a form that creates the account: */}
      <fieldset className="space-y-2">{/* a group of choices: */}
        <legend className="text-sm font-medium">I am signing up as</legend>{/* its heading, */}
        <label className="flex items-center gap-2 text-sm">{/* a line holding: */}
          <input type="radio" name="signup_as" value="parent" checked={kind === "parent"} onChange={() => setKind("parent")} />{/* a round button for "parent", */}
          A parent or carer (you can add your children next){/* and its words. */}
        </label>{/* End of the line. */}
        <label className="flex items-center gap-2 text-sm">{/* A line holding: */}
          <input type="radio" name="signup_as" value="learner" checked={kind === "learner"} onChange={() => setKind("learner")} />{/* a round button for "student", */}
          A student aged 16 or over, or an adult learner{/* and its words. */}
        </label>{/* End of the line. */}
      </fieldset>{/* End of the group. */}
      <Field label="Full name" name="full_name" autoComplete="name" required maxLength={200} />{/* Full name, */}
      <Field label="Email" name="email" type="email" autoComplete="email" required />{/* email, */}
      <Field // a password box:
        label="Password" // its label,
        name="password" // its field name,
        type="password" // hidden as typed,
        autoComplete="new-password" // lets password managers suggest one,
        required // that must be filled in,
        minLength={12} // at least 12 characters,
        hint="At least 12 characters, with upper and lowercase letters and a number." // and a hint about the rules.
      />{/* (end of the box) */}
      {kind === "learner" && ( // For students:
        <>{/* (a group:) */}
          <Field label="Date of birth" name="date_of_birth" type="date" required hint={DOB_HINT} />{/* date of birth, */}
          <StateSelect label="State you live in" />{/* state, */}
          <YearLevelSelect label="Year level or stage of study" />{/* year level, */}
          <Field // a box for their school:
            label="School, university or TAFE" // its label,
            name="school" // its field name,
            required // that must be filled in,
            maxLength={200} // up to 200 characters,
            hint='If you are not studying at the moment, write "Not studying".' // and a hint for people not studying.
          />{/* (end of the box) */}
        </> // (end of the group)
      )}{/* End of the student part. */}
      <label className="flex items-start gap-2 text-sm">{/* A line holding: */}
        <input type="checkbox" name="accept" required className="mt-1" />{/* a tick box that must be ticked, */}
        <span>{/* (the words:) */}
          I agree to CLG&apos;s <TextLink href="/privacy">privacy policy and terms</TextLink>.{/* agreeing to the privacy policy and terms, with a link. */}
        </span>{/* (end of the words) */}
      </label>{/* End of the line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SignupForm.
