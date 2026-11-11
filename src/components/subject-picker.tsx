// Summary: the subject chooser used on the child and student forms. School
// students tick subjects and pick the level they work at in each; university
// and TAFE students name each unit with its code and link instead.
//
"use client"; // Marks this file as code that runs in the browser.

import { useEffect, useRef, useState } from "react"; // React's tools: run code after showing, point at an element, and remember choices.
import { SUBJECT_SUGGESTIONS, YEAR_LEVELS, YEAR_LEVEL_NAMES, subjectsFor } from "@/lib/students"; // The subject lists, year levels, their names, and which subjects suit a year.

export type ChosenSubject = { subject: string; level: string | null; course_code?: string | null; course_url?: string | null }; // One chosen subject: name, level (or none), and for university units a code and link.

// University or TAFE students (and adult learners) name their units instead.
const TERTIARY = new Set(["University or TAFE", "Adult learner"]); // Year levels that name units instead of ticking subjects.
type Unit = { subject: string; code: string; url: string }; // One university or TAFE unit as typed: name, code and link.

const inputClass = // The look of the text boxes:
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"; // rounded, bordered, white, bronze outline when in use.

// Tick one or more subjects and, for each, the level the child is working
// at (which can differ from their school year), or "Not sure". Sent to the
// server as one hidden field, "subjects_json". The list follows the year
// level chosen in the same form (Foundation to Year 10, or Years 11 and 12),
// or the yearLevel given. University and TAFE students instead name each
// unit, with its code and a link, plus their degree ("program").
export function SubjectPicker({
  chosen = [], // Subjects already chosen (none by default).
  yearLevel = null, // The year level, if known (none by default).
  program = "", // The degree name, if known (blank by default).
}: { // The settings' types:
  chosen?: ChosenSubject[]; // chosen is a list,
  yearLevel?: string | null; // year level is text or nothing,
  program?: string; // degree is text.
}) { // End of the settings.
  const box = useRef<HTMLFieldSetElement>(null); // Points at this chooser's box, so the form around it can be found.
  const [year, setYear] = useState<string | null>(yearLevel); // The year level the list follows (starts as the given one).
  useEffect(() => { // After showing, follows the form's year level drop-down:
    const select = box.current?.closest("form")?.querySelector<HTMLSelectElement>('select[name="year_level"]'); // finds the year level drop-down in the same form,
    if (!select) return; // none: nothing to follow.
    const read = () => setYear(select.value || yearLevel); // Reads its value (or the given year level if blank).
    read(); // Reads it once now.
    select.addEventListener("change", read); // Reads it again every time it changes.
    return () => select.removeEventListener("change", read); // Stops listening when the chooser goes away.
  }, [yearLevel]); // Redoes this if the given year level changes.
  const shown = subjectsFor(year); // The subjects to show for this year.
  const listed = new Set<string>(SUBJECT_SUGGESTIONS.map((s) => s.toLowerCase())); // Every listed subject in lower case, to spot typed-in ones.
  const [picked, setPicked] = useState<Map<string, string>>( // The ticked subjects and their levels, starting from:
    () => // (worked out once)
      new Map( // a lookup of:
        chosen // the chosen subjects,
          .filter((c) => listed.has(c.subject.toLowerCase())) // that are on the list,
          .map((c) => [SUBJECT_SUGGESTIONS.find((s) => s.toLowerCase() === c.subject.toLowerCase())!, c.level ?? ""]), // each by its listed spelling, with its level (blank for "not sure").
      ), // End of the lookup.
  ); // End of the starting value.
  const [others, setOthers] = useState<{ subject: string; level: string }[]>(() => { // The typed-in "other" subjects, starting from:
    const rows = chosen // the chosen subjects:
      .filter((c) => !listed.has(c.subject.toLowerCase())) // not on the list,
      .map((c) => ({ subject: c.subject, level: c.level ?? "" })); // as name and level.
    return rows.length > 0 ? rows : [{ subject: "", level: "" }]; // Those, or one empty row to type in.
  }); // End of the starting value.

  const [units, setUnits] = useState<Unit[]>(() => { // The university units, starting from:
    const rows = chosen.map((c) => ({ subject: c.subject, code: c.course_code ?? "", url: c.course_url ?? "" })); // every chosen subject as a unit, with its code and link.
    return rows.length > 0 ? rows : [{ subject: "", code: "", url: "" }]; // Those, or one empty row.
  }); // End of the starting value.
  const tertiary = year !== null && TERTIARY.has(year); // True for university, TAFE and adult learners.

  const value = JSON.stringify( // The hidden field's value, as JSON text:
    tertiary // for university students:
      ? units // the units:
          .filter((u) => u.subject.trim()) // with a name,
          .map((u) => ({ subject: u.subject.trim(), level: year, course_code: u.code.trim(), course_url: u.url.trim() })) // as name, year level, code and link.
      : [ // otherwise:
          ...[...picked].map(([subject, level]) => ({ subject, level: level || null })), // each ticked subject with its level (blank becomes "not sure"),
          ...others.filter((o) => o.subject.trim()).map((o) => ({ subject: o.subject.trim(), level: o.level || null })), // and each typed-in subject with a name, with its level.
        ], // End of the list.
  ); // End of the value.

  if (tertiary) { // University, TAFE and adult learners see the units form:
    const setUnit = (i: number, change: Partial<Unit>) => // Helper to change one unit's details:
      setUnits((prev) => prev.map((u, j) => (j === i ? { ...u, ...change } : u))); // replaces just that unit with the changes.
    return ( // Shows:
      <fieldset ref={box} className="space-y-3">{/* a group box: */}
        <legend className="text-sm font-medium">Course and units to get help with</legend>{/* titled "Course and units to get help with", */}
        <input type="hidden" name="subjects_json" value={value} />{/* the hidden field sent to the server, */}
        <label className="block space-y-1 text-sm">{/* a labelled box: */}
          <span className="font-medium">Degree or course (optional)</span>{/* "Degree or course (optional)", */}
          <input // the degree text box:
            name="program" // named "program",
            maxLength={300} // up to 300 letters,
            defaultValue={program} // starting with the known degree,
            placeholder="For example: Bachelor of Engineering (Civil)(Honours)" // with an example shown in grey,
            className={inputClass} // in the text box look.
          />{/* (end of the text box) */}
        </label>{/* End of the label. */}
        {/* A note about what to add for each unit. */}
        <p className="text-xs text-zinc-500">{/* (small grey text) */}
          Add each unit (subject) you want help with. The unit code and a link to the course page help the tutor read
          about it before the first session.{/* (end of the note's words) */}
        </p>{/* End of the note. */}
        {units.map((u, i) => ( // For each unit:
          <div key={i} className="space-y-2 rounded-lg border border-zinc-200 p-3">{/* a bordered box: */}
            <input // the unit name box:
              aria-label="Unit name" // named "Unit name" for screen readers,
              placeholder="Unit name, for example Water Engineering Hydraulics and Modelling" // with an example,
              maxLength={100} // up to 100 letters,
              value={u.subject} // showing the typed name,
              onChange={(e) => setUnit(i, { subject: e.target.value })} // saving each change,
              className={inputClass} // in the text box look.
            />{/* (end of the box) */}
            <div className="flex flex-wrap gap-2">{/* a row: */}
              <input // the unit code box:
                aria-label="Unit code" // named for screen readers,
                placeholder="Unit code, for example ENGC 3000" // with an example,
                maxLength={40} // up to 40 letters,
                value={u.code} // showing the typed code,
                onChange={(e) => setUnit(i, { code: e.target.value })} // saving each change,
                className={`${inputClass} max-w-56`} // narrower.
              />{/* (end of the box) */}
              <input // the course link box:
                aria-label="Link to the course page" // named for screen readers,
                placeholder="Link to the course page (https://…)" // with an example,
                type="url" // for web addresses,
                maxLength={500} // up to 500 letters,
                value={u.url} // showing the typed link,
                onChange={(e) => setUnit(i, { url: e.target.value })} // saving each change,
                className={`${inputClass} min-w-56 flex-1`} // taking the rest of the row.
              />{/* (end of the box) */}
            </div>{/* End of the row. */}
          </div> // End of the unit's box.
        ))}{/* End of the loop. */}
        {units.length < 10 && ( // Fewer than 10 units:
          <button // a button:
            type="button" // that doesn't send any form,
            className="text-sm text-teal-800 underline hover:font-bold" // styled like a link,
            onClick={() => setUnits((prev) => [...prev, { subject: "", code: "", url: "" }])} // that adds an empty unit row.
          >{/* (end of the button's settings) */}
            Add another unit{/* The button's words. */}
          </button> // End of the button.
        )}{/* End of the add button. */}
      </fieldset> // End of the group box.
    ); // End of what's shown.
  } // End of the units form.

  const toggle = (s: string, on: boolean) => // Ticks or unticks a subject:
    setPicked((prev) => { // updates the ticked list:
      const next = new Map(prev); // copies it,
      if (on) next.set(s, ""); // ticked: adds the subject as "not sure",
      else next.delete(s); // unticked: removes it,
      return next; // and saves the copy.
    }); // End of toggle.

  return ( // School students see:
    <fieldset ref={box} className="space-y-2">{/* a group box: */}
      <legend className="text-sm font-medium">Subjects to get help with</legend>{/* titled "Subjects to get help with", */}
      {/* A note explaining levels. */}
      <p className="text-xs text-zinc-500">{/* (small grey text) */}
        Tick each subject, then choose the level your child is working at in it. This can be different from their
        school year. If you&apos;re not sure, leave it as &quot;Not sure&quot;; the tutor will check in the first
        sessions.{/* (end of the note's words) */}
      </p>{/* End of the note. */}
      <input type="hidden" name="subjects_json" value={value} />{/* The hidden field sent to the server. */}
      <ul className="space-y-1">{/* A list: */}
        {[...shown, ...[...picked.keys()].filter((p) => !shown.includes(p))].map((s) => ( // of this year's subjects, plus any ticked ones not on it:
          <li key={s} className="flex flex-wrap items-center gap-x-3 gap-y-1">{/* each in a row: */}
            <label className="flex min-w-48 items-center gap-2 text-sm">{/* a label: */}
              <input type="checkbox" checked={picked.has(s)} onChange={(e) => toggle(s, e.target.checked)} />{/* the tick box, ticked if chosen, saving each change, */}
              {s}{/* the subject's name. */}
            </label>{/* End of the label. */}
            {picked.has(s) && ( // If ticked:
              <LevelSelect // its level drop-down:
                label={`Level for ${s}`} // named for screen readers,
                value={picked.get(s) ?? ""} // showing its level,
                onChange={(level) => setPicked((prev) => new Map(prev).set(s, level))} // saving the chosen level.
              /> // (end of the drop-down)
            )}{/* End of the level. */}
          </li> // End of the row.
        ))}{/* End of the loop. */}
      </ul>{/* End of the list. */}
      <div className="space-y-2 pt-2">{/* The "other subjects" area: */}
        <p className="text-sm font-medium">Other subjects (optional)</p>{/* its heading, */}
        {others.map((o, i) => ( // for each typed-in subject:
          <div key={i} className="flex flex-wrap items-center gap-2">{/* a row: */}
            <input // a text box:
              aria-label="Other subject" // named for screen readers,
              placeholder="Subject" // with "Subject" shown in grey,
              maxLength={100} // up to 100 letters,
              value={o.subject} // showing the typed name,
              onChange={(e) => setOthers((prev) => prev.map((p, j) => (j === i ? { ...p, subject: e.target.value } : p)))} // saving each change to just this row,
              className={`${inputClass} max-w-xs`} // narrower.
            />{/* (end of the box) */}
            {o.subject.trim() && ( // Once a name is typed:
              <LevelSelect // its level drop-down:
                label={`Level for ${o.subject}`} // named for screen readers,
                value={o.level} // showing its level,
                onChange={(level) => setOthers((prev) => prev.map((p, j) => (j === i ? { ...p, level } : p)))} // saving the chosen level to just this row.
              /> // (end of the drop-down)
            )}{/* End of the level. */}
          </div> // End of the row.
        ))}{/* End of the loop. */}
        {others.length < 3 && ( // Fewer than 3 typed-in rows:
          <button // a button:
            type="button" // that doesn't send any form,
            className="text-sm text-teal-800 underline hover:font-bold" // styled like a link,
            onClick={() => setOthers((prev) => [...prev, { subject: "", level: "" }])} // that adds an empty row.
          >{/* (end of the button's settings) */}
            Add another subject{/* The button's words. */}
          </button> // End of the button.
        )}{/* End of the add button. */}
      </div>{/* End of the "other subjects" area. */}
    </fieldset> // End of the group box.
  ); // End of what's shown.
} // End of SubjectPicker.

// The drop-down for the level a child works at in one subject.
function LevelSelect({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return ( // Shows:
    <select aria-label={label} value={value} onChange={(e) => onChange(e.target.value)} className={`${inputClass} w-auto`}>{/* the drop-down, named for screen readers, passing each choice back, in the text box look, */}
      <option value="">Not sure</option>{/* a "Not sure" choice, */}
      {YEAR_LEVELS.map((y) => ( // then for each year level:
        <option key={y} value={y}>{/* a choice: */}
          Working at {YEAR_LEVEL_NAMES[y]}{/* e.g. "Working at Year 5". */}
        </option> // End of the choice.
      ))}{/* End of the loop. */}
    </select> // End of the drop-down.
  ); // End of what's shown.
} // End of LevelSelect.
