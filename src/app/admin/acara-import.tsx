"use client";

import { useActionState, useMemo, useState } from "react";
import { readSheet } from "read-excel-file/browser";
import { importAcara } from "@/app/actions/curriculum";
import { Button, FormMessage } from "@/components/ui";
import { ACARA_SHEET, parseAcara, type AcaraCurriculum } from "@/lib/acara";
import { initialFormState } from "@/lib/forms";

// Subjects ticked to start with: the ones CLG tutors most.
const CORE = new Set(["English", "Mathematics", "Science", "HASS F-6", "History 7-10", "Geography 7-10"]);

// Load many curricula at once from ACARA's "Download entire curriculum"
// Excel file. The file is read here in the browser; only the ticked
// subjects are sent, each as a draft for an admin to confirm.
export function AcaraImportForm({ loadedCodes }: { loadedCodes: string[] }) {
  const [state, formAction, pending] = useActionState(importAcara, initialFormState);
  const [curricula, setCurricula] = useState<AcaraCurriculum[]>([]);
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [readError, setReadError] = useState("");
  const [reading, setReading] = useState(false);
  const loaded = useMemo(() => new Set(loadedCodes), [loadedCodes]);

  async function readFile(file: File | undefined) {
    setReadError("");
    setCurricula([]);
    if (!file) return;
    setReading(true);
    try {
      const rows = await readSheet(file, ACARA_SHEET);
      const result = parseAcara(rows);
      if ("error" in result) {
        setReadError(result.error);
      } else {
        setCurricula(result);
        setChosen(new Set(result.filter((c) => CORE.has(c.subject) && !loaded.has(c.code)).map((c) => c.code)));
      }
    } catch {
      setReadError(
        'Couldn\'t read that file. Use the "Download entire curriculum" Excel file from australiancurriculum.edu.au/downloads.',
      );
    } finally {
      setReading(false);
    }
  }

  const byArea = new Map<string, AcaraCurriculum[]>();
  for (const c of curricula) byArea.set(c.learningArea, [...(byArea.get(c.learningArea) ?? []), c]);

  const toggle = (codes: string[], on: boolean) =>
    setChosen((prev) => {
      const next = new Set(prev);
      for (const code of codes) {
        if (on && !loaded.has(code)) next.add(code);
        else next.delete(code);
      }
      return next;
    });

  const picked = curricula.filter((c) => chosen.has(c.code));
  const payload = JSON.stringify(
    picked.map(({ code, name, subject, skills }) => ({ code, name, subject, skills })),
  );
  const skillCount = picked.reduce((n, c) => n + c.skills.length, 0);

  return (
    <div className="space-y-4">
      <ol className="list-decimal space-y-1 pl-5 text-sm text-zinc-700">
        <li>
          Go to{" "}
          <a
            href="https://www.australiancurriculum.edu.au/downloads"
            target="_blank"
            rel="noreferrer"
            className="text-teal-800 underline"
          >
            australiancurriculum.edu.au/downloads
          </a>{" "}
          and download the &quot;entire curriculum&quot; Excel file.
        </li>
        <li>Choose that file below, tick the subjects you want, and press Load.</li>
        <li>Each subject arrives as a draft. Check its summary, then confirm it.</li>
      </ol>

      <label className="block text-sm font-medium">
        ACARA curriculum file (.xlsx)
        <input
          type="file"
          accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          onChange={(e) => readFile(e.target.files?.[0])}
          className="mt-1 block w-full text-sm file:mr-3 file:rounded-full file:border-0 file:bg-teal-50 file:px-4 file:py-2 file:text-teal-800"
        />
      </label>
      {reading && <p className="text-sm text-zinc-600">Reading the file…</p>}
      {readError && <p className="text-sm text-red-700">{readError}</p>}

      {curricula.length > 0 && (
        <form action={formAction} className="space-y-4">
          <FormMessage state={state} />
          <input type="hidden" name="payload" value={payload} />
          <div className="flex flex-wrap gap-3 text-sm">
            <button type="button" className="text-teal-800 underline" onClick={() => toggle(curricula.map((c) => c.code), true)}>
              Tick all
            </button>
            <button type="button" className="text-teal-800 underline" onClick={() => setChosen(new Set())}>
              Untick all
            </button>
          </div>
          <div className="max-h-96 space-y-4 overflow-y-auto rounded-xl border border-zinc-200 p-4">
            {[...byArea.entries()].map(([area, list]) => (
              <fieldset key={area}>
                <legend className="mb-1 flex items-center gap-3 text-sm font-semibold">
                  {area}
                  <button
                    type="button"
                    className="text-xs font-normal text-teal-800 underline"
                    onClick={() => toggle(list.map((c) => c.code), !list.every((c) => chosen.has(c.code)))}
                  >
                    {list.every((c) => chosen.has(c.code)) ? "Untick these" : "Tick these"}
                  </button>
                </legend>
                <ul className="space-y-1">
                  {list.map((c) => (
                    <li key={c.code}>
                      <label className="flex items-start gap-2 text-sm">
                        <input
                          type="checkbox"
                          className="mt-1"
                          checked={chosen.has(c.code)}
                          disabled={loaded.has(c.code)}
                          onChange={(e) => toggle([c.code], e.target.checked)}
                        />
                        <span>
                          {c.subject}{" "}
                          <span className="text-zinc-500">
                            ({loaded.has(c.code) ? "already loaded" : `${c.skills.length} skills`})
                          </span>
                        </span>
                      </label>
                    </li>
                  ))}
                </ul>
              </fieldset>
            ))}
          </div>
          <Button type="submit" disabled={pending || picked.length === 0}>
            {pending
              ? "Loading…"
              : `Load ${picked.length} subject${picked.length === 1 ? "" : "s"} (${skillCount.toLocaleString("en-AU")} skills)`}
          </Button>
        </form>
      )}
    </div>
  );
}
