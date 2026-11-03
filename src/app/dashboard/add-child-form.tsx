"use client";

import { addChild } from "@/app/actions/family";
import { DOB_HINT } from "@/lib/students";
import { ActionForm } from "@/components/action-form";
import { StateSelect } from "@/components/state-select";
import { SubjectPicker } from "@/components/subject-picker";
import { Field, TextArea, TextLink } from "@/components/ui";
import { YearLevelSelect } from "@/components/year-level-select";

export function AddChildForm() {
  return (
    <ActionForm action={addChild} submitLabel="Add child">
      <Field label="Child's full name" name="full_name" required maxLength={200} />
      <Field label="Date of birth" name="date_of_birth" type="date" required hint={DOB_HINT} />
      <StateSelect label="State your child lives in" />
      <YearLevelSelect label="Year level at school this year" />
      <Field
        label="School"
        name="school"
        required
        maxLength={200}
        hint='If your child is home-schooled, write "Home schooled".'
      />
      <SubjectPicker />
      <GoalFields />
      <ParentalConsentBox />
    </ActionForm>
  );
}

// The end goal and anything else the family wants CLG to know.
export function GoalFields({
  goals = "",
  extraInfo = "",
  learningNeeds = "",
  optional = false,
}: {
  goals?: string;
  extraInfo?: string;
  learningNeeds?: string;
  optional?: boolean;
}) {
  return (
    <>
      <TextArea
        label={optional ? "What would they like CLG's support to achieve? (optional)" : "What would you like CLG's support to achieve?"}
        name="goals"
        required={!optional}
        rows={3}
        maxLength={4000}
        defaultValue={goals}
        hint="For example: feel confident in maths before high school, or reach a B in Year 12 Chemistry."
      />
      <TextArea
        label="Anything else you'd like us to know? (optional)"
        name="extra_info"
        rows={3}
        maxLength={2000}
        defaultValue={extraInfo}
        hint="For example, interests, how your child learns best, or times that suit. Please don't include medical details here; CLG will ask privately if needed."
      />
      <TextArea
        label="Learning needs (optional)"
        name="learning_needs"
        rows={3}
        maxLength={2000}
        defaultValue={learningNeeds}
        hint="Anything that affects how they learn, in your own words, for example dyslexia, ADHD, anxiety about tests, or adjustments their school makes. Only share what will help. Only CLG staff and their tutor see this."
      />
    </>
  );
}

// Not pre-ticked and not bundled with anything else, as privacy law expects
// for consent about a child. Asked again every 12 months.
export function ParentalConsentBox() {
  return (
    <label className="flex items-start gap-2 text-sm">
      <input type="checkbox" name="parental_consent" required className="mt-1" />
      <span>
        I am this child&apos;s parent or legal guardian. I agree to CLG keeping and using their details to provide
        learning support, as set out in the <TextLink href="/privacy">privacy policy</TextLink>. I can withdraw this
        at any time.
      </span>
    </label>
  );
}
