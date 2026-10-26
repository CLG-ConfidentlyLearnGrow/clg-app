"use client";

import { useState } from "react";
import { SUBJECT_SUGGESTIONS, YEAR_LEVELS, YEAR_LEVEL_NAMES } from "@/lib/students";

export type ChosenSubject = { subject: string; level: string | null };

const inputClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none";

// Tick one or more subjects and, for each, the level the child is working
// at (which can differ from their school year), or "Not sure". Sent to the
// server as one hidden field, "subjects_json".
export function SubjectPicker({ chosen = [] }: { chosen?: ChosenSubject[] }) {
  const listed = new Set<string>(SUBJECT_SUGGESTIONS.map((s) => s.toLowerCase()));
  const [picked, setPicked] = useState<Map<string, string>>(
    () =>
      new Map(
        chosen
          .filter((c) => listed.has(c.subject.toLowerCase()))
          .map((c) => [SUBJECT_SUGGESTIONS.find((s) => s.toLowerCase() === c.subject.toLowerCase())!, c.level ?? ""]),
      ),
  );
  const [others, setOthers] = useState<{ subject: string; level: string }[]>(() => {
    const rows = chosen
      .filter((c) => !listed.has(c.subject.toLowerCase()))
      .map((c) => ({ subject: c.subject, level: c.level ?? "" }));
    return rows.length > 0 ? rows : [{ subject: "", level: "" }];
  });

  const value = JSON.stringify([
    ...[...picked].map(([subject, level]) => ({ subject, level: level || null })),
    ...others.filter((o) => o.subject.trim()).map((o) => ({ subject: o.subject.trim(), level: o.level || null })),
  ]);

  const toggle = (s: string, on: boolean) =>
    setPicked((prev) => {
      const next = new Map(prev);
      if (on) next.set(s, "");
      else next.delete(s);
      return next;
    });

  return (
    <fieldset className="space-y-2">
      <legend className="text-sm font-medium">Subjects to get help with</legend>
      <p className="text-xs text-zinc-500">
        Tick each subject, then choose the level your child is working at in it. This can be different from their
        school year. If you&apos;re not sure, leave it as &quot;Not sure&quot;; the tutor will check in the first
        sessions.
      </p>
      <input type="hidden" name="subjects_json" value={value} />
      <ul className="space-y-1">
        {SUBJECT_SUGGESTIONS.map((s) => (
          <li key={s} className="flex flex-wrap items-center gap-x-3 gap-y-1">
            <label className="flex min-w-48 items-center gap-2 text-sm">
              <input type="checkbox" checked={picked.has(s)} onChange={(e) => toggle(s, e.target.checked)} />
              {s}
            </label>
            {picked.has(s) && (
              <LevelSelect
                label={`Level for ${s}`}
                value={picked.get(s) ?? ""}
                onChange={(level) => setPicked((prev) => new Map(prev).set(s, level))}
              />
            )}
          </li>
        ))}
      </ul>
      <div className="space-y-2 pt-2">
        <p className="text-sm font-medium">Other subjects (optional)</p>
        {others.map((o, i) => (
          <div key={i} className="flex flex-wrap items-center gap-2">
            <input
              aria-label="Other subject"
              placeholder="Subject"
              maxLength={100}
              value={o.subject}
              onChange={(e) => setOthers((prev) => prev.map((p, j) => (j === i ? { ...p, subject: e.target.value } : p)))}
              className={`${inputClass} max-w-xs`}
            />
            {o.subject.trim() && (
              <LevelSelect
                label={`Level for ${o.subject}`}
                value={o.level}
                onChange={(level) => setOthers((prev) => prev.map((p, j) => (j === i ? { ...p, level } : p)))}
              />
            )}
          </div>
        ))}
        {others.length < 3 && (
          <button
            type="button"
            className="text-sm text-teal-800 underline hover:font-bold"
            onClick={() => setOthers((prev) => [...prev, { subject: "", level: "" }])}
          >
            Add another subject
          </button>
        )}
      </div>
    </fieldset>
  );
}

function LevelSelect({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <select aria-label={label} value={value} onChange={(e) => onChange(e.target.value)} className={`${inputClass} w-auto`}>
      <option value="">Not sure</option>
      {YEAR_LEVELS.map((y) => (
        <option key={y} value={y}>
          Working at {YEAR_LEVEL_NAMES[y]}
        </option>
      ))}
    </select>
  );
}
