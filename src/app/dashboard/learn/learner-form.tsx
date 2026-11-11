// Summary: the form an adult fills in to add their own student profile.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { addMeAsLearner } from "@/app/actions/learner"; // The server action that adds the profile.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { StateSelect } from "@/components/state-select"; // A list to pick the state.
import { SubjectPicker } from "@/components/subject-picker"; // Boxes to pick subjects.
import { Field, TextArea } from "@/components/ui"; // A labelled input box and a larger text box.
import { YearLevelSelect } from "@/components/year-level-select"; // A list to pick the year level.
import { DOB_HINT } from "@/lib/students"; // The hint shown under date of birth.

// Shows the student profile form.
export function LearnerForm() {
  return ( // Shows:
    <ActionForm action={addMeAsLearner} submitLabel="Add my student profile">{/* a form that adds the profile: */}
      <Field label="Your date of birth" name="date_of_birth" type="date" required hint={DOB_HINT} />{/* date of birth (must be filled in), */}
      <StateSelect label="State you live in" />{/* the state, */}
      <YearLevelSelect label="Year level or stage of study" />{/* the year level or stage, */}
      <Field label="School, university or TAFE" name="school" required maxLength={200} />{/* the school, university or TAFE (must be filled in), */}
      <SubjectPicker />{/* the subjects, */}
      <TextArea // a text box:
        label="What would you like CLG's support to achieve? (optional)" // asking what they'd like to achieve,
        name="goals" // its field name,
        rows={3} // three lines tall,
        maxLength={4000} // up to 4,000 characters.
      />{/* (end of the text box) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LearnerForm.
