// Summary: the admin form for recording when a family or tutor leaves CLG.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { recordLeaving } from "@/app/actions/leaving"; // The server action that records it.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // The input box, drop-down list and larger text box.
import { LEAVING_REASONS } from "./leaving-reasons"; // The list of reasons.

// Shows the leaving form.
export function LeavingForm({ people, today }: { people: { value: string; label: string }[]; today: string }) {
  return ( // Shows:
    <ActionForm action={recordLeaving} submitLabel="Save">{/* a form that saves it: */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="Who left" name="who" defaultValue="" required>{/* a drop-down of who left: */}
          <option value="" disabled>{/* a blank first option that can't be picked: */}
            Choose…{/* "Choose…", */}
          </option>{/* (end of the option) */}
          {people.map((p) => ( // for each person:
            <option key={p.value} value={p.value}>{/* an option: */}
              {p.label}{/* showing their name. */}
            </option> // (end of the option)
          ))}{/* End of the people loop. */}
        </Select>{/* End of the drop-down. */}
        <Field label="Day they left" name="left_on" type="date" max={today} defaultValue={today} required />{/* The day they left (today or earlier). */}
      </div>{/* End of the columns. */}
      <Select label="Main reason" name="reason" defaultValue="" required>{/* A drop-down of the main reason: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose…{/* "Choose…", */}
        </option>{/* (end of the option) */}
        {Object.entries(LEAVING_REASONS).map(([k, label]) => ( // for each reason:
          <option key={k} value={k}>{/* an option: */}
            {label}{/* showing the reason's words. */}
          </option> // (end of the option)
        ))}{/* End of the reasons loop. */}
      </Select>{/* End of the drop-down. */}
      <TextArea label="Details (optional)" name="details" maxLength={2000} rows={2} />{/* Details (optional). */}
      <Select label="Did they leave happy?" name="left_happy" defaultValue="">{/* A drop-down: did they leave happy? */}
        <option value="">Not sure</option>{/* not sure, */}
        <option value="yes">Yes</option>{/* yes, */}
        <option value="no">No</option>{/* no. */}
      </Select>{/* End of the drop-down. */}
      <label className="flex items-start gap-2 text-sm">{/* A line holding: */}
        <input type="checkbox" name="review_asked" className="mt-1" /> We asked them for a testimonial or Google review{/* a tick box for whether a testimonial or review was asked for. */}
      </label>{/* End of the line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LeavingForm.
