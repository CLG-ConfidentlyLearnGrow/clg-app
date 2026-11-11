// Summary: the admin form for setting up a family (or an adult student) and sending the login link.
//
"use client"; // Runs in the browser, so the form can change as choices are made.

import { useState } from "react"; // Lets the form remember who the account is for.
import { DOB_HINT } from "@/lib/students"; // The hint shown under date of birth.
import { setUpFamily } from "@/app/actions/family-setup"; // The server action that sets up the family.
import { GoalFields } from "@/app/dashboard/add-child-form"; // The goals, extra information and learning needs boxes.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { StateSelect } from "@/components/state-select"; // A list to pick the state.
import { SubjectPicker } from "@/components/subject-picker"; // Boxes to pick subjects.
import { Field } from "@/components/ui"; // A labelled input box.
import { YearLevelSelect } from "@/components/year-level-select"; // A list to pick the year level.

// An admin fills in a family's details for them and sends the login link.
export function FamilySetupForm() {
  const [who, setWho] = useState<"parent" | "learner">("parent"); // Who the account is for (parent to start).
  return ( // Shows:
    <ActionForm action={setUpFamily} submitLabel={who === "parent" ? "Set up and add child" : "Set up student"}>{/* a form that sets it up, with the right button words: */}
      <fieldset className="space-y-2">{/* a group of choices: */}
        <legend className="text-sm font-medium">Who is the account for?</legend>{/* its heading, */}
        <label className="flex items-center gap-2 text-sm">{/* a line holding: */}
          <input type="radio" name="who" value="parent" checked={who === "parent"} onChange={() => setWho("parent")} />{/* a round button for "parent", */}
          A parent or carer, with their child. Use this for most students under 18, including those 16 or over.{/* and its words. */}
        </label>{/* End of the line. */}
        <label className="flex items-center gap-2 text-sm">{/* A line holding: */}
          <input type="radio" name="who" value="learner" checked={who === "learner"} onChange={() => setWho("learner")} />{/* a round button for "student", */}
          A student with their own login, and no parent account: an adult learner, or a student 16 or over who manages their own support. A student on a parent&apos;s account can be given their own login later.{/* and its words. */}
        </label>{/* End of the line. */}
      </fieldset>{/* End of the group. */}
      <Field // A name box:
        label={who === "parent" ? "Parent's full name" : "Student's full name"} // labelled for a parent or student,
        name="contact_name" // its field name,
        required // that must be filled in,
        maxLength={200} // up to 200 characters.
      />{/* (end of the box) */}
      <Field // An email box:
        label={who === "parent" ? "Parent's email" : "Student's email"} // labelled for a parent or student,
        name="email" // its field name,
        type="email" // an email address,
        required // that must be filled in,
        hint={who === "parent" ? "If this parent already has an account, the child is added to it." : undefined} // with a hint for parents.
      />{/* (end of the box) */}
      {who === "parent" ? ( // For a parent:
        <>{/* (a group:) */}
          <Field label="Child's full name" name="full_name" required maxLength={200} />{/* the child's full name, */}
          <p className="text-sm text-zinc-600">{/* a grey note: */}
            Fill in what you know. Anything left blank, the family is asked to finish when they first sign in. A tutor
            can&apos;t be assigned until the date of birth, state, year level and school are in.{/* what to fill in, and what's needed before a tutor can be assigned. */}
          </p>{/* End of the note. */}
          <Field label="Child's date of birth (optional)" name="date_of_birth" type="date" hint={DOB_HINT} />{/* date of birth (optional), */}
          <StateSelect label="State the child lives in (optional)" optional />{/* state (optional), */}
          <YearLevelSelect label="Year level at school this year (optional)" optional />{/* year level (optional), */}
          <Field label="School, university or TAFE (optional)" name="school" maxLength={200} />{/* school (optional). */}
        </> // (end of the group)
      ) : ( // For a student:
        <>{/* (a group:) */}
          <Field label="Date of birth" name="date_of_birth" type="date" required hint={DOB_HINT} />{/* date of birth, */}
          <StateSelect label="State they live in" />{/* state, */}
          <YearLevelSelect label="Year level or stage of study" />{/* year level, */}
          <Field label="School, university or TAFE" name="school" required maxLength={200} />{/* school. */}
        </> // (end of the group)
      )}{/* End of the choice. */}
      <SubjectPicker />{/* Subjects, */}
      <GoalFields optional />{/* and goals (optional). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of FamilySetupForm.
