// Summary: the scheduling forms: how long to book, choosing and offering
// times, approving or declining, cancelling, signing on and off, places
// and libraries, away dates, the waitlist, reminders, renewals, school
// terms and preferred times. Each form sends its answers to a server action
// in actions/scheduling.ts.
//
"use client"; // Marks this file as code that runs in the browser.

import { startTransition, useActionState, useState, type ReactNode } from "react"; // React tools: run an update in the background, a form's reply state, a remembered value, and the type for "anything that can be shown".
import { // The server actions these forms send to:
  addAwayDates, // add away dates,
  addLibrary, // add a library,
  addTerm, // add a school term,
  answerRenewal, // answer next term's renewal,
  joinWaitlist, // join the waitlist,
  answerBooking, // the tutor answers a booking,
  approveBooking, // the family approves a booking,
  cancelSession, // cancel one session,
  confirmAvailability, // confirm availability for next term,
  confirmTimes, // confirm a session's times,
  recordEndTime, // record a different end time,
  saveNoticeSettings, // save reminder settings,
  recordOutcome, // record how a session went,
  requestBooking, // ask for a booking,
  saveBookingLength, // save how long to book,
  saveStudentPlaces, // save a student's places,
  saveTutorPlaces, // save a tutor's places,
  signOn, // sign on to a session,
  stopBooking, // stop a whole booking.
} from "@/app/actions/scheduling"; // (from the scheduling actions file)
import { ActionForm } from "@/components/action-form"; // The form wrapper that shows errors and a submit button.
import { Button, Field, FormMessage, Select, TextArea } from "@/components/ui"; // Shared form parts: button, text box, form message, drop-down and big text box.
import { initialFormState, type FormState } from "@/lib/forms"; // A form's starting state, and the type for a form's reply.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while it sends.
import { SESSION_LENGTHS, WEEKDAY_NAMES, clockTime, placeLabel } from "@/lib/scheduling"; // Scheduling helpers: session lengths, weekday names, a time in words, and a place in words.

type Action = (prev: FormState, formData: FormData) => Promise<FormState>; // The shape of a server action that a form sends to.

// How long the family wants to book for: a last date, and whether sessions
// go ahead in school holidays and on public holidays. Needed before CLG
// offers times. Families can change it later; CLG admins can change it too.
export function BookingLengthForm({ // Its settings:
  studentId, // the student,
  today, // today's date,
  terms, // the student's term dates,
  until, // the "book until" date so far,
  schoolHolidays, // sessions in school holidays (yes, no or not answered),
  publicHolidays, // sessions on public holidays (yes, no or not answered).
}: { // The settings' types:
  studentId: string; // student id is text,
  today: string; // today is text,
  terms: StudentTerm[]; // terms is a list of terms,
  until: string; // until is text,
  schoolHolidays: boolean | null; // yes, no, or not answered,
  publicHolidays: boolean | null; // yes, no, or not answered.
}) { // End of the settings.
  const missing = !until || schoolHolidays === null || publicHolidays === null; // True if any answer is still missing.
  const yesNo = (name: string, label: string, current: boolean | null) => ( // Makes a yes or no question:
    <fieldset className="space-y-1">{/* a group box: */}
      <legend className="text-sm font-medium text-zinc-800">{label}</legend>{/* the question, */}
      <div className="flex gap-4 text-sm">{/* a row: */}
        <label className="flex items-center gap-2">{/* a label: */}
          <input type="radio" name={name} value="yes" defaultChecked={current === true} required /> Yes{/* a round "Yes" choice (picked if the answer is yes). */}
        </label>{/* End of the label. */}
        <label className="flex items-center gap-2">{/* A label: */}
          <input type="radio" name={name} value="no" defaultChecked={current === false} required /> No{/* a round "No" choice (picked if the answer is no). */}
        </label>{/* End of the label. */}
      </div>{/* End of the row. */}
    </fieldset> // End of the group box.
  ); // End of yesNo.
  return ( // Shows:
    <ActionForm action={saveBookingLength} submitLabel="Save">{/* the form, sending to saveBookingLength, with a "Save" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      {missing && ( // if anything is missing:
        <p className="rounded-lg bg-amber-50 p-3 text-sm text-amber-900">{/* an amber box: */}
          Please fill this in. CLG needs it before offering session times.{/* asks them to fill it in. */}
        </p> // End of the paragraph.
      )}{/* End of this part. */}
      <LastDateField // The last date box:
        name="book_until" // sent as book_until,
        label="Book sessions until" // labelled "Book sessions until",
        min={today} // today or later,
        defaultValue={until} // starting at the date so far,
        terms={terms} // with the term dates to pick from,
        hint="For example, the end of this term or the end of the school year (up to a year ahead)." // and a hint.
      />{/* (end of the element) */}
      {yesNo("school_holidays", "Sessions during school holidays?", schoolHolidays)}{/* The school holidays question. */}
      {yesNo("public_holidays", "Sessions on public holidays?", publicHolidays)}{/* The public holidays question. */}
      <p className="text-xs text-zinc-600">You can change these later, here or by asking CLG.</p>{/* A note that they can change these later. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of BookingLengthForm.

// A term or study period from the student's school calendar.
export type StudentTerm = { label: string; starts_on: string; ends_on: string }; // (the shape: its name, first day and last day)

// Shows a date like "3 Feb 2027".
function niceDate(d: string) { // (takes a date as text)
  return new Date(`${d}T00:00:00`).toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric" }); // Turns it into a short Australian date.
} // End of niceDate.

// The last date of a booking. Never guessed: it is the family's own "book
// until" date if they gave one, otherwise blank. The student's term dates
// are listed so the right end of term can be picked.
export function LastDateField({ // Its settings:
  min, // the earliest date allowed,
  defaultValue, // the date to start with,
  terms, // the student's term dates,
  bookUntil = null, // the family's "book until" date (none by default),
  name = "last_date", // the box's name (last_date by default),
  label = "Last date", // its label ("Last date" by default),
  required = true, // whether it must be filled (yes by default),
  hint, // and an optional hint.
}: { // The settings' types:
  min: string; // earliest is text,
  defaultValue: string; // start date is text,
  terms: StudentTerm[]; // terms is a list of terms,
  bookUntil?: string | null; // book until is optional text or nothing,
  name?: string; // name is optional text,
  label?: string; // label is optional text,
  required?: boolean; // required is optional yes or no,
  hint?: string; // hint is optional text.
}) { // End of the settings.
  const [value, setValue] = useState(defaultValue); // The date in the box (it changes when a term is picked).
  const upcoming = terms.filter((t) => t.ends_on >= min); // Terms that end on or after the earliest date.
  return ( // Shows:
    <div className="space-y-2">{/* a block: */}
      <Field // a date box:
        label={label} // with its label,
        name={name} // its name,
        type="date" // a date picker,
        value={value} // showing the current date,
        onChange={(e) => setValue(e.target.value)} // updating when typed,
        min={min} // no earlier than the earliest date,
        required={required} // filled in if required,
        hint={ // its hint:
          hint ?? // the one given, or else:
          (bookUntil // if the family gave a date,
            ? `The family asked to book until ${niceDate(bookUntil)}.` // says what it was,
            : "Bookings can run across terms, up to a year.") // otherwise says bookings can run up to a year.
        } // (end of the hint)
      />{/* (end of the element) */}
      {upcoming.length > 0 && ( // If there are upcoming terms:
        <Select // a drop-down:
          label="Or pick the end of a term" // labelled for picking a term end,
          name="term_pick" // sent as term_pick,
          value="" // always showing the first choice,
          onChange={(e) => e.target.value && setValue(e.target.value)} // putting the picked term's end date into the date box.
        >{/* (end of the settings) */}
          <option value="">Student&apos;s term dates…</option>{/* A first choice that explains the list. */}
          {upcoming.map((t) => ( // For each term:
            <option key={`${t.label}-${t.ends_on}`} value={t.ends_on}>{/* a choice whose value is its last day: */}
              {t.label}: {niceDate(t.starts_on)} to {niceDate(t.ends_on)}{/* the term's name and dates. */}
            </option> // End of the choice.
          ))}{/* End of the loop. */}
        </Select> // End of the drop-down.
      )}{/* End of this part. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of LastDateField.


// A small form with its own buttons (for example Accept and Decline). The
// button pressed is sent with the form.
function ButtonsForm({ action, children }: { action: Action; children: (pending: boolean) => ReactNode }) { // (takes the action, and the buttons to show given whether it's sending)
  const [state, formAction, pending] = useActionState(action, initialFormState); // The reply, the action to run, and whether it's sending.
  return ( // Shows:
    <form action={formAction} className="space-y-3">{/* the form: */}
      <FormMessage state={state} />{/* any message from the reply, */}
      {children(pending)}{/* and the buttons. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of ButtonsForm.

// The look of a quiet, outlined button.
const quietButton = // (the classes)
  "rounded-full border border-zinc-300 bg-white px-4 py-2 text-sm text-zinc-800 transition hover:border-teal-700 hover:text-teal-800 disabled:opacity-50"; // rounded, outlined, white, and dimmed while disabled.

// "Book this time": the family chooses the dates and can add a note.
type BookOption = { // (the shape)
  student_id: string; // the student,
  subject: string; // the subject,
  tutor_id: string; // the tutor,
  weekday: number; // the day of the week (1 is Monday),
  start_time: string; // the start time,
  minutes: number; // how long in minutes,
  delivery: string; // online or library,
  library_id: string | null; // and the library (if any).
}; // End of the shape.

// Why an admin chose something other than the app's suggestion: the code and its words.
const CHANGE_REASONS: [string, string][] = [ // (the list)
  ["family_request", "Family asked for something else"], // the family asked,
  ["tutor_request", "Tutor asked for something else"], // the tutor asked,
  ["tutor_fit", "Another tutor suits the student better"], // another tutor suits better,
  ["time", "Better time for the tutor's day"], // a better time,
  ["place", "Better place"], // a better place,
  ["other", "Other"], // other.
]; // End of the list.

// The "Book this time" form.
export function BookForm({ // Its settings:
  option, // the time being booked,
  defaultFirst, // the first date to start with,
  defaultLast = "", // the last date to start with (blank by default),
  terms = [], // the student's terms (none by default),
  bookUntil = null, // the family's "book until" date (none by default),
  isAdmin = false, // whether the person is an admin (no by default),
  suggested, // the app's suggestion,
  startOpen = false, // and whether it starts open (no by default).
}: { // The settings' types:
  option: BookOption; // the option,
  defaultFirst: string; // first date is text,
  // Only the family's own "book until" date, never a guess.
  defaultLast?: string; // last date is optional text,
  terms?: StudentTerm[]; // terms is an optional list,
  bookUntil?: string | null; // book until is optional text or nothing,
  isAdmin?: boolean; // admin is optional yes or no,
  // The app's suggestion, when an admin is offering a time.
  suggested?: BookOption | null; // the suggestion is optional (or nothing),
  startOpen?: boolean; // start open is optional yes or no.
}) { // End of the settings.
  const [open, setOpen] = useState(startOpen); // Whether the form is open.
  if (!open) { // If it's closed:
    return ( // shows:
      <button type="button" className={quietButton} onClick={() => setOpen(true)}>{/* a quiet button that opens it: */}
        Choose this time{/* "Choose this time". */}
      </button> // (end of the button)
    ); // (end of what's shown)
  } // End of the closed case.
  const isSuggestion = // True if this is the app's suggestion:
    !!suggested && // there is one,
    suggested.tutor_id === option.tutor_id && // same tutor,
    suggested.weekday === option.weekday && // same day,
    suggested.start_time === option.start_time && // same start,
    suggested.delivery === option.delivery && // same place type,
    (suggested.library_id ?? "") === (option.library_id ?? ""); // and same library.
  return ( // Shows:
    <div className="mt-3 w-full rounded-xl bg-zinc-50 p-4">{/* a shaded block: */}
      <ActionForm action={requestBooking} submitLabel={isAdmin ? "Send to tutor and family" : "Send request to tutor"}>{/* the form, sending to requestBooking, with a button worded for admins or families, */}
        {Object.entries(option).map(([k, v]) => ( // each part of the time:
          <input key={k} type="hidden" name={k} value={v ?? ""} /> // as a hidden box.
        ))}{/* End of the loop. */}
        {isAdmin && suggested && ( // If an admin is offering, with a suggestion:
          <>{/* (a group) */}
            <input type="hidden" name="suggested_tutor" value={suggested.tutor_id} />{/* the suggested tutor (hidden), */}
            <input type="hidden" name="suggested_weekday" value={suggested.weekday} />{/* day (hidden), */}
            <input type="hidden" name="suggested_start" value={suggested.start_time} />{/* start (hidden), */}
            <input type="hidden" name="suggested_delivery" value={suggested.delivery} />{/* place type (hidden), */}
            <input type="hidden" name="suggested_library" value={suggested.library_id ?? ""} />{/* and library (hidden). */}
          </> // End of the group.
        )}{/* End of this part. */}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* A row of two boxes: */}
          <Field label="First week from" name="first_date" type="date" defaultValue={defaultFirst} min={defaultFirst} required />{/* the first week, no earlier than the first date. */}
          <LastDateField min={defaultFirst} defaultValue={defaultLast} terms={terms} bookUntil={bookUntil} />{/* The last date. */}
        </div>{/* End of the block. */}
        {isAdmin && suggested && !isSuggestion && ( // If an admin chose something other than the suggestion:
          <>{/* (a group) */}
            <Select label="Why not the suggested time?" name="change_reason" required defaultValue="">{/* a required drop-down for why: */}
              <option value="" disabled>{/* a blank first choice that can't be picked: */}
                Choose…{/* "Choose…". */}
              </option>{/* End of the choice. */}
              {CHANGE_REASONS.map(([v, label]) => ( // for each reason:
                <option key={v} value={v}>{/* a choice: */}
                  {label}{/* its words. */}
                </option> // End of the choice.
              ))}{/* End of the loop. */}
            </Select>{/* End of the Select. */}
            <Field label="More detail (optional)" name="change_note" maxLength={500} hint="Helps CLG improve the suggestions." />{/* More detail (optional). */}
          </> // End of the group.
        )}{/* End of this part. */}
        <TextArea label={isAdmin ? "Note for the tutor and family (optional)" : "Note for the tutor (optional)"} name="note" maxLength={1000} rows={2} />{/* A note, worded for admins or families. */}
        <p className="text-xs text-zinc-600">{/* A small note: */}
          {isAdmin // for admins,
            ? "The tutor and family each have 3 days to approve, with a reminder after 2 days. It's confirmed once both say yes." // says both sides have 3 days to approve,
            : "This books the time each week, subject to the tutor confirming within 48 hours."}{/* for families, says the tutor confirms within 48 hr. */}
        </p>{/* End of the paragraph. */}
      </ActionForm>{/* End of the form. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of BookForm.

// One of a tutor's suitable times, for the Matching card.
export type OfferChoice = { // (the shape)
  weekday: number; // the day of the week,
  start_time: string; // the start time,
  end_time: string; // the end time,
  delivery: string; // online or library,
  library_id: string | null; // the library (if any),
  library_name: string | null; // its name (if any),
  preferred: boolean; // and whether the family prefers it.
}; // End of the shape.

// True if two times are the same:
const sameOption = (a: BookOption, b: BookOption) => // (takes two options)
  a.tutor_id === b.tutor_id && // same tutor,
  a.weekday === b.weekday && // same day,
  a.start_time.slice(0, 5) === b.start_time.slice(0, 5) && // same start (hours and minutes),
  a.delivery === b.delivery && // same place type,
  (a.library_id ?? "") === (b.library_id ?? ""); // and same library.

// CLG offers a tutor to a family: the best time is chosen, and the admin can
// switch to any of the tutor's other suitable times, or type another time or
// place. Anything but the app's suggestion asks for a reason.
export function OfferForm({ // Its settings:
  student_id, // the student,
  subject, // the subject,
  tutor_id, // the tutor,
  choices, // the tutor's suitable times,
  libraries, // the libraries,
  suggested, // the app's suggestion,
  defaultFirst, // the first date to start with,
  defaultLast = "", // the last date (blank by default),
  terms = [], // the student's terms (none by default),
  bookUntil = null, // the family's "book until" date (none by default),
  startOpen = false, // and whether it starts open (no by default).
}: { // The settings' types:
  student_id: string; // student id is text,
  subject: string; // subject is text,
  tutor_id: string; // tutor id is text,
  choices: OfferChoice[]; // times is a list,
  libraries: { id: string; name: string }[]; // libraries is a list of ids and names,
  suggested: BookOption | null; // the suggestion or nothing,
  defaultFirst: string; // first date is text,
  defaultLast?: string; // last date is optional text,
  terms?: StudentTerm[]; // terms is an optional list,
  bookUntil?: string | null; // book until is optional text or nothing,
  startOpen?: boolean; // start open is optional yes or no.
}) { // End of the settings.
  const [open, setOpen] = useState(startOpen); // Whether the form is open.
  const [pick, setPick] = useState(choices.length ? "0" : "other"); // The picked time: the first one, or "other" if there are none.
  const [weekday, setWeekday] = useState(1); // For another time: the day (Monday to start),
  const [start, setStart] = useState("16:00"); // the start time,
  const [minutes, setMinutes] = useState(60); // the length,
  const [place, setPlace] = useState("online"); // and the place (online to start).
  if (!open) { // If it's closed:
    return ( // shows:
      <button type="button" className={quietButton} onClick={() => setOpen(true)}>{/* a quiet button that opens it: */}
        Offer this tutor{/* "Offer this tutor". */}
      </button> // (end of the button)
    ); // (end of what's shown)
  } // End of the closed case.
  const other = pick === "other"; // True if the admin typed another time.
  const chosen = other ? null : choices[Number(pick)]; // The picked time (or nothing for "other").
  const option: BookOption = chosen // The time to send:
    ? { // if a suggested time was picked:
        student_id, // the student,
        subject, // the subject,
        tutor_id, // the tutor,
        weekday: chosen.weekday, // its day,
        start_time: chosen.start_time, // its start,
        minutes: 60, // one hour,
        delivery: chosen.delivery, // its place type,
        library_id: chosen.library_id, // and its library.
      } // (end of that time)
    : { // otherwise the typed time:
        student_id, // the student,
        subject, // the subject,
        tutor_id, // the tutor,
        weekday, // the day,
        start_time: start, // the start,
        minutes, // the length,
        delivery: place === "online" ? "online" : "library", // online or library,
        library_id: place === "online" ? null : place, // and the library (none if online).
      }; // (end of the typed time)
  const isSuggestion = !!suggested && !other && sameOption(suggested, option); // True if the admin kept the app's suggestion.
  return ( // Shows:
    <div className="mt-3 w-full rounded-xl bg-zinc-50 p-4">{/* a shaded block: */}
      <ActionForm action={requestBooking} submitLabel="Send to tutor and family">{/* the form, sending to requestBooking, with a "Send to tutor and family" button, */}
        {Object.entries(option).map(([k, v]) => ( // each part of the time:
          <input key={k} type="hidden" name={k} value={v ?? ""} /> // as a hidden box.
        ))}{/* End of the loop. */}
        {other && <input type="hidden" name="other" value="1" />}{/* Marks a typed time (hidden). */}
        {suggested && ( // If there's a suggestion:
          <>{/* (a group) */}
            <input type="hidden" name="suggested_tutor" value={suggested.tutor_id} />{/* the suggested tutor (hidden), */}
            <input type="hidden" name="suggested_weekday" value={suggested.weekday} />{/* day (hidden), */}
            <input type="hidden" name="suggested_start" value={suggested.start_time} />{/* start (hidden), */}
            <input type="hidden" name="suggested_delivery" value={suggested.delivery} />{/* place type (hidden), */}
            <input type="hidden" name="suggested_library" value={suggested.library_id ?? ""} />{/* and library (hidden). */}
          </> // End of the group.
        )}{/* End of this part. */}
        <Select label="Time and place" name="pick" value={pick} onChange={(e) => setPick(e.target.value)}>{/* A drop-down of the tutor's times: */}
          {choices.map((c, i) => ( // for each time:
            <option key={i} value={String(i)}>{/* a choice: */}
              {WEEKDAY_NAMES[c.weekday - 1]} {clockTime(c.start_time)} to {clockTime(c.end_time)} · {placeLabel(c.delivery, c.library_name)}{/* its day, start, end and place, */}
              {c.preferred ? " (preferred)" : ""}{/* marked if preferred. */}
            </option> // End of the choice.
          ))}{/* End of the loop. */}
          <option value="other">Another time or place…</option>{/* A last choice for another time or place. */}
        </Select>{/* End of the drop-down. */}
        {other && ( // If another time is chosen:
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* a row of boxes: */}
            <Select label="Day" name="other_weekday" value={String(weekday)} onChange={(e) => setWeekday(Number(e.target.value))}>{/* a drop-down for the day: */}
              {WEEKDAY_NAMES.map((d, i) => ( // for each day:
                <option key={d} value={String(i + 1)}>{/* a choice: */}
                  {d}{/* its name. */}
                </option> // End of the choice.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
            <Field label="Start time" name="other_start" type="time" step={300} value={start} onChange={(e) => setStart(e.target.value)} required />{/* The start time, in 5-minute steps. */}
            <Select label="Length" name="other_minutes" value={String(minutes)} onChange={(e) => setMinutes(Number(e.target.value))}>{/* A drop-down for the length: */}
              {SESSION_LENGTHS.map((m) => ( // for each allowed length:
                <option key={m} value={String(m)}>{/* a choice: */}
                  {m % 60 === 0 ? `${m / 60} hr` : `${Math.floor(m / 60)}.5 hr`}{/* in hours (for example 1 hr or 1.5 hr). */}
                </option> // End of the choice.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
            <Select label="Place" name="other_place" value={place} onChange={(e) => setPlace(e.target.value)}>{/* A drop-down for the place: */}
              <option value="online">Online</option>{/* online, */}
              {libraries.map((l) => ( // for each library:
                <option key={l.id} value={l.id}>{/* a choice: */}
                  {l.name}{/* its name. */}
                </option> // End of the choice.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
            <p className="text-xs text-zinc-600 sm:col-span-2">{/* A small note: */}
              This time isn&apos;t in the tutor&apos;s availability, so check with them first. The app still checks their weekly
              maximum and other bookings.{/* (to check with the tutor first) */}
            </p>{/* End of the paragraph. */}
          </div> // End of the block.
        )}{/* End of this part. */}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* A row of two boxes: */}
          <Field label="First week from" name="first_date" type="date" defaultValue={defaultFirst} min={defaultFirst} required />{/* the first week, no earlier than the first date. */}
          <LastDateField min={defaultFirst} defaultValue={defaultLast} terms={terms} bookUntil={bookUntil} />{/* The last date. */}
        </div>{/* End of the block. */}
        {suggested && !isSuggestion && ( // If the admin changed the suggestion:
          <>{/* (a group) */}
            <Select label="Why not the suggested time?" name="change_reason" required defaultValue="">{/* a required drop-down for why: */}
              <option value="" disabled>{/* a blank first choice that can't be picked: */}
                Choose…{/* "Choose…". */}
              </option>{/* End of the choice. */}
              {CHANGE_REASONS.map(([v, label]) => ( // for each reason:
                <option key={v} value={v}>{/* a choice: */}
                  {label}{/* its words. */}
                </option> // End of the choice.
              ))}{/* End of the loop. */}
            </Select>{/* End of the Select. */}
            <Field label="More detail (optional)" name="change_note" maxLength={500} hint="Helps CLG improve the suggestions." />{/* More detail (optional). */}
          </> // End of the group.
        )}{/* End of this part. */}
        <TextArea label="Note for the tutor and family (optional)" name="note" maxLength={1000} rows={2} />{/* A note for the tutor and family. */}
        <p className="text-xs text-zinc-600">{/* A small note: */}
          The tutor and family each have 3 days to approve, with a reminder after 2 days. It&apos;s confirmed once both say yes.{/* says both sides have 3 days to approve. */}
        </p>{/* End of the paragraph. */}
      </ActionForm>{/* End of the form. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of OfferForm.

// The family approves or declines a time CLG offered.
export function ApproveForm({ bookingId }: { bookingId: string }) { // (takes the booking)
  return ( // Shows:
    <ButtonsForm action={approveBooking}>{/* a form with its own buttons, sending to approveBooking: */}
      {(pending) => ( // given whether it's sending:
        <>{/* (a group) */}
          <input type="hidden" name="booking_id" value={bookingId} />{/* the booking (hidden), */}
          <TextArea label="Note for CLG (needed if you decline: please say why)" name="note" maxLength={1000} rows={2} />{/* a note (needed when declining), */}
          <div className="flex flex-wrap gap-2">{/* a row of buttons: */}
            <Button type="submit" name="answer" value="accept" disabled={pending}>{/* an approve button: */}
              Approve{/* "Approve". */}
            </Button>{/* (end of the button) */}
            <BusyButton type="submit" name="answer" value="decline" disabled={pending} className={quietButton}>{/* a quiet decline button: */}
              This time doesn&apos;t suit{/* "This time doesn't suit". */}
            </BusyButton>{/* (end of the button) */}
          </div>{/* End of the block. */}
        </> // End of the group.
      )}{/* End of this part. */}
    </ButtonsForm> // End of the form.
  ); // End of what's shown.
} // End of ApproveForm.

// The tutor accepts or declines a booking request.
export function AnswerForm({ bookingId }: { bookingId: string }) { // (takes the booking)
  return ( // Shows:
    <ButtonsForm action={answerBooking}>{/* a form with its own buttons, sending to answerBooking: */}
      {(pending) => ( // given whether it's sending:
        <>{/* (a group) */}
          <input type="hidden" name="booking_id" value={bookingId} />{/* the booking (hidden), */}
          <TextArea label="Note to the family (needed if you decline: please say why)" name="note" maxLength={1000} rows={2} />{/* a note (needed when declining), */}
          <div className="flex flex-wrap gap-2">{/* a row of buttons: */}
            <Button type="submit" name="answer" value="accept" disabled={pending}>{/* an accept button: */}
              Accept{/* "Accept". */}
            </Button>{/* (end of the button) */}
            <BusyButton type="submit" name="answer" value="decline" disabled={pending} className={quietButton}>{/* a quiet decline button: */}
              Decline{/* "Decline". */}
            </BusyButton>{/* (end of the button) */}
          </div>{/* End of the block. */}
        </> // End of the group.
      )}{/* End of this part. */}
    </ButtonsForm> // End of the form.
  ); // End of what's shown.
} // End of AnswerForm.

// Cancel one session, or stop a whole booking. Admins say who asked, which
// decides credits and pay.
export function CancelForm({ id, kind, isAdmin }: { id: string; kind: "session" | "booking"; isAdmin: boolean }) { // (takes the session or booking id, which one it is, and whether the person is an admin)
  const [open, setOpen] = useState(false); // Whether the form is open.
  if (!open) { // If it's closed:
    return ( // shows:
      <button type="button" className="text-xs text-red-700 underline" onClick={() => setOpen(true)}>{/* a small red link-style button that opens it: */}
        {kind === "session" ? "Cancel" : "Stop booking"}{/* "Cancel" or "Stop booking". */}
      </button> // (end of the button)
    ); // (end of what's shown)
  } // End of the closed case.
  return ( // Shows:
    <div className="mt-2 w-full rounded-xl bg-zinc-50 p-4">{/* a shaded block: */}
      <ActionForm // the form:
        action={kind === "session" ? cancelSession : stopBooking} // sending to cancelSession or stopBooking,
        submitLabel={kind === "session" ? "Cancel this session" : "Stop booking and cancel future sessions"} // with a button saying what it does.
      >{/* (end of the form's settings) */}
        <input type="hidden" name="id" value={id} />{/* the session or booking (hidden), */}
        <Field label="Reason (optional)" name="reason" maxLength={500} />{/* a reason (optional), */}
        {isAdmin && ( // for admins:
          <Select label="Who asked?" name="on_behalf" defaultValue="family">{/* a drop-down for who asked: */}
            <option value="family">The family</option>{/* the family, */}
            <option value="tutor">The tutor</option>{/* the tutor, */}
            <option value="admin">CLG</option>{/* or CLG. */}
          </Select> // End of the drop-down.
        )}{/* End of this part. */}
        {!isAdmin && ( // For families:
          <p className="text-xs text-zinc-600">{/* a small note: */}
            Family cancellations: more than 24 hr before gets a full credit, 24 to 2 hr before gets a 50% credit, and
            under 2 hr gets no credit.{/* (the credit rules) */}
          </p> // End of the paragraph.
        )}{/* End of this part. */}
      </ActionForm>{/* End of the form. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of CancelForm.

// The tutor records a session as done or a no-show.
export function OutcomeForm({ id }: { id: string }) { // (takes the session)
  return ( // Shows:
    <ButtonsForm action={recordOutcome}>{/* a form with its own buttons, sending to recordOutcome: */}
      {(pending) => ( // given whether it's sending:
        <div className="flex flex-wrap gap-2">{/* a row: */}
          <input type="hidden" name="id" value={id} />{/* the session (hidden), */}
          <BusyButton type="submit" name="outcome" value="completed" disabled={pending} className={quietButton}>{/* a quiet "Done" button: */}
            Done{/* "Done". */}
          </BusyButton>{/* (end of the button) */}
          <BusyButton type="submit" name="outcome" value="no_show" disabled={pending} className={quietButton}>{/* a quiet "No-show" button: */}
            No-show{/* "No-show". */}
          </BusyButton>{/* (end of the button) */}
        </div> // End of the block.
      )}{/* End of this part. */}
    </ButtonsForm> // End of the form.
  ); // End of what's shown.
} // End of OutcomeForm.

// The tutor's places: how they teach and the libraries they can work at.
export function PlacesForm({ // Its settings:
  libraries, // the libraries,
  chosen, // the ones already ticked,
  settings, // and how they teach.
}: { // The settings' types:
  libraries: { id: string; name: string; suburb: string | null }[]; // libraries is a list of ids, names and suburbs,
  chosen: string[]; // chosen is a list of library ids,
  settings: { online: boolean; in_person: boolean; learning_support: boolean }; // online, in person and learning support are yes or no.
}) { // End of the settings.
  const box = "flex items-start gap-2 text-sm"; // The look of each tick box row.
  return ( // Shows:
    <ActionForm action={saveTutorPlaces} submitLabel="Save">{/* the form, sending to saveTutorPlaces, with a "Save" button, */}
      <fieldset className="space-y-2">{/* a group box: */}
        <legend className="mb-1 text-sm font-medium text-zinc-800">How you teach</legend>{/* its title, */}
        <label className={box}>{/* a label: */}
          <input type="checkbox" name="online" defaultChecked={settings.online} className="mt-1" /> Online{/* an "Online" tick box. */}
        </label>{/* End of the label. */}
        <label className={box}>{/* A label: */}
          <input type="checkbox" name="in_person" defaultChecked={settings.in_person} className="mt-1" /> In person, at
          the libraries ticked below{/* (an "In person" tick box) */}
        </label>{/* End of the label. */}
        <label className={box}>{/* A label: */}
          <input type="checkbox" name="learning_support" defaultChecked={settings.learning_support} className="mt-1" />{/* a learning support tick box, */}
          I have experience with learning difficulties{/* its words. */}
        </label>{/* End of the label. */}
      </fieldset>{/* End of the group box. */}
      <fieldset className="space-y-2">{/* A group box: */}
        <legend className="mb-1 text-sm font-medium text-zinc-800">Libraries you can work at</legend>{/* its title, */}
        {libraries.length === 0 && <p className="text-sm text-zinc-500">CLG hasn&apos;t added any libraries yet.</p>}{/* a note if there are no libraries yet, */}
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">{/* a grid: */}
          {libraries.map((l) => ( // for each library:
            <label key={l.id} className={box}>{/* a label: */}
              <input type="checkbox" name="library" value={l.id} defaultChecked={chosen.includes(l.id)} className="mt-1" />{/* a tick box (ticked if chosen), */}
              <span>{/* the words: */}
                {l.name}{/* the library's name, */}
                {l.suburb && <span className="text-zinc-500"> · {l.suburb}</span>}{/* and its suburb in grey, if known. */}
              </span>{/* End of the text. */}
            </label> // End of the label.
          ))}{/* End of the loop. */}
        </div>{/* End of the block. */}
        <p className="text-xs text-zinc-600">{/* A small note: */}
          You&apos;ll stay at one library for the day. Online sessions can be taken from the library on library days.{/* about staying at one library for the day. */}
        </p>{/* End of the paragraph. */}
      </fieldset>{/* End of the group box. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of PlacesForm.

// An admin adds a library.
export function LibraryForm() {
  return ( // Shows:
    <ActionForm action={addLibrary} submitLabel="Add library">{/* the form, sending to addLibrary, with an "Add library" button, */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* a row of two boxes: */}
        <Field label="Library name" name="name" required maxLength={200} />{/* the name (required), */}
        <Field label="Suburb" name="suburb" maxLength={100} />{/* and the suburb. */}
      </div>{/* End of the block. */}
      <Field label="Address (optional)" name="address" maxLength={300} />{/* The address (optional). */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* A row of two boxes: */}
        <Field label="Latitude" name="latitude" inputMode="decimal" placeholder="-34.9285" />{/* latitude, */}
        <Field label="Longitude" name="longitude" inputMode="decimal" placeholder="138.6007" />{/* and longitude. */}
      </div>{/* End of the block. */}
      <p className="text-xs text-zinc-600">{/* A small note: */}
        Used for the tutor&apos;s sign-on check (within 300 m). Find them by right-clicking the library in Google Maps.{/* says what they're for and how to find them. */}
      </p>{/* End of the paragraph. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LibraryForm.

// Adds dates when a student or tutor will be away.
export function AwayForm({ // Its settings:
  choices, // who can be chosen,
  today, // today's date,
  isTutor = false, // and whether the person is a tutor (no by default).
}: { // The settings' types:
  choices: { value: string; label: string }[]; // choices is a list of values and labels,
  today: string; // today is text,
  isTutor?: boolean; // tutor is optional yes or no.
}) { // End of the settings.
  return ( // Shows:
    <ActionForm action={addAwayDates} submitLabel="Save away dates">{/* the form, sending to addAwayDates, with a "Save away dates" button, */}
      <Select label="Who will be away?" name="who" defaultValue={choices[0]?.value}>{/* a drop-down for who, starting at the first choice: */}
        {choices.map((c) => ( // for each choice:
          <option key={c.value} value={c.value}>{/* a choice: */}
            {c.label}{/* its words. */}
          </option> // End of the choice.
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* A row of two boxes: */}
        <Field label="First day away" name="from_date" type="date" min={today} required />{/* the first day away (today or later), */}
        <Field label="Last day away" name="to_date" type="date" min={today} required />{/* and the last day away. */}
      </div>{/* End of the block. */}
      <Field label="Reason (optional)" name="reason" maxLength={300} hint="For example: family holiday, school camp." />{/* The reason (optional), with examples. */}
      {isTutor && ( // For tutors:
        <>{/* (a group) */}
          <TextArea // a big text box:
            label="Times you could offer instead (optional, for your own away dates)" // labelled for other times,
            name="tutor_offer" // sent as tutor_offer,
            maxLength={1000} // up to 1000 letters,
            rows={2} // two rows high,
            hint="Shared with the families whose sessions are cancelled. For example: I could do Thursday 4pm that week instead." // with a note on who sees it.
          />{/* (end of the element) */}
          <p className="text-xs text-zinc-600">{/* A small note: */}
            Your sessions on these dates are cancelled 2 hours after you save, so you can remove the dates if you made a
            mistake. Families and CLG are then told politely, and families can ask for another time or a different tutor.{/* (when sessions are cancelled, and who is told) */}
          </p>{/* End of the paragraph. */}
        </> // End of the group.
      )}{/* End of this part. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AwayForm.

// Joins the waitlist when no tutor is free.
export function WaitlistForm({ request }: { request: Record<string, string | number> }) { // (takes the details of what was asked for)
  return ( // Shows:
    <ActionForm action={joinWaitlist} submitLabel="Join the waitlist">{/* the form, sending to joinWaitlist, with a "Join the waitlist" button, */}
      {Object.entries(request).map(([k, v]) => ( // each detail:
        <input key={k} type="hidden" name={k} value={v} /> // as a hidden box.
      ))}{/* End of the loop. */}
      <TextArea label="Anything CLG should know? (optional)" name="note" maxLength={1000} rows={2} />{/* Anything CLG should know (optional). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of WaitlistForm.

// Sign on to a session. For a library session the app asks the browser for
// the tutor's position once, with their permission; it's compared with the
// library and not kept.
export function SignOnForm({ id, atLibrary }: { id: string; atLibrary: boolean }) { // (takes the session, and whether it's at a library)
  const [state, formAction, pending] = useActionState(signOn, initialFormState); // The reply, the action to run, and whether it's sending.
  const [locating, setLocating] = useState(false); // Whether the app is checking the location.

  function withPosition(event: React.FormEvent<HTMLFormElement>) { // Runs when the form is sent:
    if (!atLibrary) return; // not at a library: sends as normal.
    event.preventDefault(); // Stops the normal send.
    const form = event.currentTarget; // The form.
    const data = new FormData(form); // Its answers.
    const send = () => startTransition(() => formAction(data)); // Sends the answers in the background.
    if (!("geolocation" in navigator)) return send(); // No location on this device: sends without it.
    setLocating(true); // Shows that it's checking.
    navigator.geolocation.getCurrentPosition( // Asks the browser for the position once:
      (pos) => { // if it gets one:
        data.set("latitude", String(pos.coords.latitude)); // adds the latitude,
        data.set("longitude", String(pos.coords.longitude)); // and the longitude,
        setLocating(false); // stops showing the check,
        send(); // and sends.
      }, // (end of the success case)
      () => { // if it's refused or fails:
        setLocating(false); // stops showing the check,
        send(); // and sends without it.
      }, // (end of the failure case)
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }, // asks for an accurate, fresh reading, waiting up to 10 seconds.
    ); // (end of the ask)
  } // End of withPosition.

  if (state.message) return <FormMessage state={state} />; // Once signed on, shows just the message.
  return ( // Shows:
    <form action={formAction} onSubmit={withPosition} className="space-y-2">{/* the form, getting the position first when needed: */}
      <FormMessage state={state} />{/* any message, */}
      <input type="hidden" name="id" value={id} />{/* the session (hidden), */}
      <Button type="submit" disabled={pending || locating}>{/* the sign on button (off while busy): */}
        {locating ? "Checking location…" : pending ? "Signing on…" : "Sign on"}{/* its words, showing what's happening. */}
      </Button>{/* (end of the button) */}
      {atLibrary && ( // At a library:
        <p className="text-xs text-zinc-600">{/* a small note: */}
          Your phone will ask to share your location once. CLG only keeps whether you were at the library.{/* about the location check. */}
        </p> // End of the paragraph.
      )}{/* End of this part. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of SignOnForm.

// The tutor says they finished at a different time.
export function EndTimeForm({ id, date, bookedEnd }: { id: string; date: string; bookedEnd: string }) { // (takes the session, the date and the booked end time)
  const [open, setOpen] = useState(false); // Whether the form is open.
  if (!open) { // If it's closed:
    return ( // shows:
      <button type="button" className="text-xs text-teal-800 underline" onClick={() => setOpen(true)}>{/* a small link-style button that opens it: */}
        Finished at a different time?{/* "Finished at a different time?". */}
      </button> // (end of the button)
    ); // (end of what's shown)
  } // End of the closed case.
  return ( // Shows:
    <div className="mt-2 w-full rounded-xl bg-zinc-50 p-4">{/* a shaded block: */}
      <ActionForm action={recordEndTime} submitLabel="Send to CLG">{/* the form, sending to recordEndTime, with a "Send to CLG" button, */}
        <input type="hidden" name="id" value={id} />{/* the session (hidden), */}
        <input type="hidden" name="date" value={date} />{/* the date (hidden), */}
        <Field label="Time you finished" name="end_time" type="time" defaultValue={bookedEnd} required />{/* the finish time, starting at the booked end, */}
        <Field label="Why was it different?" name="note" maxLength={500} required />{/* and why (required). */}
      </ActionForm>{/* End of the form. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of EndTimeForm.

// An admin confirms a session's start and end times.
export function ConfirmTimesForm({ id, date, from, to }: { id: string; date: string; from: string; to: string }) { // (takes the session, date, and start and end times)
  return ( // Shows:
    <ActionForm action={confirmTimes} submitLabel="Confirm times">{/* the form, sending to confirmTimes, with a "Confirm times" button, */}
      <input type="hidden" name="id" value={id} />{/* the session (hidden), */}
      <input type="hidden" name="date" value={date} />{/* the date (hidden), */}
      <div className="grid grid-cols-2 gap-4 sm:w-2/3">{/* a row of two boxes: */}
        <Field label="From" name="from_time" type="time" defaultValue={from} required />{/* from, */}
        <Field label="To" name="to_time" type="time" defaultValue={to} required />{/* and to. */}
      </div>{/* End of the block. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of ConfirmTimesForm.

// The person's reminder setting: when the first reminder comes.
export function NoticeSettingsForm({ // Its settings:
  settings, // the current setting,
  quiet, // and CLG's quiet hours, e.g. "9pm and 5am".
}: { // The settings' types:
  settings: { first_reminder_hours: number }; // hours before is a number,
  quiet: string; // the quiet hours are words.
}) { // End of the settings.
  return ( // Shows:
    <ActionForm action={saveNoticeSettings} submitLabel="Save">{/* the form, sending to saveNoticeSettings, with a "Save" button, */}
      <Select label="First reminder" name="first_reminder_hours" defaultValue={String(settings.first_reminder_hours)}>{/* a drop-down, starting at the current setting: */}
        {[2, 6, 12, 24, 48, 72, 168].map((h) => ( // for each choice of hours:
          <option key={h} value={h}>{/* a choice: */}
            {h === 168 ? "1 week" : `${h} hr`} before{/* "1 week" or the hours, then "before". */}
          </option> // End of the choice.
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <p className="text-xs text-zinc-600">{/* A small note: */}
        A final reminder always comes 1 hr before. Nothing arrives between {quiet}, your local time. Reminders and notices
        show here in the app; CLG doesn&apos;t send them by email.{/* (about the final reminder and quiet hours) */}
      </p>{/* End of the paragraph. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of NoticeSettingsForm.

// Next term: same again, holidays, and what to change if not.
export function RenewalForm({ id }: { id: string }) { // (takes the renewal)
  const [sameAgain, setSameAgain] = useState(""); // The family's answer to "same again?" (none yet).
  return ( // Shows:
    <ActionForm action={answerRenewal} submitLabel="Send answer">{/* the form, sending to answerRenewal, with a "Send answer" button, */}
      <input type="hidden" name="id" value={id} />{/* the renewal (hidden), */}
      <fieldset className="space-y-2">{/* a group box: */}
        <legend className="mb-1 text-sm font-medium text-zinc-800">Same time and tutor next term?</legend>{/* its question, */}
        <label className="flex items-start gap-2 text-sm">{/* a label: */}
          <input type="radio" name="same_again" value="yes" required onChange={() => setSameAgain("yes")} className="mt-1" />{" "}{/* a round "yes" choice (required), then a space, */}
          Yes, the same again{/* its words. */}
        </label>{/* End of the label. */}
        <label className="flex items-start gap-2 text-sm">{/* A label: */}
          <input type="radio" name="same_again" value="no" onChange={() => setSameAgain("no")} className="mt-1" />{" "}{/* a round "no" choice, then a space, */}
          No, something different{/* its words. */}
        </label>{/* End of the label. */}
      </fieldset>{/* End of the group box. */}
      {sameAgain === "no" && ( // If they said no:
        <>{/* (a group) */}
          <Select label="What would you like to change?" name="change_what" defaultValue="time">{/* a drop-down for what to change: */}
            <option value="time">Day and time</option>{/* day and time, */}
            <option value="tutor">Tutor</option>{/* tutor, */}
            <option value="both">Both</option>{/* both. */}
          </Select>{/* End of the drop-down. */}
          <TextArea label="Why? (helps us find a better fit)" name="change_reason" maxLength={1000} rows={2} />{/* Why. */}
        </> // End of the group.
      )}{/* End of this part. */}
      <fieldset className="space-y-2">{/* A group box: */}
        <legend className="mb-1 text-sm font-medium text-zinc-800">Sessions in the school holidays?</legend>{/* its question, */}
        <label className="flex items-start gap-2 text-sm">{/* a label: */}
          <input type="radio" name="holidays" value="yes" required className="mt-1" /> Yes, keep going in the holidays{/* a round "yes" choice (required). */}
        </label>{/* End of the label. */}
        <label className="flex items-start gap-2 text-sm">{/* A label: */}
          <input type="radio" name="holidays" value="no" className="mt-1" /> No, pause for the holidays{/* a round "no" choice. */}
        </label>{/* End of the label. */}
      </fieldset>{/* End of the group box. */}
      <TextArea label="How is it going? (optional)" name="feedback" maxLength={2000} rows={3} />{/* How it's going (optional). */}
      <label className="flex items-start gap-2 text-sm">{/* A label: */}
        <input type="checkbox" name="testimonial_ok" className="mt-1" /> CLG may share my feedback as a testimonial
        (first name only){/* (a tick box to allow sharing as a testimonial) */}
      </label>{/* End of the label. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of RenewalForm.

// An admin adds a school term's dates.
export function TermForm() {
  return ( // Shows:
    <ActionForm action={addTerm} submitLabel="Save term">{/* the form, sending to addTerm, with a "Save term" button, */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* a row of boxes: */}
        <Select label="State" name="state" defaultValue="SA">{/* a drop-down for the state, starting at SA: */}
          {["SA", "NSW", "VIC", "QLD", "WA", "TAS", "ACT", "NT"].map((s) => ( // for each state:
            <option key={s} value={s}>{/* a choice: */}
              {s}{/* its name. */}
            </option> // End of the choice.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <Select label="Calendar" name="calendar" defaultValue="public">{/* a drop-down for the calendar: */}
          <option value="public">Government schools</option>{/* government, */}
          <option value="private">Private schools</option>{/* private. */}
        </Select>{/* End of the drop-down. */}
        <Select label="Term" name="term" defaultValue="1">{/* a drop-down for the term: */}
          {[1, 2, 3, 4].map((t) => ( // for terms 1 to 4:
            <option key={t} value={t}>{/* a choice: */}
              Term {t}{/* "Term" and its number. */}
            </option> // End of the choice.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
      </div>{/* End of the block. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* A row of two boxes: */}
        <Field label="First day" name="starts_on" type="date" required />{/* the first day, */}
        <Field label="Last day" name="ends_on" type="date" required />{/* and the last day. */}
      </div>{/* End of the block. */}
      <p className="text-xs text-zinc-600">Saving a term that already exists replaces its dates.</p>{/* A note that saving again replaces the dates. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of TermForm.

// Each term: "Is your availability right for next term?"
export function AvailabilityCheckForm({ id }: { id: string }) { // (takes the check)
  return ( // Shows:
    <ButtonsForm action={confirmAvailability}>{/* a form with its own buttons, sending to confirmAvailability: */}
      {(pending) => ( // given whether it's sending:
        <>{/* (a group) */}
          <input type="hidden" name="id" value={id} />{/* the check (hidden), */}
          <div className="flex flex-wrap gap-2">{/* a row of buttons: */}
            <Button type="submit" name="answer" value="same" disabled={pending}>{/* a "No changes" button: */}
              No changes{/* "No changes". */}
            </Button>{/* (end of the button) */}
            <BusyButton type="submit" name="answer" value="changed" disabled={pending} className={quietButton}>{/* a quiet "updated" button: */}
              I&apos;ve updated it{/* "I've updated it". */}
            </BusyButton>{/* (end of the button) */}
          </div>{/* End of the block. */}
        </> // End of the group.
      )}{/* End of this part. */}
    </ButtonsForm> // End of the form.
  ); // End of what's shown.
} // End of AvailabilityCheckForm.

// Where a child can have sessions: online, and the libraries that suit.
export function StudentPlacesForm({ // Its settings:
  studentId, // the student,
  libraries, // the libraries,
  online, // whether online suits,
  chosen, // the libraries already chosen,
  preferredDays = [], // preferred days (none by default),
  preferredParts = [], // preferred parts of the day (none by default),
  schoolHours = false, // whether school hours suit (no by default),
  showPlaces = true, // whether to show places (yes by default),
  tutorPreferences = "", // and tutor preferences (blank by default).
}: { // The settings' types:
  studentId: string; // student id is text,
  libraries: { id: string; name: string; suburb: string | null }[]; // libraries is a list of ids, names and suburbs,
  online: boolean; // online is yes or no,
  chosen: string[]; // chosen is a list of library ids,
  preferredDays?: number[]; // days is an optional list of numbers,
  preferredParts?: string[]; // parts is an optional list of words,
  schoolHours?: boolean; // school hours is optional yes or no,
  // Admins choose places; families only give preferred times.
  showPlaces?: boolean; // show places is optional yes or no,
  tutorPreferences?: string; // tutor preferences is optional text.
}) { // End of the settings.
  const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]; // Short day names.
  const box = "flex items-start gap-2 text-sm"; // The look of each tick box row.
  return ( // Shows:
    <ActionForm action={saveStudentPlaces} submitLabel={showPlaces ? "Save places" : "Save preferences"}>{/* the form, sending to saveStudentPlaces, with a button worded for what's shown, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      {showPlaces ? ( // if places are shown:
        <>{/* (a group) */}
          <label className={box}>{/* a label: */}
            <input type="checkbox" name="online" defaultChecked={online} className="mt-1" /> Online{/* an "Online" tick box. */}
          </label>{/* End of the label. */}
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">{/* A grid: */}
            {libraries.map((l) => ( // for each library:
              <label key={l.id} className={box}>{/* a label: */}
                <input type="checkbox" name="library" value={l.id} defaultChecked={chosen.includes(l.id)} className="mt-1" />{/* a tick box (ticked if chosen), */}
                <span>{/* the words: */}
                  {l.name}{/* the library's name, */}
                  {l.suburb && <span className="text-zinc-500"> · {l.suburb}</span>}{/* and its suburb in grey, if known. */}
                </span>{/* End of the text. */}
              </label> // End of the label.
            ))}{/* End of the loop. */}
          </div>{/* End of the block. */}
          <p className="text-xs text-zinc-600">More places mean more tutors to choose from, though a match isn&apos;t guaranteed.</p>{/* A note that more places mean more tutors. */}
        </> // End of the group.
      ) : ( // Otherwise:
        <input type="hidden" name="keep_places" value="1" /> // tells the server to keep the places as they are (hidden).
      )}{/* End of this part. */}
      <fieldset className="space-y-2 rounded-lg border border-amber-200 bg-amber-50 p-3">{/* An amber group box: */}
        <legend className="px-1 text-sm font-medium text-amber-900">Preferred days and times (optional: a preference, not a guarantee)</legend>{/* its title, */}
        <label className={box}>{/* a label: */}
          <input type="checkbox" name="preferred_school_hours" defaultChecked={schoolHours} className="mt-1" /> During school
          hours (9am to 3pm, weekdays), for example for home schooling{/* (a school hours tick box) */}
        </label>{/* End of the label. */}
        <div className="flex flex-wrap gap-x-4 gap-y-2">{/* A row: */}
          {days.map((d, i) => ( // for each day:
            <label key={d} className={box}>{/* a label: */}
              <input type="checkbox" name="preferred_day" value={i + 1} defaultChecked={preferredDays.includes(i + 1)} className="mt-1" />{" "}{/* a tick box for the day (ticked if preferred), then a space, */}
              {d}{/* the day's name. */}
            </label> // End of the label.
          ))}{/* End of the loop. */}
        </div>{/* End of the block. */}
        <div className="flex flex-wrap gap-x-4 gap-y-2">{/* A row: */}
          {[ // for each part of the day:
            ["morning", "Morning (before 11am)"], // morning,
            ["midday", "Middle of the day (11am to 2pm)"], // middle of the day,
            ["afternoon", "Afternoon (2pm to 5pm)"], // afternoon,
            ["evening", "Evening (from 5pm)"], // evening,
          ].map(([v, label]) => ( // (the list, for each one:)
            <label key={v} className={box}>{/* a label: */}
              <input type="checkbox" name="preferred_part" value={v} defaultChecked={preferredParts.includes(v)} className="mt-1" />{" "}{/* a tick box (ticked if preferred), then a space, */}
              {label}{/* its words. */}
            </label> // End of the label.
          ))}{/* End of the loop. */}
        </div>{/* End of the block. */}
        <p className="text-xs text-amber-900">{/* An amber note: */}
          These are preferences, not guarantees. They may not be met: it depends on which tutors are free. We&apos;ll
          offer matching times first. If none are available, we&apos;ll offer the closest time we can, and you can say if
          it doesn&apos;t suit.{/* (that preferences aren't guaranteed) */}
        </p>{/* End of the paragraph. */}
      </fieldset>{/* End of the group box. */}
      <TextArea // A big text box:
        label="Tutor preferences (optional)" // labelled "Tutor preferences",
        name="tutor_preferences" // sent as tutor_preferences,
        maxLength={1000} // up to 1000 letters,
        rows={2} // two rows high,
        defaultValue={tutorPreferences} // filled with what's saved,
        hint="For example, experience with dyslexia or exam preparation. CLG reads this when choosing a tutor; it's a preference, not a guarantee. Please don't ask for things like gender, age, religion or background." // with examples and what not to ask for.
      />{/* (end of the element) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of StudentPlacesForm.
