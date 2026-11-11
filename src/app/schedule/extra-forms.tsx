"use client";

// Forms for the 2 Nov 2026 scheduling changes: study periods, requests,
// public holidays, blocking and libraries.

import { useState } from "react";
import {
  addLibraryHours,
  addOwnTerm,
  blockMatch,
  closeSessionRequest,
  confirmLibrary,
  makeSessionRequest,
  offerOneOff,
  recordBlockFollowUp,
  setSkipPublicHolidays,
  setStudyPeriod,
  setTerm4LastDay,
  suggestLibrary,
  loadSaLibraries,
} from "@/app/actions/scheduling-extra";
import { ActionForm } from "@/components/action-form";
import { Field, Select, TextArea } from "@/components/ui";

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const box = "flex items-start gap-2 text-sm";

// ---------------------------------------------------------------------------
// Study periods
// ---------------------------------------------------------------------------
export function StudyPeriodForm({ studentId, calendar }: { studentId: string; calendar: string }) {
  return (
    <ActionForm action={setStudyPeriod} submitLabel="Save study period">
      <input type="hidden" name="student_id" value={studentId} />
      <Select label="Study period" name="calendar" defaultValue={calendar}>
        <option value="public">South Australian government school terms</option>
        <option value="private">South Australian private school terms (an extra week off between Terms 2 and 3)</option>
        <option value="own">My own dates (university, TAFE or other study)</option>
      </Select>
      <p className="text-xs text-zinc-600">
        Next-term questions, holiday sessions and term reviews follow these dates.
      </p>
    </ActionForm>
  );
}

export function OwnTermForm({ studentId }: { studentId: string }) {
  return (
    <ActionForm action={addOwnTerm} submitLabel="Add study dates">
      <input type="hidden" name="student_id" value={studentId} />
      <Field label="Name (optional)" name="label" maxLength={100} placeholder="For example: Semester 1 2027" />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="First day" name="starts_on" type="date" required />
        <Field label="Last day" name="ends_on" type="date" required />
      </div>
    </ActionForm>
  );
}

export function Term4LastDayForm({ studentId, current }: { studentId: string; current: string }) {
  return (
    <ActionForm action={setTerm4LastDay} submitLabel="Save last day">
      <input type="hidden" name="student_id" value={studentId} />
      <Field
        label="Last day of school in Term 4"
        name="last_day"
        type="date"
        defaultValue={current}
        required
        hint="This changes from school to school and by year level (Year 12s often finish early)."
      />
    </ActionForm>
  );
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------
type Child = { id: string; name: string; subjects: string[] };

export function SessionRequestForm({ students, today }: { students: Child[]; today: string }) {
  const [kind, setKind] = useState("extra");
  const [student, setStudent] = useState(students[0]?.id ?? "");
  const subjects = students.find((s) => s.id === student)?.subjects ?? [];
  return (
    <ActionForm action={makeSessionRequest} submitLabel="Send request">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Select label="Child" name="student_id" value={student} onChange={(e) => setStudent(e.target.value)}>
          {students.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </Select>
        <Select label="Subject" name="subject" defaultValue={subjects[0] ?? ""} key={student} required>
          {subjects.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
      </div>
      <Select label="What would you like?" name="kind" value={kind} onChange={(e) => setKind(e.target.value)}>
        <option value="extra">An extra session before a test, exam or other big event</option>
        <option value="public_holiday">A one-off at another time in a public holiday week</option>
        <option value="away_cover">Another time or tutor while our tutor is away</option>
      </Select>
      {kind === "extra" && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="Date of the event" name="event_on" type="date" min={today} required />
          <Field label="What is it?" name="event_label" maxLength={200} placeholder="For example: algebra test" />
        </div>
      )}
      {kind === "public_holiday" && <Field label="Public holiday date" name="event_on" type="date" min={today} />}
      {kind === "away_cover" && (
        <>
          <Field label="Date of the cancelled session" name="event_on" type="date" min={today} />
          <Select label="We'd like" name="wants" defaultValue="either">
            <option value="time">Another time with our tutor</option>
            <option value="tutor">A different tutor at our usual time</option>
            <option value="either">Either is fine</option>
          </Select>
        </>
      )}
      <TextArea label="Times that suit, or anything else (optional)" name="note" maxLength={1000} rows={2} />
      <p className="text-xs text-zinc-600">
        Your tutor or CLG will offer a time if one is available. A one-off session is charged at the usual hourly rate.
      </p>
    </ActionForm>
  );
}

export function OfferOneOffForm({
  requestId,
  isAdmin,
  tutors,
  libraries,
  today,
  before,
}: {
  requestId: string;
  isAdmin: boolean;
  tutors: { id: string; name: string }[];
  libraries: { id: string; name: string }[];
  today: string;
  before: string | null;
}) {
  const [delivery, setDelivery] = useState("online");
  return (
    <ActionForm action={offerOneOff} submitLabel="Offer this time">
      <input type="hidden" name="request_id" value={requestId} />
      {isAdmin && tutors.length > 0 && (
        <Select label="Tutor" name="tutor_id" defaultValue={tutors[0].id}>
          {tutors.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}
            </option>
          ))}
        </Select>
      )}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Field label="Date" name="date" type="date" min={today} max={before ?? undefined} required />
        <Field label="Start" name="start_time" type="time" required />
        <Select label="Length" name="minutes" defaultValue="60">
          {[60, 90, 120].map((m) => (
            <option key={m} value={m}>
              {m === 60 ? "1 hr" : `${m / 60} hr`}
            </option>
          ))}
        </Select>
      </div>
      <Select label="Where" name="delivery" value={delivery} onChange={(e) => setDelivery(e.target.value)}>
        <option value="online">Online</option>
        <option value="library">At a library</option>
        {isAdmin && <option value="home">At home (special circumstances)</option>}
        {isAdmin && <option value="school">At school (special circumstances)</option>}
      </Select>
      {delivery === "library" && (
        <Select label="Library" name="library_id" required>
          {libraries.map((l) => (
            <option key={l.id} value={l.id}>
              {l.name}
            </option>
          ))}
        </Select>
      )}
      <Field label="Note for the family (optional)" name="note" maxLength={500} />
    </ActionForm>
  );
}

export function CloseRequestForm({ id, status, label }: { id: string; status: "done" | "declined" | "withdrawn"; label: string }) {
  return (
    <ActionForm action={closeSessionRequest} submitLabel={label}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="status" value={status} />
      {status === "declined" && <Field label="Note for the family" name="note" maxLength={1000} />}
    </ActionForm>
  );
}

export function SkipPublicHolidaysForm({ bookingId, skipping }: { bookingId: string; skipping: boolean }) {
  return (
    <ActionForm action={setSkipPublicHolidays} submitLabel={skipping ? "Have sessions on public holidays" : "Skip public holidays"}>
      <input type="hidden" name="booking_id" value={bookingId} />
      <input type="hidden" name="skip" value={skipping ? "no" : "yes"} />
    </ActionForm>
  );
}

// ---------------------------------------------------------------------------
// Blocking
// ---------------------------------------------------------------------------
export function BlockForm({ choices, asTutor }: { choices: { value: string; label: string }[]; asTutor: boolean }) {
  return (
    <ActionForm action={blockMatch} submitLabel={asTutor ? "Block this student" : "Block this tutor"}>
      <Select label={asTutor ? "Student" : "Tutor"} name="pair" defaultValue="" required>
        <option value="" disabled>
          Choose…
        </option>
        {choices.map((c) => (
          <option key={c.value} value={c.value}>
            {c.label}
          </option>
        ))}
      </Select>
      <TextArea
        label="Why? (required)"
        name="reason"
        required
        minLength={10}
        maxLength={2000}
        hint="Only CLG sees this. CLG will follow up with you to understand what happened and help it not happen again."
      />
      <p className="text-xs text-zinc-600">
        The app stops suggesting you together. The other person isn&apos;t told. Existing sessions aren&apos;t changed
        until CLG has talked with you.
      </p>
    </ActionForm>
  );
}

export function BlockFollowUpForm({ id }: { id: string }) {
  return (
    <ActionForm action={recordBlockFollowUp} submitLabel="Save follow-up">
      <input type="hidden" name="id" value={id} />
      <TextArea label="What was discussed, and what will help next time" name="note" required minLength={5} maxLength={2000} rows={2} />
    </ActionForm>
  );
}

// ---------------------------------------------------------------------------
// Libraries
// ---------------------------------------------------------------------------
export function SuggestLibraryForm() {
  return (
    <ActionForm action={suggestLibrary} submitLabel="Suggest library">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="Library name" name="name" required maxLength={200} />
        <Field label="Suburb" name="suburb" maxLength={100} />
      </div>
      <Field label="Street address" name="address" required minLength={5} maxLength={300} placeholder="e.g. 5 Mount Barker Road" />
    </ActionForm>
  );
}

// Admins: load all South Australian libraries in one go.
export function LoadLibrariesForm() {
  return (
    <ActionForm action={loadSaLibraries} submitLabel="Load SA libraries">
      <p className="text-sm text-zinc-600">
        Adds every South Australian library from OpenStreetMap that isn&apos;t listed yet, with its address and map
        location. Libraries already listed keep their details. Takes up to a minute.
      </p>
    </ActionForm>
  );
}

export function LibraryHoursForm({ libraryId }: { libraryId: string }) {
  return (
    <ActionForm action={addLibraryHours} submitLabel="Add hours">
      <input type="hidden" name="library_id" value={libraryId} />
      <div className="flex flex-wrap gap-x-4 gap-y-2">
        {DAYS.map((d, i) => (
          <label key={d} className={box}>
            <input type="checkbox" name="weekday" value={i + 1} className="mt-1" /> {d}
          </label>
        ))}
      </div>
      <div className="grid grid-cols-2 gap-4 sm:w-2/3">
        <Field label="Opens" name="opens" type="time" required />
        <Field label="Closes" name="closes" type="time" required />
      </div>
    </ActionForm>
  );
}

export function ConfirmLibraryForm({ libraryId }: { libraryId: string }) {
  return (
    <ActionForm action={confirmLibrary} submitLabel="Confirm library">
      <input type="hidden" name="library_id" value={libraryId} />
    </ActionForm>
  );
}
