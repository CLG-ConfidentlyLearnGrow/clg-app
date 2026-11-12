// Summary: the parent's form for adding a child, plus parts shared with other forms.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { addChild } from "@/app/actions/family"; // The server action that adds the child.
import { DOB_HINT } from "@/lib/students"; // The hint shown under date of birth.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { StateSelect } from "@/components/state-select"; // A list to pick the state.
import { SubjectPicker } from "@/components/subject-picker"; // Boxes to pick subjects.
import { Field, TextArea, TextLink } from "@/components/ui"; // The input box, larger text box and link style.
import { YearLevelSelect } from "@/components/year-level-select"; // A list to pick the year level.

// Shows the add-child form.
export function AddChildForm() {
  return ( // Shows:
    <ActionForm action={addChild} submitLabel="Add child">{/* a form that adds the child: */}
      <OneProfilePerChild />{/* the "one profile per child" warning, */}
      <Field label="Child's full name" name="full_name" required maxLength={200} />{/* the child's full name, */}
      <Field label="Date of birth" name="date_of_birth" type="date" required hint={DOB_HINT} />{/* date of birth, */}
      <StateSelect label="State your child lives in" />{/* state, */}
      <YearLevelSelect label="Year level at school this year" />{/* year level, */}
      <Field // a school box:
        label="School, university or TAFE" // its label,
        name="school" // its field name,
        required // that must be filled in,
        maxLength={200} // up to 200 characters,
        hint='If your child is home-schooled, write "Home schooled".' // and a hint for home-schooled children.
      />{/* (end of the box) */}
      <SubjectPicker />{/* subjects, */}
      <GoalFields />{/* goals and other details, */}
      <ParentalConsentBox />{/* and the consent tick box. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AddChildForm.

// Each child has one profile that every parent or guardian shares. A second
// parent adding the child again makes a double-up that CLG has to merge.
export function OneProfilePerChild() {
  return ( // Shows:
    <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-zinc-800">{/* an amber box: */}
      <p className="font-medium">Has another parent or guardian already added this child?</p>{/* the question in bold, */}
      <p className="mt-1">{/* a line: */}
        Please don&apos;t add them again. Each child has one profile that all their parents and guardians share. Instead,
        contact CLG and we&apos;ll link you to your child&apos;s existing profile.{/* asking them to contact CLG instead. */}
      </p>{/* End of the line. */}
    </div> // End of the box.
  ); // End of what's shown.
} // End of OneProfilePerChild.

// The end goal and anything else the family wants CLG to know.
export function GoalFields({
  goals = "", // the goals already written (blank to start),
  extraInfo = "", // the extra information already written,
  learningNeeds = "", // the learning needs already written,
  optional = false, // and whether the goals box is optional.
}: { // (their types:)
  goals?: string; // text,
  extraInfo?: string; // text,
  learningNeeds?: string; // text,
  optional?: boolean; // true or false.
}) { // (end of the settings)
  return ( // Shows:
    <>{/* (a group:) */}
      <TextArea // the goals box:
        label={optional ? "What would they like CLG's support to achieve? (optional)" : "What would you like CLG's support to achieve?"} // its label (marked optional if so),
        name="goals" // its field name,
        required={!optional} // required unless optional,
        rows={3} // three lines tall,
        maxLength={4000} // up to 4,000 characters,
        defaultValue={goals} // starting with what's already written,
        hint="For example: feel confident in maths before high school, or reach a B in Year 12 Chemistry." // and a hint with examples.
      />{/* (end of the box) */}
      <TextArea // The extra information box:
        label="Anything else you'd like us to know? (optional)" // its label,
        name="extra_info" // its field name,
        rows={3} // three lines tall,
        maxLength={2000} // up to 2,000 characters,
        defaultValue={extraInfo} // starting with what's already written,
        hint="For example, interests, how your child learns best, or times that suit. Please don't include medical details here; CLG will ask privately if needed." // and a hint (no medical details).
      />{/* (end of the box) */}
      <TextArea // The learning needs box:
        label="Learning needs (optional)" // its label,
        name="learning_needs" // its field name,
        rows={3} // three lines tall,
        maxLength={2000} // up to 2,000 characters,
        defaultValue={learningNeeds} // starting with what's already written,
        hint="Anything that affects how they learn, in your own words, for example dyslexia, ADHD, anxiety about tests, or adjustments their school makes. Only share what will help. Only CLG staff and their tutor see this." // and a hint about who sees it.
      />{/* (end of the box) */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of GoalFields.

// Not pre-ticked and not bundled with anything else, as privacy law expects
// for consent about a child. Asked again every 12 months.
export function ParentalConsentBox() {
  return ( // Shows:
    <label className="flex items-start gap-2 text-sm">{/* a line holding: */}
      <input type="checkbox" name="parental_consent" required className="mt-1" />{/* a tick box that must be ticked, */}
      <span>{/* (the words:) */}
        I am this child&apos;s parent or legal guardian. I agree to CLG keeping and using their details to provide
        learning support, as set out in the <TextLink href="/privacy">privacy policy</TextLink>. I can withdraw this
        at any time.{/* agreeing as parent or guardian, with a link to the privacy policy. */}
      </span>{/* (end of the words) */}
    </label> // End of the line.
  ); // End of what's shown.
} // End of ParentalConsentBox.
