// Summary: the forms for work outside CLG (Carla, 22 Nov 2026; contract
// clause 6.7): the staff member's form to add or change a report, the form
// to end one, and the owner's "mark as seen" form.
//
"use client"; // Runs in the browser, so each form can show its result straight away.

import { endOutsideWork, markOutsideWorkSeen, saveOutsideWork } from "@/app/actions/outside-work"; // The server actions.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // The input box, drop-down list and larger text box.

// The kinds of role, in words.
export const OUTSIDE_WORK_KINDS = { // The words for each kind:
  tutoring: "Tutoring (private or through another business)", // tutoring,
  education_support: "Other educational support (for example a school or learning centre)", // other educational support,
  admin: "Administrative work", // admin work,
  other: "Something else", // anything else.
} as const; // (fixed list)

// One report as the forms need it.
export type OutsideWork = { // A report:
  id: string; // its id,
  kind: keyof typeof OUTSIDE_WORK_KINDS; // the kind,
  role_title: string; // the role,
  organisation: string | null; // where,
  details: string | null; // anything else,
  paid: boolean; // paid or not,
  starts_on: string; // when it starts,
  ends_on: string | null; // when it ends (if set).
}; // End of the type.

// The add-or-change form (a new report when no report is given).
export function OutsideWorkForm({ report }: { report?: OutsideWork }) { // Takes the report to change, if any.
  return ( // Shows:
    <ActionForm action={saveOutsideWork} submitLabel={report ? "Save changes" : "Tell CLG"}>{/* the form: */}
      <input type="hidden" name="id" value={report?.id ?? ""} />{/* which report (hidden; blank for a new one), */}
      <Select label="Kind of role" name="kind" defaultValue={report?.kind ?? ""} required>{/* the kind: */}
        <option value="" disabled>Choose…</option>{/* a prompt, */}
        {Object.entries(OUTSIDE_WORK_KINDS).map(([k, label]) => <option key={k} value={k}>{label}</option>)}{/* one choice per kind. */}
      </Select>{/* End of the drop-down. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label="The role" name="role_title" maxLength={200} required defaultValue={report?.role_title ?? ""} placeholder="For example: Private maths tutor" />{/* the role, */}
        <Field label="Where (optional)" name="organisation" maxLength={200} defaultValue={report?.organisation ?? ""} hint="The business or school. Leave blank for private work." />{/* where, */}
        <Select label="Paid?" name="paid" defaultValue={report ? (report.paid ? "yes" : "no") : ""} required>{/* paid or not: */}
          <option value="" disabled>Choose…</option>{/* a prompt, */}
          <option value="yes">Paid</option>{/* paid, */}
          <option value="no">Unpaid</option>{/* unpaid. */}
        </Select>{/* End of the drop-down. */}
        <Field label="Starts (or started)" name="starts_on" type="date" required defaultValue={report?.starts_on ?? ""} />{/* the start date, */}
        <Field label="Ends (optional)" name="ends_on" type="date" defaultValue={report?.ends_on ?? ""} />{/* the end date. */}
      </div>{/* End of the columns. */}
      <TextArea label="Anything else CLG should know (optional)" name="details" maxLength={1000} rows={2} defaultValue={report?.details ?? ""} hint="For example how many hours a week. Do not include students' names." />{/* the details. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of OutsideWorkForm.

// The form to end a report.
export function EndOutsideWorkForm({ id, today }: { id: string; today: string }) { // Takes the report and today's date.
  return ( // Shows:
    <ActionForm action={endOutsideWork} submitLabel="Save end date">{/* the form: */}
      <input type="hidden" name="id" value={id} />{/* which report (hidden), */}
      <Field label="It ends (or ended) on" name="ends_on" type="date" defaultValue={today} required />{/* the end date. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of EndOutsideWorkForm.

// The owner's "mark as seen" form.
export function MarkOutsideWorkSeenForm({ id, note }: { id: string; note: string | null }) { // Takes the report and any earlier note.
  return ( // Shows:
    <ActionForm action={markOutsideWorkSeen} submitLabel="Mark as seen">{/* the form: */}
      <input type="hidden" name="id" value={id} />{/* which report (hidden), */}
      <TextArea label="Private note (optional)" name="note" maxLength={1000} rows={2} defaultValue={note ?? ""} hint="Only you see this." />{/* the owner's note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of MarkOutsideWorkSeenForm.
