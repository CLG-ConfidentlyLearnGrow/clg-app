"use client";

import { addAdminTime, savePayPeriod, saveStaffPay, sendTimesheetsNow, workOutPay } from "@/app/actions/pay";
import { ActionForm } from "@/components/action-form";
import { Field, Select } from "@/components/ui";

type Option = { id: string; name: string };

export type StaffPay = {
  account_id: string;
  employment: string;
  school_rate_cents: number | null;
  tertiary_rate_cents: number | null;
  admin_rate_cents: number | null;
  xero_employee_id: string | null;
  xero_school_rate_id: string | null;
  xero_tertiary_rate_id: string | null;
  xero_admin_rate_id: string | null;
};

const money = (c: number | null) => (c === null ? "" : (c / 100).toFixed(2));

function XeroSelect({ label, name, value, options }: { label: string; name: string; value: string | null; options: Option[] }) {
  return (
    <Select label={label} name={name} defaultValue={value ?? ""}>
      <option value="">Not chosen</option>
      {options.map((o) => (
        <option key={o.id} value={o.id}>
          {o.name}
        </option>
      ))}
    </Select>
  );
}

export function StaffPayForm({
  accountId,
  pay,
  xeroEmployees,
  xeroRates,
  suggestedEmployee,
}: {
  accountId: string;
  pay: StaffPay | null;
  xeroEmployees: Option[] | null;
  xeroRates: Option[] | null;
  suggestedEmployee: string | null;
}) {
  return (
    <ActionForm action={saveStaffPay} submitLabel="Save pay details">
      <input type="hidden" name="account_id" value={accountId} />
      <Select label="Employment" name="employment" defaultValue={pay?.employment ?? "casual"}>
        <option value="casual">Casual</option>
        <option value="part_time">Part-time</option>
        <option value="full_time">Full-time</option>
      </Select>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field label="School tutoring ($/hr)" name="school_rate" defaultValue={money(pay?.school_rate_cents ?? null)} inputMode="decimal" />
        <Field label="Tertiary and other ($/hr)" name="tertiary_rate" defaultValue={money(pay?.tertiary_rate_cents ?? null)} inputMode="decimal" />
        <Field label="Admin ($/hr)" name="admin_rate" defaultValue={money(pay?.admin_rate_cents ?? null)} inputMode="decimal" />
      </div>
      {xeroEmployees && xeroRates && (
        <div className="grid gap-3 sm:grid-cols-2">
          <XeroSelect label="Xero employee" name="xero_employee_id" value={pay?.xero_employee_id ?? suggestedEmployee} options={xeroEmployees} />
          <XeroSelect label="Xero earnings rate: school" name="xero_school_rate_id" value={pay?.xero_school_rate_id ?? null} options={xeroRates} />
          <XeroSelect label="Xero earnings rate: tertiary" name="xero_tertiary_rate_id" value={pay?.xero_tertiary_rate_id ?? null} options={xeroRates} />
          <XeroSelect label="Xero earnings rate: admin" name="xero_admin_rate_id" value={pay?.xero_admin_rate_id ?? null} options={xeroRates} />
        </div>
      )}
    </ActionForm>
  );
}

export function AdminTimeForm({ staff }: { staff: Option[] }) {
  return (
    <ActionForm action={addAdminTime} submitLabel="Record hours">
      <div className="grid gap-3 sm:grid-cols-3">
        <Select label="Person" name="account_id" required defaultValue="">
          <option value="" disabled>
            Choose…
          </option>
          {staff.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </Select>
        <Field label="Day" name="day" type="date" required />
        <Field label="Hours" name="hours" inputMode="decimal" required placeholder="1.5" />
      </div>
      <Field label="What it was for" name="note" maxLength={300} placeholder="For example: progress summaries" />
    </ActionForm>
  );
}

export function WorkOutPayForm({ from, to }: { from: string; to: string }) {
  return (
    <ActionForm action={workOutPay} submitLabel="Work out pay again">
      <input type="hidden" name="from" value={from} />
      <input type="hidden" name="to" value={to} />
      <p className="text-sm text-zinc-600">
        Pay is worked out every morning from the times tutors signed on and off. Do it again now after confirming a
        changed time.
      </p>
    </ActionForm>
  );
}

export function SendTimesheetsForm({ periodStart }: { periodStart: string }) {
  return (
    <ActionForm action={sendTimesheetsNow} submitLabel="Send to Xero Payroll">
      <input type="hidden" name="period_start" value={periodStart} />
      <p className="text-sm text-zinc-600">
        Sends a draft timesheet for each person with pay waiting in this period. You check and approve them in Xero
        before the pay run.
      </p>
    </ActionForm>
  );
}

export function PayPeriodForm({ days, anchor, casualMin }: { days: number; anchor: string; casualMin: boolean }) {
  return (
    <ActionForm action={savePayPeriod} submitLabel="Save pay period">
      <div className="grid gap-3 sm:grid-cols-2">
        <Select label="Pay period" name="pay_period_days" defaultValue={String(days)}>
          <option value="7">Weekly</option>
          <option value="14">Fortnightly</option>
        </Select>
        <Field label="A day a pay period starts" name="pay_period_anchor" type="date" defaultValue={anchor} required />
      </div>
      <p className="text-xs text-zinc-500">This must match the pay calendar set up in Xero Payroll.</p>
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" name="casual_min_enabled" defaultChecked={casualMin} className="mt-1" />
        <span>Top up casual staff to the 2 hr minimum on each day they work (award rule; off for now)</span>
      </label>
    </ActionForm>
  );
}
