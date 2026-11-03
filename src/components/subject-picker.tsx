"use client";

import { useEffect, useRef, useState } from "react";
import { SUBJECT_SUGGESTIONS, YEAR_LEVELS, YEAR_LEVEL_NAMES, subjectsFor } from "@/lib/students";

export type ChosenSubject = { subject: string; level: string | null; course_code?: string | null; course_url?: string | null };

// University or TAFE students (and adult learners) name their units instead.
const TERTIARY = new Set(["University or TAFE", "Adult learner"]);
type Unit = { subject: string; code: string; url: string };

const inputClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none";

// Tick one or more subjects and, for each, the level the child is working
// at (which can differ from their school year), or "Not sure". Sent to the
// server as one hidden field, "subjects_json". The list follows the year
// level chosen in the same form (Foundation to Year 10, or Years 11 and 12),
// or the yearLevel given. University and TAFE students instead name each
// unit, with its code and a link, plus their degree ("program").
export function SubjectPicker({
  chosen = [],
  yearLevel = null,
  program = "",
}: {
  chosen?: ChosenSubject[];
  yearLevel?: string | null;
  program?: string;
}) {
  const box = useRef<HTMLFieldSetElement>(null);
  const [year, setYear] = useState<string | null>(yearLevel);
  useEffect(() => {
    const select = box.current?.closest("form")?.querySelector<HTMLSelectElement>('select[name="year_level"]');
    if (!select) return;
    const read = () => setYear(select.value || yearLevel);
    read();
    select.addEventListener("change", read);
    return () => select.removeEventListener("change", read);
  }, [yearLevel]);
  const shown = subjectsFor(year);
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

  const [units, setUnits] = useState<Unit[]>(() => {
    const rows = chosen.map((c) => ({ subject: c.subject, code: c.course_code ?? "", url: c.course_url ?? "" }));
    return rows.length > 0 ? rows : [{ subject: "", code: "", url: "" }];
  });
  const tertiary = year !== null && TERTIARY.has(year);

  const value = JSON.stringify(
    tertiary
      ? units
          .filter((u) => u.subject.trim())
          .map((u) => ({ subject: u.subject.trim(), level: year, course_code: u.code.trim(), course_url: u.url.trim() }))
      : [
          ...[...picked].map(([subject, level]) => ({ subject, level: level || null })),
          ...others.filter((o) => o.subject.trim()).map((o) => ({ subject: o.subject.trim(), level: o.level || null })),
        ],
  );

  if (tertiary) {
    const setUnit = (i: number, change: Partial<Unit>) =>
      setUnits((prev) => prev.map((u, j) => (j === i ? { ...u, ...change } : u)));
    return (
      <fieldset ref={box} className="space-y-3">
        <legend className="text-sm font-medium">Course and units to get help with</legend>
        <input type="hidden" name="subjects_json" value={value} />
        <label className="block space-y-1 text-sm">
          <span className="font-medium">Degree or course (optional)</span>
          <input
            name="program"
            maxLength={300}
            defaultValue={program}
            placeholder="For example: Bachelor of Engineering (Civil)(Honours)"
            className={inputClass}
          />
        </label>
        <p className="text-xs text-zinc-500">
          Add each unit (subject) you want help with. The unit code and a link to the course page help the tutor read
          about it before the first session.
        </p>
        {units.map((u, i) => (
          <div key={i} className="space-y-2 rounded-lg border border-zinc-200 p-3">
            <input
              aria-label="Unit name"
              placeholder="Unit name, for example Water Engineering Hydraulics and Modelling"
              maxLength={100}
              value={u.subject}
              onChange={(e) => setUnit(i, { subject: e.target.value })}
              className={inputClass}
            />
            <div className="flex flex-wrap gap-2">
              <input
                aria-label="Unit code"
                placeholder="Unit code, for example ENGC 3000"
                maxLength={40}
                value={u.code}
                onChange={(e) => setUnit(i, { code: e.target.value })}
                className={`${inputClass} max-w-56`}
              />
              <input
                aria-label="Link to the course page"
                placeholder="Link to the course page (https://…)"
                type="url"
                maxLength={500}
                value={u.url}
                onChange={(e) => setUnit(i, { url: e.target.value })}
                className={`${inputClass} min-w-56 flex-1`}
              />
            </div>
          </div>
        ))}
        {units.length < 10 && (
          <button
            type="button"
            className="text-sm text-teal-800 underline hover:font-bold"
            onClick={() => setUnits((prev) => [...prev, { subject: "", code: "", url: "" }])}
          >
            Add another unit
          </button>
        )}
      </fieldset>
    );
  }

  const toggle = (s: string, on: boolean) =>
    setPicked((prev) => {
      const next = new Map(prev);
      if (on) next.set(s, "");
      else next.delete(s);
      return next;
    });

  return (
    <fieldset ref={box} className="space-y-2">
      <legend className="text-sm font-medium">Subjects to get help with</legend>
      <p className="text-xs text-zinc-500">
        Tick each subject, then choose the level your child is working at in it. This can be different from their
        school year. If you&apos;re not sure, leave it as &quot;Not sure&quot;; the tutor will check in the first
        sessions.
      </p>
      <input type="hidden" name="subjects_json" value={value} />
      <ul className="space-y-1">
        {[...shown, ...[...picked.keys()].filter((p) => !shown.includes(p))].map((s) => (
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
