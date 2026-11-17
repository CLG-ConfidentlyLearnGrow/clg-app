// Summary: admin and staff forms for pay: pay details, admin time, pay runs, pay period and logging hours.
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { addAdminTime, declineHours, linkXeroByEmail, logMyHours, markXeroTaskDone, savePayPeriod, saveStaffPay, sendTimesheetsNow, uploadAwardRates, workOutPay } from "@/app/actions/pay"; // The server actions for these forms.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // The input box, drop-down list and multi-line box.
import { WORK_CATEGORIES } from "@/lib/billing/work-categories"; // The kinds of work outside sessions.

type Option = { id: string; name: string }; // An item in a drop-down: its id and name.

// A tutor's no-show or late-cancel session, for the "Which session?" choice.
export type NoShowSession = { id: string; label: string }; // its id, and its words (when, who and what).

// A staff member's pay details as the form needs them.
export type StaffPay = {
  account_id: string; // who,
  employment: string; // casual, part-time or full-time,
  school_rate_cents: number | null; // school tutoring rate in cents (if set),
  tertiary_rate_cents: number | null; // tertiary rate in cents (if set),
  admin_rate_cents: number | null; // admin rate in cents (if set),
  guaranteed_weekly_minutes: number | null; // agreed weekly minutes (if set),
  xero_employee_id: string | null; // their Xero employee id (if linked),
  xero_school_rate_id: string | null; // Xero rate for school tutoring (if linked),
  xero_tertiary_rate_id: string | null; // Xero rate for tertiary tutoring (if linked),
  xero_admin_rate_id: string | null; // Xero rate for admin (if linked).
}; // End of the shape.

const money = (c: number | null) => (c === null ? "" : (c / 100).toFixed(2)); // Cents as dollars with two decimal places (or blank).

// A drop-down of Xero employees or earnings rates.
function XeroSelect({ label, name, value, options }: { label: string; name: string; value: string | null; options: Option[] }) {
  return ( // Shows:
    <Select label={label} name={name} defaultValue={value ?? ""}>{/* a drop-down, starting on the current choice: */}
      <option value="">Not chosen</option>{/* "Not chosen", */}
      {options.map((o) => ( // for each option:
        <option key={o.id} value={o.id}>{/* an option: */}
          {o.name}{/* its name. */}
        </option> // (end of the option)
      ))}{/* End of the loop. */}
    </Select> // End of the drop-down.
  ); // End of what's shown.
} // End of XeroSelect.

// The form for a staff member's pay details.
export function StaffPayForm({
  accountId, // who,
  pay, // their current pay details,
  xeroEmployees, // Xero employees to choose from,
  xeroRates, // Xero earnings rates to choose from,
  suggestedEmployee, // the Xero employee that seems to match,
  roles, // and their roles.
}: { // (their types:)
  roles: string[]; // a list of roles,
  accountId: string; // an id,
  pay: StaffPay | null; // pay details or nothing,
  xeroEmployees: Option[] | null; // a list or nothing,
  xeroRates: Option[] | null; // a list or nothing,
  suggestedEmployee: string | null; // an id or nothing.
}) { // (end of the settings)
  const tutor = roles.includes("tutor"); // True if they're a tutor.
  const admin = roles.includes("admin"); // True if they're an admin.
  return ( // Shows:
    <ActionForm action={saveStaffPay} submitLabel="Save pay details">{/* a form that saves the details: */}
      <input type="hidden" name="account_id" value={accountId} />{/* who (hidden), */}
      <Select label="Employment" name="employment" defaultValue={pay?.employment ?? "casual"}>{/* a drop-down of employment type (casual to start): */}
        <option value="casual">Casual</option>{/* casual, */}
        <option value="part_time">Part-time</option>{/* part-time, */}
        <option value="full_time">Full-time</option>{/* full-time. */}
      </Select>{/* End of the drop-down. */}
      <Field // The agreed hours box:
        label="Agreed hours per week (part-time and full-time only)" // its label,
        name="guaranteed_hours" // its field name,
        inputMode="decimal" // a number keypad with a decimal point on phones,
        placeholder="For example 10" // an example,
        defaultValue={pay?.guaranteed_weekly_minutes != null ? String(Math.round((pay.guaranteed_weekly_minutes / 60) * 100) / 100) : ""} // starting with the current hours (or blank).
      />{/* (end of the box) */}
      <p className="-mt-2 text-xs text-zinc-600">{/* A small grey note: */}
        If their sessions and logged hours come to less than this in a pay period (for example in the school holidays), the
        app adds a top-up for you to approve. Leave empty for casuals.{/* what the top-up does. */}
      </p>{/* End of the note. */}
      {/* One rate for each role the person holds. A rate for a role they
          no longer hold is kept as it is (hidden), so it isn't lost. */}
      {tutor ? ( // For tutors:
        <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
          <Field label="Tutor: school tutoring ($/hr)" name="school_rate" defaultValue={money(pay?.school_rate_cents ?? null)} inputMode="decimal" />{/* the school tutoring rate, */}
          <Field label="Tutor: tertiary and other ($/hr)" name="tertiary_rate" defaultValue={money(pay?.tertiary_rate_cents ?? null)} inputMode="decimal" />{/* the tertiary rate. */}
        </div> // End of the columns.
      ) : ( // Otherwise:
        <>{/* (a group:) */}
          <input type="hidden" name="school_rate" value={money(pay?.school_rate_cents ?? null)} />{/* the school rate kept as it is (hidden), */}
          <input type="hidden" name="tertiary_rate" value={money(pay?.tertiary_rate_cents ?? null)} />{/* the tertiary rate kept as it is (hidden). */}
        </> // (end of the group)
      )}{/* End of the choice. */}
      {admin ? ( // For admins:
        <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
          <Field label="Admin ($/hr)" name="admin_rate" defaultValue={money(pay?.admin_rate_cents ?? null)} inputMode="decimal" />{/* the admin rate. */}
        </div> // End of the columns.
      ) : ( // Otherwise:
        <input type="hidden" name="admin_rate" value={money(pay?.admin_rate_cents ?? null)} /> // the admin rate kept as it is (hidden).
      )}{/* End of the choice. */}
      {xeroEmployees && xeroRates && ( // If Xero is connected:
        <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
          <XeroSelect label="Xero employee" name="xero_employee_id" value={pay?.xero_employee_id ?? suggestedEmployee} options={xeroEmployees} />{/* the Xero employee, */}
          {tutor ? ( // for tutors:
            <>{/* (a group:) */}
              <XeroSelect label="Xero earnings rate: school tutoring" name="xero_school_rate_id" value={pay?.xero_school_rate_id ?? null} options={xeroRates} />{/* the Xero rate for school tutoring, */}
              <XeroSelect label="Xero earnings rate: tertiary tutoring" name="xero_tertiary_rate_id" value={pay?.xero_tertiary_rate_id ?? null} options={xeroRates} />{/* the Xero rate for tertiary tutoring. */}
            </> // (end of the group)
          ) : ( // Otherwise:
            <>{/* (a group:) */}
              <input type="hidden" name="xero_school_rate_id" value={pay?.xero_school_rate_id ?? ""} />{/* kept as it is (hidden), */}
              <input type="hidden" name="xero_tertiary_rate_id" value={pay?.xero_tertiary_rate_id ?? ""} />{/* kept as it is (hidden). */}
            </> // (end of the group)
          )}{/* End of the choice. */}
          {admin ? ( // For admins:
            <XeroSelect label="Xero earnings rate: admin" name="xero_admin_rate_id" value={pay?.xero_admin_rate_id ?? null} options={xeroRates} /> // the Xero rate for admin,
          ) : ( // otherwise:
            <input type="hidden" name="xero_admin_rate_id" value={pay?.xero_admin_rate_id ?? ""} /> // kept as it is (hidden).
          )}{/* End of the choice. */}
        </div> // End of the columns.
      )}{/* End of the Xero part. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of StaffPayForm.

// The form for recording someone's admin hours.
export function AdminTimeForm({ staff }: { staff: Option[] }) {
  return ( // Shows:
    <ActionForm action={addAdminTime} submitLabel="Record hours">{/* a form that records the hours: */}
      <div className="grid gap-3 sm:grid-cols-3">{/* three columns on wider screens: */}
        <Select label="Person" name="account_id" required defaultValue="">{/* a drop-down of people: */}
          <option value="" disabled>{/* a blank first option that can't be picked: */}
            Choose…{/* "Choose…", */}
          </option>{/* (end of the option) */}
          {staff.map((s) => ( // for each person:
            <option key={s.id} value={s.id}>{/* an option: */}
              {s.name}{/* their name. */}
            </option> // (end of the option)
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <Field label="Day" name="day" type="date" required />{/* The day, */}
        <Field label="Hours" name="hours" inputMode="decimal" required placeholder="1.5" />{/* the hours. */}
      </div>{/* End of the columns. */}
      <Field label="What it was for" name="note" maxLength={300} placeholder="For example: progress summaries" />{/* What it was for. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AdminTimeForm.

// A button to work out pay again for a period.
export function WorkOutPayForm({ from, to }: { from: string; to: string }) {
  return ( // Shows:
    <ActionForm action={workOutPay} submitLabel="Work out pay again">{/* a form that works it out: */}
      <input type="hidden" name="from" value={from} />{/* the first day (hidden), */}
      <input type="hidden" name="to" value={to} />{/* the last day (hidden), */}
      <p className="text-sm text-zinc-600">{/* a grey note: */}
        Pay is worked out every morning from the times tutors signed on and off. Do it again now after confirming a
        changed time.{/* when pay is worked out. */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of WorkOutPayForm.

// A button to send this period's timesheets to Xero Payroll.
export function SendTimesheetsForm({ periodStart }: { periodStart: string }) {
  return ( // Shows:
    <ActionForm action={sendTimesheetsNow} submitLabel="Send to Xero Payroll">{/* a form that sends them: */}
      <input type="hidden" name="period_start" value={periodStart} />{/* the period's first day (hidden), */}
      <p className="text-sm text-zinc-600">{/* a grey note: */}
        Sends a draft timesheet for each person with pay waiting in this period. You check and approve them in Xero
        before the pay run.{/* what it sends and what to do next. */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SendTimesheetsForm.

// The form for the pay period settings.
export function PayPeriodForm({ days, anchor, casualMin }: { days: number; anchor: string; casualMin: boolean }) {
  return ( // Shows:
    <ActionForm action={savePayPeriod} submitLabel="Save pay period">{/* a form that saves them: */}
      <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="Pay period" name="pay_period_days" defaultValue={String(days)}>{/* a drop-down of the pay period: */}
          <option value="7">Weekly</option>{/* weekly, */}
          <option value="14">Fortnightly</option>{/* fortnightly. */}
        </Select>{/* End of the drop-down. */}
        <Field label="A day a pay period starts" name="pay_period_anchor" type="date" defaultValue={anchor} required />{/* A day a pay period starts. */}
      </div>{/* End of the columns. */}
      <p className="text-xs text-zinc-500">This must match the pay calendar set up in Xero Payroll.</p>{/* A note that it must match Xero. */}
      <label className="flex items-start gap-2 text-sm">{/* A line holding: */}
        <input type="checkbox" name="casual_min_enabled" defaultChecked={casualMin} className="mt-1" />{/* a tick box for the casual minimum, */}
        <span>Top up casual staff to the 2 hr minimum on each day they work (award rule; off for now)</span>{/* and its words. */}
      </label>{/* End of the line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of PayPeriodForm.

// The form for declining logged hours with a reason.
export function DeclineHoursForm({ id }: { id: string }) {
  return ( // Shows:
    <ActionForm action={declineHours} submitLabel="Decline">{/* a form that declines them: */}
      <input type="hidden" name="id" value={id} />{/* which log (hidden), */}
      <Field label="Reason" name="reason" required minLength={3} maxLength={300} placeholder="For example: already paid as session time" />{/* the reason. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of DeclineHoursForm.

// The form for staff to log their own hours.
export function LogHoursForm({ today, canTutor, canAdmin, noShowSessions }: { today: string; canTutor: boolean; canAdmin: boolean; noShowSessions: NoShowSession[] }) { // Takes today, which kinds they can log, and their no-show sessions.
  const kinds = WORK_CATEGORIES.filter((c) => (c.type === "admin" ? canAdmin : canTutor)); // The kinds of work this person can log (office admin only for admin staff).
  return ( // Shows:
    <ActionForm action={logMyHours} submitLabel="Log hours">{/* a form that logs the hours: */}
      <Select label="What kind of work?" name="category" required defaultValue="">{/* the kind of work (Carla, 18 Nov 2026): */}
        <option value="" disabled>Choose one</option>{/* a prompt to choose, */}
        {kinds.map((c) => ( // each kind:
          <option key={c.id} value={c.id}>{/* an option: */}
            {c.label}{/* its words. */}
          </option> // (end of the option)
        ))}{/* End of the kinds. */}
      </Select>{/* End of the drop-down. */}
      <ul className="space-y-1 text-xs text-zinc-600">{/* a short help line for each kind: */}
        {kinds.map((c) => ( // each kind:
          <li key={c.id}><strong>{c.label}:</strong> {c.help}</li> // its name and what it covers.
        ))}{/* End of the help lines. */}
      </ul>{/* End of the help. */}
      <div className="grid gap-3 sm:grid-cols-2">{/* Two columns on wider screens: */}
        <Field label="Day" name="day" type="date" required max={today} defaultValue={today} />{/* the day (today or earlier), */}
        <Field label="Hours" name="hours" inputMode="decimal" required placeholder="1.5" />{/* the hours. */}
      </div>{/* End of the columns. */}
      {canTutor && noShowSessions.length > 0 && ( // If they have no-show or late-cancel sessions to choose from:
        <Select label="Which session? (only for work during a no-show or late cancel)" name="session_id" defaultValue="">{/* the session drop-down: */}
          <option value="">Not a no-show or late cancel</option>{/* none, for every other kind of work, */}
          {noShowSessions.map((s) => ( // each session:
            <option key={s.id} value={s.id}>{/* an option: */}
              {s.label}{/* when, who and what. */}
            </option> // (end of the option)
          ))}{/* End of the sessions. */}
        </Select> // End of the drop-down.
      )}{/* End of the session choice. */}
      <Field label="What you did" name="note" required minLength={10} maxLength={300} placeholder="For example: made fraction worksheets for Year 7" />{/* What they did. */}
      <TextArea label="What you finished or achieved" name="achieved" required minLength={10} maxLength={1000} rows={2} placeholder="For example: three Year 7 fraction worksheets with answers, saved in Materials" hint="CLG checks this before approving the hours." />{/* What they achieved (Carla, 18 Nov 2026). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LogHoursForm.

// Upload form for a year's award minimum rates: the start date, and a CSV
// file (or pasted lines). templateCsv is this year's rates, to download,
// change and upload again.
export function AwardRatesForm({ nextJuly, templateCsv }: { nextJuly: string; templateCsv: string }) {
  return ( // The form:
    <ActionForm action={uploadAwardRates} submitLabel="Upload award rates">{/* sends to the upload action */}
      <Field label="New rates start on" name="effective_from" type="date" required defaultValue={nextJuly} />{/* the start date (next 1 July by default) */}
      <label className="block text-sm">{/* the file picker: */}
        <span className="mb-1 block font-medium">Rates file (CSV)</span>{/* its label */}
        <input type="file" name="file" accept=".csv,text/csv,text/plain" className="block text-sm" />{/* choose a .csv file */}
      </label>{/* end of the file picker */}
      <label className="block text-sm">{/* or paste the lines: */}
        <span className="mb-1 block font-medium">Or paste the lines</span>{/* its label */}
        <textarea name="csv" rows={5} className="w-full rounded-lg border border-zinc-300 p-2 font-mono text-xs" placeholder="school,casual,33.50,Miscellaneous Award MA000104 Level 1 casual" />{/* the paste box */}
      </label>{/* end of the paste box */}
      <p className="text-xs text-zinc-600">{/* help text: */}
        One line per rate: work (school, tertiary or admin), employment (casual, part_time or full_time), hourly rate, award name.{" "}
        <a className="underline" href={`data:text/csv;charset=utf-8,${encodeURIComponent(templateCsv)}`} download="clg-award-rates.csv">Download this year&apos;s rates</a>{/* a ready-made file to change */}
        {" "}to change and upload. Anyone below the new minimum for their employment type is raised on the start date; rates already above it are not changed.
      </p>{/* end of the help text */}
    </ActionForm> // End of the form.
  ); // End of what it shows.
} // End of AwardRatesForm.

// The button that ticks off one line on the Xero to-do list.
export function XeroTaskDoneForm({ id }: { id: string }) {
  return ( // Shows:
    <ActionForm action={markXeroTaskDone} submitLabel="Done in Xero">{/* a form that ticks it off: */}
      <input type="hidden" name="task_id" value={id} />{/* which to-do (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of XeroTaskDoneForm.

// The button that links staff to Xero employees with the same email.
export function LinkXeroByEmailForm() {
  return ( // Shows:
    <ActionForm action={linkXeroByEmail} submitLabel="Link staff to Xero by email">{/* a form that links them: */}
      <p className="text-xs text-zinc-600">{/* a small note: */}
        Links everyone not yet linked to the Xero employee with the same email. Anyone already linked stays as they are.{/* what it does. */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LinkXeroByEmailForm.
