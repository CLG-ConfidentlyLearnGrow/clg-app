// Summary: the admin form for loading Australian Curriculum subjects from ACARA's Excel file.
//
"use client"; // Runs in the browser, so the file can be read here before sending.

import { useActionState, useMemo, useState } from "react"; // Lets the form remember its reply, the file's subjects and the ticks.
import { readSheet } from "read-excel-file/browser"; // Reads Excel files in the browser.
import { importAcara } from "@/app/actions/curriculum"; // The server action that saves the drafts.
import { Button, FormMessage } from "@/components/ui"; // The button and reply message.
import { ACARA_SHEET, parseAcara, type AcaraCurriculum } from "@/lib/acara"; // The sheet to read, the reader, and the type of one curriculum.
import { initialFormState } from "@/lib/forms"; // The starting (empty) form reply.

// Subjects ticked to start with: the ones CLG tutors most.
const CORE = new Set(["English", "Mathematics", "Science", "HASS F-6", "History 7-10", "Geography 7-10"]); // The core subjects.

// Load many curricula at once from ACARA's "Download entire curriculum"
// Excel file. The file is read here in the browser; only the ticked
// subjects are sent, each as a draft for an admin to confirm.
export function AcaraImportForm({ loadedCodes }: { loadedCodes: string[] }) {
  const [state, formAction, pending] = useActionState(importAcara, initialFormState); // The reply, the action to send, and whether it's sending.
  const [curricula, setCurricula] = useState<AcaraCurriculum[]>([]); // The subjects found in the file.
  const [chosen, setChosen] = useState<Set<string>>(new Set()); // The codes of the ticked subjects.
  const [readError, setReadError] = useState(""); // Any problem reading the file.
  const [reading, setReading] = useState(false); // Whether the file is being read.
  const loaded = useMemo(() => new Set(loadedCodes), [loadedCodes]); // The codes already loaded, as a set (worked out once).

  // Reads the chosen file into subjects.
  async function readFile(file: File | undefined) {
    setReadError(""); // Clears any earlier problem,
    setCurricula([]); // and any earlier subjects.
    if (!file) return; // No file: stops.
    setReading(true); // Shows "Reading the file…".
    try { // Tries:
      const rows = await readSheet(file, ACARA_SHEET); // reads the right sheet,
      const result = parseAcara(rows); // and turns it into subjects.
      if ("error" in result) { // A problem:
        setReadError(result.error); // shows it.
      } else { // Otherwise:
        setCurricula(result); // keeps the subjects,
        setChosen(new Set(result.filter((c) => CORE.has(c.subject) && !loaded.has(c.code)).map((c) => c.code))); // and ticks the core ones not loaded yet.
      } // End of the choice.
    } catch { // If the file couldn't be read:
      setReadError( // shows:
        'Couldn\'t read that file. Use the "Download entire curriculum" Excel file from australiancurriculum.edu.au/downloads.', // which file to use.
      ); // (end of the message)
    } finally { // Either way:
      setReading(false); // stops showing "Reading".
    } // End of the try.
  } // End of readFile.

  const byArea = new Map<string, AcaraCurriculum[]>(); // The subjects grouped by learning area.
  for (const c of curricula) byArea.set(c.learningArea, [...(byArea.get(c.learningArea) ?? []), c]); // Adds each subject to its area's group.

  const toggle = (codes: string[], on: boolean) => // Ticks or unticks a list of subjects:
    setChosen((prev) => { // changes the ticks:
      const next = new Set(prev); // a copy of the current ticks,
      for (const code of codes) { // for each subject:
        if (on && !loaded.has(code)) next.add(code); // ticks it (unless already loaded),
        else next.delete(code); // or unticks it.
      } // End of the loop.
      return next; // Gives back the new ticks.
    }); // End of toggle.

  const picked = curricula.filter((c) => chosen.has(c.code)); // The ticked subjects.
  const payload = JSON.stringify( // What to send:
    picked.map(({ code, name, subject, skills }) => ({ code, name, subject, skills })), // each ticked subject's code, name, subject and skills.
  ); // (end of the data)
  const skillCount = picked.reduce((n, c) => n + c.skills.length, 0); // How many skills are ticked in all.

  return ( // Shows:
    <div className="space-y-4">{/* a block with space between parts: */}
      <ol className="list-decimal space-y-1 pl-5 text-sm text-zinc-700">{/* a numbered list of steps: */}
        <li>{/* step: */}
          Go to{" "}{/* "Go to", */}
          <a // a link:
            href="https://www.australiancurriculum.edu.au/downloads" // to ACARA's downloads page,
            target="_blank" // in a new tab,
            rel="noreferrer" // safely,
            className="text-teal-800 underline" // styled as a link.
          >{/* (end of its settings) */}
            australiancurriculum.edu.au/downloads{/* the address, */}
          </a>{" "}{/* (end of the link and a space) */}
          and download the &quot;entire curriculum&quot; Excel file.{/* and download the file. */}
        </li>{/* (end of step) */}
        <li>Choose that file below, tick the subjects you want, and press Load.</li>{/* Choose it, tick subjects, and press Load. */}
        <li>Each subject arrives as a draft. Check its summary, then confirm it.</li>{/* Check each draft, then confirm. */}
      </ol>{/* End of the list. */}

      <label className="block text-sm font-medium">{/* A label: */}
        ACARA curriculum file (.xlsx){/* "ACARA curriculum file", */}
        <input // a file picker:
          type="file" // (a file)
          accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" // that accepts Excel files,
          onChange={(e) => readFile(e.target.files?.[0])} // reads the file as soon as it's chosen,
          className="mt-1 block w-full text-sm file:mr-3 file:rounded-full file:border-0 file:bg-teal-50 file:px-4 file:py-2 file:text-teal-800" // styled with a soft button.
        />{/* (end of the picker) */}
      </label>{/* End of the label. */}
      {reading && <p className="text-sm text-zinc-600">Reading the file…</p>}{/* "Reading the file…" while reading, */}
      {readError && <p className="text-sm text-red-700">{readError}</p>}{/* any reading problem in red. */}

      {curricula.length > 0 && ( // When subjects are found:
        <form action={formAction} className="space-y-4">{/* a form: */}
          <FormMessage state={state} />{/* the reply message, */}
          <input type="hidden" name="payload" value={payload} />{/* the ticked subjects, as hidden data, */}
          <div className="flex flex-wrap gap-3 text-sm">{/* a row of buttons: */}
            <button type="button" className="text-teal-800 underline" onClick={() => toggle(curricula.map((c) => c.code), true)}>{/* a button that ticks everything: */}
              Tick all{/* "Tick all". */}
            </button>{/* (end of the button) */}
            <button type="button" className="text-teal-800 underline" onClick={() => setChosen(new Set())}>{/* A button that unticks everything: */}
              Untick all{/* "Untick all". */}
            </button>{/* (end of the button) */}
          </div>{/* End of the row. */}
          <div className="max-h-96 space-y-4 overflow-y-auto rounded-xl border border-zinc-200 p-4">{/* A scrolling box: */}
            {[...byArea.entries()].map(([area, list]) => ( // for each learning area:
              <fieldset key={area}>{/* a group: */}
                <legend className="mb-1 flex items-center gap-3 text-sm font-semibold">{/* its heading: */}
                  {area}{/* the area's name, */}
                  <button // a button:
                    type="button" // (a plain button)
                    className="text-xs font-normal text-teal-800 underline" // styled as a small link,
                    onClick={() => toggle(list.map((c) => c.code), !list.every((c) => chosen.has(c.code)))} // that ticks the whole area (or unticks it if all are ticked):
                  >{/* (end of its settings) */}
                    {list.every((c) => chosen.has(c.code)) ? "Untick these" : "Tick these"}{/* its words change to match. */}
                  </button>{/* End of the button. */}
                </legend>{/* End of the heading. */}
                <ul className="space-y-1">{/* A list: */}
                  {list.map((c) => ( // for each subject:
                    <li key={c.code}>{/* a list item: */}
                      <label className="flex items-start gap-2 text-sm">{/* a line holding: */}
                        <input // a tick box:
                          type="checkbox" // (a tick box)
                          className="mt-1" // with a little space above,
                          checked={chosen.has(c.code)} // ticked if chosen,
                          disabled={loaded.has(c.code)} // greyed out if already loaded,
                          onChange={(e) => toggle([c.code], e.target.checked)} // ticks or unticks it when clicked.
                        />{/* (end of the tick box) */}
                        <span>{/* The words: */}
                          {c.subject}{" "}{/* the subject's name, */}
                          <span className="text-zinc-500">{/* grey details: */}
                            ({loaded.has(c.code) ? "already loaded" : `${c.skills.length} skills`}){/* "already loaded", or how many skills. */}
                          </span>{/* End of the details. */}
                        </span>{/* End of the words. */}
                      </label>{/* End of the line. */}
                    </li> // End of the list item.
                  ))}{/* End of the subjects loop. */}
                </ul>{/* End of the list. */}
              </fieldset> // End of the group.
            ))}{/* End of the areas loop. */}
          </div>{/* End of the scrolling box. */}
          <Button type="submit" disabled={pending || picked.length === 0}>{/* The button (greyed out while sending or with nothing ticked): */}
            {pending // while sending:
              ? "Loading…" // "Loading…",
              : `Load ${picked.length} subject${picked.length === 1 ? "" : "s"} (${skillCount.toLocaleString("en-AU")} skills)`}{/* otherwise how many subjects and skills it will load. */}
          </Button>{/* End of the button. */}
        </form> // End of the form.
      )}{/* End of the subjects part. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of AcaraImportForm.
