"use client";

import { addAvailability, saveMaxHours, submitMyCheck } from "@/app/actions/tutor";
import { ActionForm } from "@/components/action-form";
import { Field, Select } from "@/components/ui";
import { CHECK_KINDS, CHECK_NAMES, WEEKDAYS } from "@/lib/checks";

export function MaxHoursForm({ current }: { current: number | null }) {
  return (
    <ActionForm action={saveMaxHours} submitLabel="Save hours">
      <Field
        label="Most hours I can work each week"
        name="max_weekly_hours"
        type="number"
        min={0}
        max={60}
        step={0.5}
        defaultValue={current ?? ""}
        required
      />
    </ActionForm>
  );
}

export function AvailabilityForm() {
  return (
    <ActionForm action={addAvailability} submitLabel="Add time">
      <Select label="Day" name="weekday" defaultValue="1">
        {WEEKDAYS.map((d, i) => (
          <option key={d} value={i + 1}>
            {d}
          </option>
        ))}
      </Select>
      <Field label="From" name="starts_at" type="time" required />
      <Field label="To" name="ends_at" type="time" required />
    </ActionForm>
  );
}

export function MyCheckForm() {
  return (
    <ActionForm action={submitMyCheck} submitLabel="Send to CLG">
      <Select label="Check" name="kind" defaultValue="" required>
        <option value="" disabled>
          Choose…
        </option>
        {CHECK_KINDS.map((k) => (
          <option key={k} value={k}>
            {CHECK_NAMES[k]}
          </option>
        ))}
      </Select>
      <Field
        label="Card, registration or certificate number"
        name="reference"
        maxLength={100}
        hint="Not needed for RRHAN-EC training."
      />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field
          label="Date done or issued"
          name="completed_on"
          type="date"
          hint="Needed for a police check: it lasts 5 years from this date."
        />
        <Field
          label="Expires or due again on"
          name="expires_on"
          type="date"
          hint="Leave blank for a police check. The app works it out."
        />
      </div>
      <p className="text-xs text-zinc-500">
        Please have your card or certificate ready to show CLG. CLG confirms each check against the official record
        before it counts. No copies are stored in the app.
      </p>
    </ActionForm>
  );
}
