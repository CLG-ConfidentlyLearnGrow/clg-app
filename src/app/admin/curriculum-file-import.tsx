// Summary: the admin form for loading a curriculum from a spreadsheet file.
//
"use client"; // Runs in the browser, so the file can be read here before sending.

import { useActionState, useState } from "react"; // Lets the form remember its reply, the skills found, and any error.
import { readSheet } from "read-excel-file/browser"; // Reads Excel files in the browser.
import { importCurriculumFile } from "@/app/actions/curriculum"; // The server action that saves the draft curriculum.
import { Button, Field, FormMessage, TextArea } from "@/components/ui"; // The button, input box, reply message and larger text box.
import { splitCsvLine } from "@/lib/csv"; // Splits one line of a CSV file into columns.
import { parseCurriculumRows, type FileSkill } from "@/lib/curriculum-file"; // Turns the file's rows into skills, and the type of a skill.
import { initialFormState } from "@/lib/forms"; // The starting (empty) form reply.

// Load any curriculum (for example SACE for Years 11 and 12) from a
// spreadsheet in CLG's simple layout. The file is read here in the browser;
// the skills are sent as one draft for an admin to confirm.
export function CurriculumFileForm() {
  const [state, formAction, pending] = useActionState(importCurriculumFile, initialFormState); // The reply, the action to send, and whether it's sending.
  const [skills, setSkills] = useState<FileSkill[]>([]); // The skills found in the file.
  const [readError, setReadError] = useState(""); // Any problem reading the file.

  // Reads the chosen file into skills.
  async function readFile(file: File | undefined) {
    setReadError(""); // Clears any earlier problem,
    setSkills([]); // and any earlier skills.
    if (!file) return; // No file: stops.
    try { // Tries:
      const rows = /\.(csv|tsv|txt)$/i.test(file.name) // the rows: if it's a CSV or text file,
        ? (await file.text()) // reads it as text,
            .split(/\r?\n/) // splits it into lines,
            .filter((l) => l.trim()) // drops blank lines,
            .map(splitCsvLine) // and splits each line into columns;
        : await readSheet(file); // otherwise reads it as an Excel sheet.
      const result = parseCurriculumRows(rows); // Turns the rows into skills.
      if ("error" in result) setReadError(result.error); // A problem: shows it.
      else setSkills(result); // Otherwise keeps the skills.
    } catch { // If the file couldn't be read:
      setReadError("Couldn't read that file. Save it as Excel (.xlsx) or CSV and try again."); // asks for Excel or CSV.
    } // End of the try.
  } // End of readFile.

  const subjects = [...new Set(skills.map((s) => s.subject))]; // The different subjects found.
  const levels = [...new Set(skills.map((s) => s.level_band))]; // The different year levels found.

  return ( // Shows:
    <form action={formAction} className="space-y-4">{/* a form: */}
      <ol className="list-decimal space-y-1 pl-5 text-sm text-zinc-700">{/* a numbered list of steps: */}
        <li>{/* step: */}
          <a href="/templates/curriculum-template.csv" download className="text-teal-800 underline">{/* a link that downloads the template: */}
            Download the template{/* "Download the template", */}
          </a>{" "}{/* (end of the link and a space) */}
          and fill in one row per skill: code (optional), subject, year or level, the skill, and plain wording for
          parents (optional).{/* and what to fill in. */}
        </li>{/* (end of step) */}
        <li>Fill in the details below, choose your file, and press Load.</li>{/* Fill in the details and press Load. */}
        <li>It arrives as a draft. Check its summary, then confirm it.</li>{/* Check the draft, then confirm. */}
      </ol>{/* End of the list. */}
      <FormMessage state={state} />{/* The reply message (error or success). */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* Two columns on wider screens: */}
        <Field label="Name" name="name" required maxLength={200} hint="For example SACE Stage 1 and 2." />{/* its name, */}
        <Field label="Short code" name="code" required maxLength={30} hint="No spaces, for example SACE." />{/* a short code, */}
        <Field label="Version or year" name="version" required maxLength={40} hint="For example 2026." />{/* its version or year. */}
      </div>{/* End of the columns. */}
      <TextArea // The source box:
        label="Where it comes from" // its label,
        name="source" // its field name,
        rows={3} // three lines tall,
        required // that must be filled in,
        maxLength={1000} // up to 1,000 characters,
        hint="Who publishes it and how CLG may use it, for example the copyright owner and the date permission was given." // and a hint about permission.
      />{/* (end of the box) */}
      <label className="block text-sm font-medium">{/* A label: */}
        Curriculum file (.xlsx or .csv){/* "Curriculum file", */}
        <input // a file picker:
          type="file" // (a file)
          accept=".xlsx,.csv,.tsv,.txt,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" // that accepts Excel, CSV and text files,
          onChange={(e) => readFile(e.target.files?.[0])} // reads the file as soon as it's chosen,
          className="mt-1 block w-full text-sm file:mr-3 file:rounded-full file:border-0 file:bg-teal-50 file:px-4 file:py-2 file:text-teal-800" // styled with a soft button.
        />{/* (end of the picker) */}
      </label>{/* End of the label. */}
      {readError && <p className="text-sm text-red-700">{readError}</p>}{/* Any reading problem in red. */}
      {skills.length > 0 && ( // When skills are found:
        <p className="text-sm text-zinc-700">{/* a line: */}
          Found {skills.length.toLocaleString("en-AU")} skills in {subjects.length} subject{/* how many skills, in how many subject */}
          {subjects.length === 1 ? "" : "s"} ({subjects.slice(0, 6).join(", ")}{/* (s), naming up to six */}
          {subjects.length > 6 ? ", …" : ""}) across {levels.join(", ")}.{/* (and "…" for more), and the year levels. */}
        </p> // End of the line.
      )}{/* End of the summary. */}
      <input type="hidden" name="payload" value={JSON.stringify(skills)} />{/* The skills, sent as hidden data. */}
      <Button type="submit" disabled={pending || skills.length === 0}>{/* The button (greyed out while sending or with no skills): */}
        {pending ? "Loading…" : "Load curriculum"}{/* its words change while sending. */}
      </Button>{/* End of the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of CurriculumFileForm.
