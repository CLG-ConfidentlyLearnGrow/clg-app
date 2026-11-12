"use client"; // Marks this file as code that runs in the browser.

// Forms for the 2 Nov 2026 scheduling changes: study periods, requests,
// public holidays, blocking and libraries.

import { useState } from "react"; // React tool to remember a value on the page.
import { // The scheduling actions these forms send to:
  addLibraryHours, // add a library's opening hours,
  addOwnTerm, // add the family's own study dates,
  blockMatch, // block a tutor-student pair,
  closeSessionRequest, // close a request,
  confirmLibrary, // confirm a library,
  makeSessionRequest, // make a request,
  offerOneOff, // offer a one-off session,
  recordBlockFollowUp, // record a block follow-up,
  setSkipPublicHolidays, // skip public holidays (or not),
  setStudyPeriod, // choose a study period,
  setTerm4LastDay, // set the last day of Term 4,
  suggestLibrary, // suggest a library,
  loadSaLibraries, // load all SA libraries,
  fillHoursFromOsm, // fill a library's hours from OpenStreetMap,
  setSummaryMinutes, // set the summary time after each session,
  setQuietHours, // set CLG's quiet hours.
} from "@/app/actions/scheduling-extra"; // End of the list.
import { ActionForm } from "@/components/action-form"; // A shared form that shows a save button and messages.
import { Field, Select, TextArea } from "@/components/ui"; // Shared page parts: a field, a drop-down and a text area.

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]; // Short weekday names, Monday first.
const box = "flex items-start gap-2 text-sm"; // The style for a tick box line.

// ---------------------------------------------------------------------------
// Study periods
// ---------------------------------------------------------------------------
export function StudyPeriodForm({ studentId, calendar }: { studentId: string; calendar: string }) { // The "study period" form for a student.
  return ( // Shows:
    <ActionForm action={setStudyPeriod} submitLabel="Save study period">{/* the form, saving with setStudyPeriod: */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <Select label="Study period" name="calendar" defaultValue={calendar}>{/* the study period drop-down: */}
        <option value="public">South Australian government school terms</option>{/* government school terms, */}
        <option value="private">South Australian private school terms (an extra week off between Terms 2 and 3)</option>{/* private school terms, */}
        <option value="own">My own dates (university, TAFE or other study)</option>{/* their own dates. */}
      </Select>{/* End of the drop-down. */}
      <p className="text-xs text-zinc-600">{/* a help line: */}
        Next-term questions, holiday sessions and term reviews follow these dates.{/* what follows these dates. */}
      </p>{/* End of the help line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of StudyPeriodForm.

export function OwnTermForm({ studentId }: { studentId: string }) { // The "add our own study dates" form.
  return ( // Shows:
    <ActionForm action={addOwnTerm} submitLabel="Add study dates">{/* the form, saving with addOwnTerm: */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <Field label="Name (optional)" name="label" maxLength={100} placeholder="For example: Semester 1 2027" />{/* an optional name, */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label="First day" name="starts_on" type="date" required />{/* the first day, */}
        <Field label="Last day" name="ends_on" type="date" required />{/* the last day. */}
      </div>{/* End of the columns. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of OwnTermForm.

export function Term4LastDayForm({ studentId, current }: { studentId: string; current: string }) { // The "last day of Term 4" form.
  return ( // Shows:
    <ActionForm action={setTerm4LastDay} submitLabel="Save last day">{/* the form, saving with setTerm4LastDay: */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <Field // the date box:
        label="Last day of school in Term 4" // its label,
        name="last_day" // its name for the action,
        type="date" // a date,
        defaultValue={current} // filled with the current date,
        required // must be filled in,
        hint="This changes from school to school and by year level (Year 12s often finish early)." // a help hint.
      />{/* End of the box. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of Term4LastDayForm.

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------
type Child = { id: string; name: string; subjects: string[] }; // A child: id, name and their subjects.

export function SessionRequestForm({ students, today }: { students: Child[]; today: string }) { // The "ask for a session" form for families.
  const [kind, setKind] = useState("extra"); // Which kind of request is chosen (extra to start).
  const [student, setStudent] = useState(students[0]?.id ?? ""); // Which child is chosen (the first to start).
  const subjects = students.find((s) => s.id === student)?.subjects ?? []; // That child's subjects.
  return ( // Shows:
    <ActionForm action={makeSessionRequest} submitLabel="Send request">{/* the form, saving with makeSessionRequest: */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="Child" name="student_id" value={student} onChange={(e) => setStudent(e.target.value)}>{/* the child drop-down (changing it updates the subjects): */}
          {students.map((s) => ( // for each child:
            <option key={s.id} value={s.id}>{/* an option: */}
              {s.name}{/* their name, */}
            </option> // end of the option.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <Select label="Subject" name="subject" defaultValue={subjects[0] ?? ""} key={student} required>{/* the subject drop-down (reset when the child changes): */}
          {subjects.map((s) => ( // for each subject:
            <option key={s} value={s}>{/* an option: */}
              {s}{/* its name, */}
            </option> // end of the option.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
      </div>{/* End of the columns. */}
      <Select label="What would you like?" name="kind" value={kind} onChange={(e) => setKind(e.target.value)}>{/* the kind of request drop-down: */}
        <option value="extra">An extra session before a test, exam or other big event</option>{/* an extra session before an event, */}
        <option value="public_holiday">A one-off at another time in a public holiday week</option>{/* a one-off in a public holiday week, */}
        <option value="away_cover">Another time or tutor while our tutor is away</option>{/* cover while the tutor is away. */}
      </Select>{/* End of the drop-down. */}
      {kind === "extra" && ( // For an extra session:
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns: */}
          <Field label="Date of the event" name="event_on" type="date" min={today} required />{/* the event's date (today or later), */}
          <Field label="What is it?" name="event_label" maxLength={200} placeholder="For example: algebra test" />{/* what the event is. */}
        </div> // End of the columns.
      )}{/* End of this part. */}
      {kind === "public_holiday" && <Field label="Public holiday date" name="event_on" type="date" min={today} />}{/* For a public holiday: the holiday's date. */}
      {kind === "away_cover" && ( // For cover while away:
        <>{/* (a group) */}
          <Field label="Date of the cancelled session" name="event_on" type="date" min={today} />{/* the cancelled session's date, */}
          <Select label="We'd like" name="wants" defaultValue="either">{/* what they'd like: */}
            <option value="time">Another time with our tutor</option>{/* another time with their tutor, */}
            <option value="tutor">A different tutor at our usual time</option>{/* a different tutor at the usual time, */}
            <option value="either">Either is fine</option>{/* either. */}
          </Select>{/* End of the drop-down. */}
        </> // End of the group.
      )}{/* End of this part. */}
      <TextArea label="Times that suit, or anything else (optional)" name="note" maxLength={1000} rows={2} />{/* a note box for times that suit. */}
      <p className="text-xs text-zinc-600">{/* a help line: */}
        Your tutor or CLG will offer a time if one is available. A one-off session is charged at the usual hourly rate.{/* what happens next and the cost. */}
      </p>{/* End of the help line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SessionRequestForm.

export function OfferOneOffForm({ // The "offer a one-off time" form, given:
  requestId, // the request,
  isAdmin, // whether the person is an admin,
  tutors, // the tutors to choose from,
  libraries, // the libraries,
  today, // today's date,
  before, // and the latest date allowed (if any).
}: { // The types of those:
  requestId: string; // the request's id,
  isAdmin: boolean; // admin or not,
  tutors: { id: string; name: string }[]; // tutors' ids and names,
  libraries: { id: string; name: string }[]; // libraries' ids and names,
  today: string; // today's date,
  before: string | null; // the latest date (or none).
}) { // End of the types.
  const [delivery, setDelivery] = useState("online"); // Where the session is (online to start).
  return ( // Shows:
    <ActionForm action={offerOneOff} submitLabel="Offer this time">{/* the form, saving with offerOneOff: */}
      <input type="hidden" name="request_id" value={requestId} />{/* the request (hidden), */}
      {isAdmin && tutors.length > 0 && ( // For an admin with tutors to choose from:
        <Select label="Tutor" name="tutor_id" defaultValue={tutors[0].id}>{/* the tutor drop-down: */}
          {tutors.map((t) => ( // for each tutor:
            <option key={t.id} value={t.id}>{/* an option: */}
              {t.name}{/* their name, */}
            </option> // end of the option.
          ))}{/* End of the loop. */}
        </Select> // End of the drop-down.
      )}{/* End of this part. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">{/* three columns on wider screens: */}
        <Field label="Date" name="date" type="date" min={today} max={before ?? undefined} required />{/* the date (between today and the latest date), */}
        <Field label="Start" name="start_time" type="time" required />{/* the start time, */}
        <Select label="Length" name="minutes" defaultValue="60">{/* the length drop-down: */}
          {[60, 90, 120].map((m) => ( // for 1, 1.5 and 2 hr:
            <option key={m} value={m}>{/* an option: */}
              {m === 60 ? "1 hr" : `${m / 60} hr`}{/* its length in hours, */}
            </option> // end of the option.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
      </div>{/* End of the columns. */}
      <Select label="Where" name="delivery" value={delivery} onChange={(e) => setDelivery(e.target.value)}>{/* the "Where" drop-down: */}
        <option value="online">Online</option>{/* online, */}
        <option value="library">At a library</option>{/* at a library, */}
        {isAdmin && <option value="home">At home (special circumstances)</option>}{/* at home (admins only), */}
        {isAdmin && <option value="school">At school (special circumstances)</option>}{/* at school (admins only). */}
      </Select>{/* End of the drop-down. */}
      {delivery === "library" && ( // For a library session:
        <Select label="Library" name="library_id" required>{/* the library drop-down: */}
          {libraries.map((l) => ( // for each library:
            <option key={l.id} value={l.id}>{/* an option: */}
              {l.name}{/* its name, */}
            </option> // end of the option.
          ))}{/* End of the loop. */}
        </Select> // End of the drop-down.
      )}{/* End of this part. */}
      <Field label="Note for the family (optional)" name="note" maxLength={500} />{/* a note for the family. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of OfferOneOffForm.

export function CloseRequestForm({ id, status, label }: { id: string; status: "done" | "declined" | "withdrawn"; label: string }) { // The "close a request" button form (done, declined or withdrawn).
  return ( // Shows:
    <ActionForm action={closeSessionRequest} submitLabel={label}>{/* the form, with the given button label: */}
      <input type="hidden" name="id" value={id} />{/* the request (hidden), */}
      <input type="hidden" name="status" value={status} />{/* the new status (hidden), */}
      {status === "declined" && <Field label="Note for the family" name="note" maxLength={1000} />}{/* a note for the family when declining. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of CloseRequestForm.

export function SkipPublicHolidaysForm({ bookingId, skipping }: { bookingId: string; skipping: boolean }) { // The "skip public holidays" switch for a booking.
  return ( // Shows:
    <ActionForm action={setSkipPublicHolidays} submitLabel={skipping ? "Have sessions on public holidays" : "Skip public holidays"}>{/* the form, with a button that says what it will change to: */}
      <input type="hidden" name="booking_id" value={bookingId} />{/* the booking (hidden), */}
      <input type="hidden" name="skip" value={skipping ? "no" : "yes"} />{/* the new setting (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SkipPublicHolidaysForm.

// ---------------------------------------------------------------------------
// Blocking
// ---------------------------------------------------------------------------
export function BlockForm({ choices, asTutor }: { choices: { value: string; label: string }[]; asTutor: boolean }) { // The "block a tutor or student" form.
  return ( // Shows:
    <ActionForm action={blockMatch} submitLabel={asTutor ? "Block this student" : "Block this tutor"}>{/* the form, saving with blockMatch: */}
      <Select label={asTutor ? "Student" : "Tutor"} name="pair" defaultValue="" required>{/* the person drop-down (must choose): */}
        <option value="" disabled>{/* a "Choose…" prompt that can't be picked: */}
          Choose…{/* its words, */}
        </option>{/* end of the prompt. */}
        {choices.map((c) => ( // for each person:
          <option key={c.value} value={c.value}>{/* an option: */}
            {c.label}{/* their name, */}
          </option> // end of the option.
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <TextArea // the reason box:
        label="Why? (required)" // its label,
        name="reason" // its name for the action,
        required // must be filled in,
        minLength={10} // at least 10 letters,
        maxLength={2000} // up to 2000 letters,
        hint="Only CLG sees this. CLG will follow up with you to understand what happened and help it not happen again." // a help hint.
      />{/* End of the box. */}
      <p className="text-xs text-zinc-600">{/* a help line explaining what blocking does: */}
        The app stops suggesting you together. The other person isn&apos;t told. Existing sessions aren&apos;t changed
        until CLG has talked with you.{/* (end of the text) */}
      </p>{/* End of the help line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of BlockForm.

export function BlockFollowUpForm({ id }: { id: string }) { // The admin's "block follow-up" form.
  return ( // Shows:
    <ActionForm action={recordBlockFollowUp} submitLabel="Save follow-up">{/* the form, saving with recordBlockFollowUp: */}
      <input type="hidden" name="id" value={id} />{/* the block (hidden), */}
      <TextArea label="What was discussed, and what will help next time" name="note" required minLength={5} maxLength={2000} rows={2} />{/* what was discussed. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of BlockFollowUpForm.

// ---------------------------------------------------------------------------
// Libraries
// ---------------------------------------------------------------------------
export function SuggestLibraryForm() { // The "suggest a library" form.
  return ( // Shows:
    <ActionForm action={suggestLibrary} submitLabel="Suggest library">{/* the form, saving with suggestLibrary: */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label="Library name" name="name" required maxLength={200} />{/* the library's name, */}
        <Field label="Suburb" name="suburb" maxLength={100} />{/* its suburb. */}
      </div>{/* End of the columns. */}
      <Field label="Street address" name="address" required minLength={5} maxLength={300} placeholder="e.g. 5 Mount Barker Road" />{/* its street address. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SuggestLibraryForm.

// Admins: fill a library's hours from OpenStreetMap, to check by hand.
export function FillHoursForm({ libraryId }: { libraryId: string }) { // The "fill hours from OpenStreetMap" button for a library.
  return ( // Shows:
    <ActionForm action={fillHoursFromOsm} submitLabel="Fill hours from OpenStreetMap">{/* the form, saving with fillHoursFromOsm: */}
      <input type="hidden" name="library_id" value={libraryId} />{/* the library (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of FillHoursForm.

// Admins: load all South Australian libraries in one go.
export function LoadLibrariesForm() { // The "load SA libraries" button.
  return ( // Shows:
    <ActionForm action={loadSaLibraries} submitLabel="Load SA libraries">{/* the form, saving with loadSaLibraries: */}
      <p className="text-sm text-zinc-600">{/* a help line explaining what it does: */}
        Adds every South Australian library from OpenStreetMap that isn&apos;t listed yet, with its address and map
        location. Libraries already listed keep their details. Takes up to a minute.{/* (end of the text) */}
      </p>{/* End of the help line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LoadLibrariesForm.

export function LibraryHoursForm({ libraryId }: { libraryId: string }) { // The "add opening hours" form for a library.
  return ( // Shows:
    <ActionForm action={addLibraryHours} submitLabel="Add hours">{/* the form, saving with addLibraryHours: */}
      <input type="hidden" name="library_id" value={libraryId} />{/* the library (hidden), */}
      <div className="flex flex-wrap gap-x-4 gap-y-2">{/* a row of day tick boxes: */}
        {DAYS.map((d, i) => ( // for each day:
          <label key={d} className={box}>{/* a tick box line: */}
            <input type="checkbox" name="weekday" value={i + 1} className="mt-1" /> {d}{/* the tick box and the day's name. */}
          </label> // End of the line.
        ))}{/* End of the loop. */}
      </div>{/* End of the row. */}
      <div className="grid grid-cols-2 gap-4 sm:w-2/3">{/* two columns: */}
        <Field label="Opens" name="opens" type="time" required />{/* opening time, */}
        <Field label="Closes" name="closes" type="time" required />{/* closing time. */}
      </div>{/* End of the columns. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LibraryHoursForm.

export function ConfirmLibraryForm({ libraryId }: { libraryId: string }) { // The "confirm library" button.
  return ( // Shows:
    <ActionForm action={confirmLibrary} submitLabel="Confirm library">{/* the form, saving with confirmLibrary: */}
      <input type="hidden" name="library_id" value={libraryId} />{/* the library (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of ConfirmLibraryForm.

// ---------------------------------------------------------------------------
// Summary time after each session (Carla, 12 Nov 2026)
// ---------------------------------------------------------------------------

// The "time to write the session summary" setting, for owner and operations admins.
export function SummaryMinutesForm({ current }: { current: number }) { // Takes the current number of minutes.
  return ( // What's shown:
    <ActionForm action={setSummaryMinutes} submitLabel="Save">{/* the form, saving with setSummaryMinutes: */}
      <Field label="Minutes after each session" name="minutes" type="number" min={0} max={30} step={5} defaultValue={current} required />{/* the minutes, 0 to 30, starting at the current value. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SummaryMinutesForm.

// Every half hour of the day, as "HH:MM" values with words like "9:30pm".
const HALF_HOURS = Array.from({ length: 48 }, (_, i) => { // 48 half hours in a day:
  const value = `${String(Math.floor(i / 2)).padStart(2, "0")}:${i % 2 ? "30" : "00"}`; // the time, e.g. "21:30",
  const h = Math.floor(i / 2) % 12 === 0 ? 12 : Math.floor(i / 2) % 12; // the 12-hour clock hour,
  const label = `${h}${i % 2 ? ":30" : ""}${i < 24 ? "am" : "pm"}`; // and the words, e.g. "9:30pm".
  return { value, label }; // Hands back both.
}); // End of HALF_HOURS.

// The owner or operations admin's form for CLG's quiet hours.
export function QuietHoursForm({ starts, ends }: { starts: string; ends: string }) { // Takes the current times, e.g. "21:00" and "05:00".
  return ( // What's shown:
    <ActionForm action={setQuietHours} submitLabel="Save">{/* the form, saving with setQuietHours: */}
      <div className="grid grid-cols-2 gap-4 sm:w-2/3">{/* a row of two drop-downs: */}
        <Select label="Quiet from" name="starts" defaultValue={starts}>{/* when quiet hours start, */}
          {HALF_HOURS.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}{/* (every half hour) */}
        </Select>{/* End of the start drop-down. */}
        <Select label="Until" name="ends" defaultValue={ends}>{/* and when they end. */}
          {HALF_HOURS.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}{/* (every half hour) */}
        </Select>{/* End of the end drop-down. */}
      </div>{/* End of the row. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of QuietHoursForm.
