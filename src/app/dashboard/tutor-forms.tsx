"use client";

import { addAvailability, saveMaxHours } from "@/app/actions/tutor";
import { ActionForm } from "@/components/action-form";
import { Field, Select } from "@/components/ui";
import { WEEKDAYS } from "@/lib/checks";

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
