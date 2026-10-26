"use client";

import { addAvailability, addTeaching, saveMaxHours, submitMyCheck } from "@/app/actions/tutor";
import { startTransition, useActionState, useState, type FormEvent } from "react";
import { ActionForm } from "@/components/action-form";
import { Button, Field, FormMessage, Select } from "@/components/ui";
import { initialFormState } from "@/lib/forms";
import { CHECK_KINDS, CHECK_NAMES, WEEKDAYS } from "@/lib/checks";
import { SUBJECT_SUGGESTIONS, YEAR_LEVELS, YEAR_LEVEL_NAMES } from "@/lib/students";

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

// Phone photos can be large. Shrink big images before sending so the upload
// is quick and stays under the size limit. PDFs are sent as they are.
async function shrinkImage(file: File): Promise<File> {
  if (!file.type.startsWith("image/") || file.size < 1_500_000) return file;
  try {
    const bitmap = await createImageBitmap(file);
    const scale = Math.min(1, 2400 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(bitmap.width * scale);
    canvas.height = Math.round(bitmap.height * scale);
    canvas.getContext("2d")?.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85));
    return blob ? new File([blob], "certificate.jpg", { type: "image/jpeg" }) : file;
  } catch {
    return file;
  }
}

export function MyCheckForm() {
  const [state, formAction, pending] = useActionState(submitMyCheck, initialFormState);
  const [preparing, setPreparing] = useState(false);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const data = new FormData(form);
    const file = data.get("document");
    if (file instanceof File && file.size > 0) {
      setPreparing(true);
      data.set("document", await shrinkImage(file));
      setPreparing(false);
    }
    startTransition(() => formAction(data));
  }

  const busy = pending || preparing;
  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <FormMessage state={state} />
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
        hint="Not needed for RRHAN-EC training or first aid."
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
      <Field
        label="Copy of the certificate or card"
        name="document"
        type="file"
        required
        accept="application/pdf,image/jpeg,image/png,image/webp"
        hint="A PDF, or a clear photo of the whole card or certificate. Only you and CLG admins can open it."
      />
      <Button type="submit" disabled={busy}>
        {busy ? "Sending…" : "Send to CLG"}
      </Button>
    </form>
  );
}

export function TeachingForm() {
  return (
    <ActionForm action={addTeaching} submitLabel="Add subject">
      <Field
        label="Subject"
        name="subject"
        list="subject-suggestions"
        required
        maxLength={100}
        hint="Pick from the list or type your own."
      />
      <datalist id="subject-suggestions">
        {SUBJECT_SUGGESTIONS.map((s) => (
          <option key={s} value={s} />
        ))}
      </datalist>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Select label="From" name="from_level" defaultValue="" required>
          <option value="" disabled>
            Choose…
          </option>
          {YEAR_LEVELS.map((y) => (
            <option key={y} value={y}>
              {y === "Foundation" ? "Foundation (Reception)" : YEAR_LEVEL_NAMES[y]}
            </option>
          ))}
        </Select>
        <Select label="To" name="to_level" defaultValue="" required>
          <option value="" disabled>
            Choose…
          </option>
          {YEAR_LEVELS.map((y) => (
            <option key={y} value={y}>
              {y === "Foundation" ? "Foundation (Reception)" : YEAR_LEVEL_NAMES[y]}
            </option>
          ))}
        </Select>
      </div>
    </ActionForm>
  );
}
