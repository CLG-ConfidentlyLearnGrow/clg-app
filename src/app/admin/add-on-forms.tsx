"use client";

import { giveAddOn, setAddOn } from "@/app/actions/add-ons";
import { ActionForm } from "@/components/action-form";
import { Field, Select } from "@/components/ui";

export type AddOn = {
  code: string;
  name: string;
  description: string | null;
  mode: "free" | "paid" | "off";
  price_cents: number | null;
  price_period: "week" | "month" | "term";
  gst_applies: boolean;
};

// The owner chooses whether an add-on is free for everyone, paid (only the
// students given it), or off, and sets the price families will see.
export function SetAddOnForm({ addOn }: { addOn: AddOn }) {
  return (
    <ActionForm action={setAddOn} submitLabel="Save">
      <input type="hidden" name="code" value={addOn.code} />
      <Select label="Who can use it" name="mode" defaultValue={addOn.mode}>
        <option value="free">Free for everyone</option>
        <option value="paid">Paid: only students given it below</option>
        <option value="off">Off for everyone</option>
      </Select>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field
          label="Price ($)"
          name="price"
          inputMode="decimal"
          placeholder="For example 25"
          defaultValue={addOn.price_cents ? (addOn.price_cents / 100).toFixed(2) : ""}
          hint="Needed before it can be paid. Include GST if it applies."
        />
        <Select label="Charged per" name="price_period" defaultValue={addOn.price_period}>
          <option value="week">Week</option>
          <option value="month">Month</option>
          <option value="term">Term</option>
        </Select>
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" name="gst_applies" defaultChecked={addOn.gst_applies} />
        GST applies to this add-on
      </label>
    </ActionForm>
  );
}

// An admin gives a paid add-on to a student (or changes their dates).
export function GiveAddOnForm({ code, students }: { code: string; students: { id: string; full_name: string }[] }) {
  return (
    <ActionForm action={giveAddOn} submitLabel="Give add-on">
      <input type="hidden" name="add_on" value={code} />
      <Select label="Student" name="student_id" defaultValue="" required>
        <option value="" disabled>
          Choose a student
        </option>
        {students.map((s) => (
          <option key={s.id} value={s.id}>
            {s.full_name}
          </option>
        ))}
      </Select>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="From" name="starts_on" type="date" hint="Leave blank for today." />
        <Field label="Until" name="ends_on" type="date" hint="Leave blank to keep going." />
      </div>
      <Field label="Note (optional)" name="note" maxLength={300} placeholder="For example: pays monthly by card" />
    </ActionForm>
  );
}
