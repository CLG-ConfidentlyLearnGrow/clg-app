// Summary: the owner's report forms: make a report for chosen dates, and the
// report settings (super and other monthly costs).
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { makeReport, saveReportSettings } from "@/app/actions/reports"; // The server actions that make a report and save settings.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field } from "@/components/ui"; // The labelled input box.

// The "make a report for your dates" form, with quick choices for common ranges.
export function MakeReportForm({ today, ranges }: { today: string; ranges: { label: string; from: string; to: string }[] }) {
  return ( // Shows:
    <div className="space-y-4">{/* a block with space between its parts: */}
      <ActionForm action={makeReport} submitLabel="Make report">{/* a form that makes the report: */}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
          <Field label="First day" name="from" type="date" max={today} required />{/* the first day (today or earlier), */}
          <Field label="Last day" name="to" type="date" required />{/* and the last day. */}
        </div>{/* End of the columns. */}
      </ActionForm>{/* End of the form. */}
      <div>{/* The quick choices: */}
        <p className="mb-2 text-sm text-zinc-600">Or choose a common range:</p>{/* a short note, */}
        <div className="flex flex-wrap gap-2">{/* and a row of buttons that wraps on small screens: */}
          {ranges.map((r) => ( // for each range:
            <ActionChip key={r.label} {...r} /> // a one-tap button for it.
          ))}{/* End of the ranges loop. */}
        </div>{/* End of the row. */}
      </div>{/* End of the quick choices. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of MakeReportForm.

// One quick-choice button: a tiny form with the range's dates hidden inside.
function ActionChip({ label, from, to }: { label: string; from: string; to: string }) {
  return ( // Shows:
    <form action={async (fd) => { await makeReport({}, fd); }}>{/* a form that makes the report straight away (it opens when done), */}
      <input type="hidden" name="from" value={from} />{/* the first day, hidden, */}
      <input type="hidden" name="to" value={to} />{/* the last day, hidden, */}
      <button type="submit" className="rounded-full border border-zinc-300 px-3 py-1.5 text-sm hover:border-brand hover:text-brand">{/* a rounded button: */}
        {label}{/* showing the range's name. */}
      </button>{/* End of the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of ActionChip.

// The report settings form: super, and other running costs a month.
export function ReportSettingsForm({ superPercent, otherCosts }: { superPercent: number; otherCosts: string }) {
  return ( // Shows:
    <ActionForm action={saveReportSettings} submitLabel="Save settings">{/* a form that saves the settings: */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field // the super box:
          label="Super on wages (%)" // its words,
          name="super_percent" // its name,
          type="number" // numbers only,
          step="0.01" // allows part percentages,
          min={0} // no lower than 0,
          max={50} // no higher than 50,
          defaultValue={superPercent} // starts with the saved super,
          hint="Added on top of every wage in the report. 12% from 1 July 2025." // help under the box,
          required // must be filled in.
        />{/* End of the super box. */}
        <Field // the other costs box:
          label="Other running costs a month ($)" // its words,
          name="other_costs" // its name,
          inputMode="decimal" // shows a number keypad on phones,
          defaultValue={otherCosts} // starts with the saved costs,
          hint="Rent, software, insurance, fees and other costs that aren't wages. Used for profit after all costs. Leave blank if not known." // help under the box.
        />{/* End of the other costs box. */}
      </div>{/* End of the columns. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of ReportSettingsForm.
