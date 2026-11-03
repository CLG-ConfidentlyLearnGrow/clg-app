"use client";

import { recordLeaving } from "@/app/actions/leaving";
import { ActionForm } from "@/components/action-form";
import { Field, Select, TextArea } from "@/components/ui";
import { LEAVING_REASONS } from "./leaving-reasons";

export function LeavingForm({ people, today }: { people: { value: string; label: string }[]; today: string }) {
  return (
    <ActionForm action={recordLeaving} submitLabel="Save">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Select label="Who left" name="who" defaultValue="" required>
          <option value="" disabled>
            Choose…
          </option>
          {people.map((p) => (
            <option key={p.value} value={p.value}>
              {p.label}
            </option>
          ))}
        </Select>
        <Field label="Day they left" name="left_on" type="date" max={today} defaultValue={today} required />
      </div>
      <Select label="Main reason" name="reason" defaultValue="" required>
        <option value="" disabled>
          Choose…
        </option>
        {Object.entries(LEAVING_REASONS).map(([k, label]) => (
          <option key={k} value={k}>
            {label}
          </option>
        ))}
      </Select>
      <TextArea label="Details (optional)" name="details" maxLength={2000} rows={2} />
      <Select label="Did they leave happy?" name="left_happy" defaultValue="">
        <option value="">Not sure</option>
        <option value="yes">Yes</option>
        <option value="no">No</option>
      </Select>
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" name="review_asked" className="mt-1" /> We asked them for a testimonial or Google review
      </label>
    </ActionForm>
  );
}
