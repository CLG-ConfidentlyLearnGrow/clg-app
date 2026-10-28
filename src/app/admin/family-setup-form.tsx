"use client";

import { useState } from "react";
import { DOB_HINT } from "@/lib/students";
import { setUpFamily } from "@/app/actions/family-setup";
import { GoalFields } from "@/app/dashboard/add-child-form";
import { ActionForm } from "@/components/action-form";
import { StateSelect } from "@/components/state-select";
import { SubjectPicker } from "@/components/subject-picker";
import { Field } from "@/components/ui";
import { YearLevelSelect } from "@/components/year-level-select";

// An admin fills in a family's details for them and sends the login link.
export function FamilySetupForm() {
  const [who, setWho] = useState<"parent" | "learner">("parent");
  return (
    <ActionForm action={setUpFamily} submitLabel={who === "parent" ? "Set up and add child" : "Set up student"}>
      <fieldset className="space-y-2">
        <legend className="text-sm font-medium">Who is the account for?</legend>
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" name="who" value="parent" checked={who === "parent"} onChange={() => setWho("parent")} />
          A parent or carer, with their child
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" name="who" value="learner" checked={who === "learner"} onChange={() => setWho("learner")} />
          A student aged 16 or over, or an adult learner, with their own login
        </label>
      </fieldset>
      <Field
        label={who === "parent" ? "Parent's full name" : "Student's full name"}
        name="contact_name"
        required
        maxLength={200}
      />
      <Field
        label={who === "parent" ? "Parent's email" : "Student's email"}
        name="email"
        type="email"
        required
        hint={who === "parent" ? "If this parent already has an account, the child is added to it." : undefined}
      />
      {who === "parent" ? (
        <>
          <Field label="Child's full name" name="full_name" required maxLength={200} />
          <p className="text-sm text-zinc-600">
            Fill in what you know. Anything left blank, the family is asked to finish when they first sign in. A tutor
            can&apos;t be assigned until the date of birth, state, year level and school are in.
          </p>
          <Field label="Child's date of birth (optional)" name="date_of_birth" type="date" hint={DOB_HINT} />
          <StateSelect label="State the child lives in (optional)" optional />
          <YearLevelSelect label="Year level at school this year (optional)" optional />
          <Field label="School (optional)" name="school" maxLength={200} />
        </>
      ) : (
        <>
          <Field label="Date of birth" name="date_of_birth" type="date" required hint={DOB_HINT} />
          <StateSelect label="State they live in" />
          <YearLevelSelect label="Year level or stage of study" />
          <Field label="School, university or TAFE" name="school" required maxLength={200} />
        </>
      )}
      <SubjectPicker />
      <GoalFields optional />
    </ActionForm>
  );
}
