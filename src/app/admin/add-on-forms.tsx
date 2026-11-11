// Summary: admin forms for add-ons: set who can use one and its price, and give one to a student.
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { giveAddOn, setAddOn } from "@/app/actions/add-ons"; // The server actions for the two forms.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select } from "@/components/ui"; // The input box and drop-down list.

// An add-on as the forms need it.
export type AddOn = {
  code: string; // its code,
  name: string; // its name,
  description: string | null; // its description (if any),
  mode: "free" | "paid" | "off"; // free, paid or off,
  price_cents: number | null; // its price in cents (if set),
  price_period: "week" | "month" | "term"; // charged per week, month or term,
  gst_applies: boolean; // and whether GST applies.
}; // End of the shape.

// The owner chooses whether an add-on is free for everyone, paid (only the
// students given it), or off, and sets the price families will see.
export function SetAddOnForm({ addOn }: { addOn: AddOn }) {
  return ( // Shows:
    <ActionForm action={setAddOn} submitLabel="Save">{/* a form that saves the settings: */}
      <input type="hidden" name="code" value={addOn.code} />{/* the add-on's code (hidden), */}
      <Select label="Who can use it" name="mode" defaultValue={addOn.mode}>{/* a drop-down of who can use it: */}
        <option value="free">Free for everyone</option>{/* free for everyone, */}
        <option value="paid">Paid: only students given it below</option>{/* paid, */}
        <option value="off">Off for everyone</option>{/* off. */}
      </Select>{/* End of the drop-down. */}
      <div className="grid gap-4 sm:grid-cols-2">{/* Two columns on wider screens: */}
        <Field // the price box:
          label="Price ($)" // its label,
          name="price" // its field name,
          inputMode="decimal" // a number keypad with a decimal point on phones,
          placeholder="For example 25" // an example,
          defaultValue={addOn.price_cents ? (addOn.price_cents / 100).toFixed(2) : ""} // starting with the current price in dollars (or blank),
          hint="Needed before it can be paid. Include GST if it applies." // and a hint.
        />{/* (end of the box) */}
        <Select label="Charged per" name="price_period" defaultValue={addOn.price_period}>{/* A drop-down of how often it's charged: */}
          <option value="week">Week</option>{/* week, */}
          <option value="month">Month</option>{/* month, */}
          <option value="term">Term</option>{/* term. */}
        </Select>{/* End of the drop-down. */}
      </div>{/* End of the columns. */}
      <label className="flex items-center gap-2 text-sm">{/* A line holding: */}
        <input type="checkbox" name="gst_applies" defaultChecked={addOn.gst_applies} />{/* a tick box for GST, */}
        GST applies to this add-on{/* and its words. */}
      </label>{/* End of the line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SetAddOnForm.

// An admin gives a paid add-on to a student (or changes their dates).
export function GiveAddOnForm({ code, students }: { code: string; students: { id: string; full_name: string }[] }) {
  return ( // Shows:
    <ActionForm action={giveAddOn} submitLabel="Give add-on">{/* a form that gives it: */}
      <input type="hidden" name="add_on" value={code} />{/* the add-on's code (hidden), */}
      <Select label="Student" name="student_id" defaultValue="" required>{/* a drop-down of students: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose a student{/* "Choose a student", */}
        </option>{/* (end of the option) */}
        {students.map((s) => ( // for each student:
          <option key={s.id} value={s.id}>{/* an option: */}
            {s.full_name}{/* showing their name. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <div className="grid gap-4 sm:grid-cols-2">{/* Two columns on wider screens: */}
        <Field label="From" name="starts_on" type="date" hint="Leave blank for today." />{/* the start date, */}
        <Field label="Until" name="ends_on" type="date" hint="Leave blank to keep going." />{/* the end date. */}
      </div>{/* End of the columns. */}
      <Field label="Note (optional)" name="note" maxLength={300} placeholder="For example: pays monthly by card" />{/* A note (optional). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of GiveAddOnForm.
