"use client";

import { useActionState, useState } from "react";
import { readSheet } from "read-excel-file/browser";
import { importCurriculumFile } from "@/app/actions/curriculum";
import { Button, Field, FormMessage, TextArea } from "@/components/ui";
import { splitCsvLine } from "@/lib/csv";
import { parseCurriculumRows, type FileSkill } from "@/lib/curriculum-file";
import { initialFormState } from "@/lib/forms";

// Load any curriculum (for example SACE for Years 11 and 12) from a
// spreadsheet in CLG's simple layout. The file is read here in the browser;
// the skills are sent as one draft for an admin to confirm.
export function CurriculumFileForm() {
  const [state, formAction, pending] = useActionState(importCurriculumFile, initialFormState);
  const [skills, setSkills] = useState<FileSkill[]>([]);
  const [readError, setReadError] = useState("");

  async function readFile(file: File | undefined) {
    setReadError("");
    setSkills([]);
    if (!file) return;
    try {
      const rows = /\.(csv|tsv|txt)$/i.test(file.name)
        ? (await file.text())
            .split(/\r?\n/)
            .filter((l) => l.trim())
            .map(splitCsvLine)
        : await readSheet(file);
      const result = parseCurriculumRows(rows);
      if ("error" in result) setReadError(result.error);
      else setSkills(result);
    } catch {
      setReadError("Couldn't read that file. Save it as Excel (.xlsx) or CSV and try again.");
    }
  }

  const subjects = [...new Set(skills.map((s) => s.subject))];
  const levels = [...new Set(skills.map((s) => s.level_band))];

  return (
    <form action={formAction} className="space-y-4">
      <ol className="list-decimal space-y-1 pl-5 text-sm text-zinc-700">
        <li>
          <a href="/templates/curriculum-template.csv" download className="text-teal-800 underline">
            Download the template
          </a>{" "}
          and fill in one row per skill: code (optional), subject, year or level, the skill, and plain wording for
          parents (optional).
        </li>
        <li>Fill in the details below, choose your file, and press Load.</li>
        <li>It arrives as a draft. Check its summary, then confirm it.</li>
      </ol>
      <FormMessage state={state} />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="Name" name="name" required maxLength={200} hint="For example SACE Stage 1 and 2." />
        <Field label="Short code" name="code" required maxLength={30} hint="No spaces, for example SACE." />
        <Field label="Version or year" name="version" required maxLength={40} hint="For example 2026." />
      </div>
      <TextArea
        label="Where it comes from"
        name="source"
        rows={3}
        required
        maxLength={1000}
        hint="Who publishes it and how CLG may use it, for example the copyright owner and the date permission was given."
      />
      <label className="block text-sm font-medium">
        Curriculum file (.xlsx or .csv)
        <input
          type="file"
          accept=".xlsx,.csv,.tsv,.txt,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          onChange={(e) => readFile(e.target.files?.[0])}
          className="mt-1 block w-full text-sm file:mr-3 file:rounded-full file:border-0 file:bg-teal-50 file:px-4 file:py-2 file:text-teal-800"
        />
      </label>
      {readError && <p className="text-sm text-red-700">{readError}</p>}
      {skills.length > 0 && (
        <p className="text-sm text-zinc-700">
          Found {skills.length.toLocaleString("en-AU")} skills in {subjects.length} subject
          {subjects.length === 1 ? "" : "s"} ({subjects.slice(0, 6).join(", ")}
          {subjects.length > 6 ? ", …" : ""}) across {levels.join(", ")}.
        </p>
      )}
      <input type="hidden" name="payload" value={JSON.stringify(skills)} />
      <Button type="submit" disabled={pending || skills.length === 0}>
        {pending ? "Loading…" : "Load curriculum"}
      </Button>
    </form>
  );
}
