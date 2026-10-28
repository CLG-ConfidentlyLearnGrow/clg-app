"use client";

import { startTransition, useActionState, useState, type ReactNode } from "react";
import {
  addAwayDates,
  addLibrary,
  addTerm,
  answerRenewal,
  joinWaitlist,
  answerBooking,
  cancelSession,
  confirmTimes,
  recordEndTime,
  saveNoticeSettings,
  recordOutcome,
  requestBooking,
  saveTutorPlaces,
  signOn,
  stopBooking,
} from "@/app/actions/scheduling";
import { ActionForm } from "@/components/action-form";
import { Button, Field, FormMessage, Select, TextArea } from "@/components/ui";
import { initialFormState, type FormState } from "@/lib/forms";

type Action = (prev: FormState, formData: FormData) => Promise<FormState>;

// A small form with its own buttons (for example Accept and Decline). The
// button pressed is sent with the form.
function ButtonsForm({ action, children }: { action: Action; children: (pending: boolean) => ReactNode }) {
  const [state, formAction, pending] = useActionState(action, initialFormState);
  return (
    <form action={formAction} className="space-y-3">
      <FormMessage state={state} />
      {children(pending)}
    </form>
  );
}

const quietButton =
  "rounded-full border border-zinc-300 bg-white px-4 py-2 text-sm text-zinc-800 transition hover:border-teal-700 hover:text-teal-800 disabled:opacity-50";

// "Book this time": the family chooses the dates and can add a note.
export function BookForm({
  option,
  defaultFirst,
  defaultLast,
}: {
  option: {
    student_id: string;
    subject: string;
    tutor_id: string;
    weekday: number;
    start_time: string;
    minutes: number;
    delivery: string;
    library_id: string | null;
  };
  defaultFirst: string;
  defaultLast: string;
}) {
  const [open, setOpen] = useState(false);
  if (!open) {
    return (
      <button type="button" className={quietButton} onClick={() => setOpen(true)}>
        Choose this time
      </button>
    );
  }
  return (
    <div className="mt-3 w-full rounded-xl bg-zinc-50 p-4">
      <ActionForm action={requestBooking} submitLabel="Send request to tutor">
        {Object.entries(option).map(([k, v]) => (
          <input key={k} type="hidden" name={k} value={v ?? ""} />
        ))}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="First week from" name="first_date" type="date" defaultValue={defaultFirst} min={defaultFirst} required />
          <Field
            label="Last date"
            name="last_date"
            type="date"
            defaultValue={defaultLast}
            min={defaultFirst}
            required
            hint="Bookings can run across terms, up to a year."
          />
        </div>
        <TextArea label="Note for the tutor (optional)" name="note" maxLength={1000} rows={2} />
        <p className="text-xs text-zinc-600">
          This books the time each week, subject to the tutor confirming within 48 hours.
        </p>
      </ActionForm>
    </div>
  );
}

export function AnswerForm({ bookingId }: { bookingId: string }) {
  return (
    <ButtonsForm action={answerBooking}>
      {(pending) => (
        <>
          <input type="hidden" name="booking_id" value={bookingId} />
          <TextArea label="Note to the family (optional)" name="note" maxLength={1000} rows={2} />
          <div className="flex flex-wrap gap-2">
            <Button type="submit" name="answer" value="accept" disabled={pending}>
              Accept
            </Button>
            <button type="submit" name="answer" value="decline" disabled={pending} className={quietButton}>
              Decline
            </button>
          </div>
        </>
      )}
    </ButtonsForm>
  );
}

// Cancel one session, or stop a whole booking. Admins say who asked, which
// decides credits and pay.
export function CancelForm({ id, kind, isAdmin }: { id: string; kind: "session" | "booking"; isAdmin: boolean }) {
  const [open, setOpen] = useState(false);
  if (!open) {
    return (
      <button type="button" className="text-xs text-red-700 underline" onClick={() => setOpen(true)}>
        {kind === "session" ? "Cancel" : "Stop booking"}
      </button>
    );
  }
  return (
    <div className="mt-2 w-full rounded-xl bg-zinc-50 p-4">
      <ActionForm
        action={kind === "session" ? cancelSession : stopBooking}
        submitLabel={kind === "session" ? "Cancel this session" : "Stop booking and cancel future sessions"}
      >
        <input type="hidden" name="id" value={id} />
        <Field label="Reason (optional)" name="reason" maxLength={500} />
        {isAdmin && (
          <Select label="Who asked?" name="on_behalf" defaultValue="family">
            <option value="family">The family</option>
            <option value="tutor">The tutor</option>
            <option value="admin">CLG</option>
          </Select>
        )}
        {!isAdmin && (
          <p className="text-xs text-zinc-600">
            Family cancellations: more than 24 hr before gets a full credit, 24 to 2 hr before gets a 50% credit, and
            under 2 hr gets no credit.
          </p>
        )}
      </ActionForm>
    </div>
  );
}

export function OutcomeForm({ id }: { id: string }) {
  return (
    <ButtonsForm action={recordOutcome}>
      {(pending) => (
        <div className="flex flex-wrap gap-2">
          <input type="hidden" name="id" value={id} />
          <button type="submit" name="outcome" value="completed" disabled={pending} className={quietButton}>
            Done
          </button>
          <button type="submit" name="outcome" value="no_show" disabled={pending} className={quietButton}>
            No-show
          </button>
        </div>
      )}
    </ButtonsForm>
  );
}

export function PlacesForm({
  libraries,
  chosen,
  settings,
}: {
  libraries: { id: string; name: string; suburb: string | null }[];
  chosen: string[];
  settings: { online: boolean; in_person: boolean; learning_support: boolean };
}) {
  const box = "flex items-start gap-2 text-sm";
  return (
    <ActionForm action={saveTutorPlaces} submitLabel="Save">
      <fieldset className="space-y-2">
        <legend className="mb-1 text-sm font-medium text-zinc-800">How you teach</legend>
        <label className={box}>
          <input type="checkbox" name="online" defaultChecked={settings.online} className="mt-1" /> Online
        </label>
        <label className={box}>
          <input type="checkbox" name="in_person" defaultChecked={settings.in_person} className="mt-1" /> In person, at
          the libraries ticked below
        </label>
        <label className={box}>
          <input type="checkbox" name="learning_support" defaultChecked={settings.learning_support} className="mt-1" />
          I have experience with learning difficulties
        </label>
      </fieldset>
      <fieldset className="space-y-2">
        <legend className="mb-1 text-sm font-medium text-zinc-800">Libraries you can work at</legend>
        {libraries.length === 0 && <p className="text-sm text-zinc-500">CLG hasn&apos;t added any libraries yet.</p>}
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          {libraries.map((l) => (
            <label key={l.id} className={box}>
              <input type="checkbox" name="library" value={l.id} defaultChecked={chosen.includes(l.id)} className="mt-1" />
              <span>
                {l.name}
                {l.suburb && <span className="text-zinc-500"> · {l.suburb}</span>}
              </span>
            </label>
          ))}
        </div>
        <p className="text-xs text-zinc-600">
          You&apos;ll stay at one library for the day. Online sessions can be taken from the library on library days.
        </p>
      </fieldset>
    </ActionForm>
  );
}

export function LibraryForm() {
  return (
    <ActionForm action={addLibrary} submitLabel="Add library">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="Library name" name="name" required maxLength={200} />
        <Field label="Suburb" name="suburb" maxLength={100} />
      </div>
      <Field label="Address (optional)" name="address" maxLength={300} />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="Latitude" name="latitude" inputMode="decimal" placeholder="-34.9285" />
        <Field label="Longitude" name="longitude" inputMode="decimal" placeholder="138.6007" />
      </div>
      <p className="text-xs text-zinc-600">
        Used for the tutor&apos;s sign-on check (within 300 m). Find them by right-clicking the library in Google Maps.
      </p>
    </ActionForm>
  );
}

export function AwayForm({ choices, today }: { choices: { value: string; label: string }[]; today: string }) {
  return (
    <ActionForm action={addAwayDates} submitLabel="Save away dates">
      <Select label="Who will be away?" name="who" defaultValue={choices[0]?.value}>
        {choices.map((c) => (
          <option key={c.value} value={c.value}>
            {c.label}
          </option>
        ))}
      </Select>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="First day away" name="from_date" type="date" min={today} required />
        <Field label="Last day away" name="to_date" type="date" min={today} required />
      </div>
      <Field label="Reason (optional)" name="reason" maxLength={300} hint="For example: family holiday, school camp." />
    </ActionForm>
  );
}

export function WaitlistForm({ request }: { request: Record<string, string | number> }) {
  return (
    <ActionForm action={joinWaitlist} submitLabel="Join the waitlist">
      {Object.entries(request).map(([k, v]) => (
        <input key={k} type="hidden" name={k} value={v} />
      ))}
      <TextArea label="Anything CLG should know? (optional)" name="note" maxLength={1000} rows={2} />
    </ActionForm>
  );
}

// Sign on to a session. For a library session the app asks the browser for
// the tutor's position once, with their permission; it's compared with the
// library and not kept.
export function SignOnForm({ id, atLibrary }: { id: string; atLibrary: boolean }) {
  const [state, formAction, pending] = useActionState(signOn, initialFormState);
  const [locating, setLocating] = useState(false);

  function withPosition(event: React.FormEvent<HTMLFormElement>) {
    if (!atLibrary) return;
    event.preventDefault();
    const form = event.currentTarget;
    const data = new FormData(form);
    const send = () => startTransition(() => formAction(data));
    if (!("geolocation" in navigator)) return send();
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        data.set("latitude", String(pos.coords.latitude));
        data.set("longitude", String(pos.coords.longitude));
        setLocating(false);
        send();
      },
      () => {
        setLocating(false);
        send();
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 },
    );
  }

  if (state.message) return <FormMessage state={state} />;
  return (
    <form action={formAction} onSubmit={withPosition} className="space-y-2">
      <FormMessage state={state} />
      <input type="hidden" name="id" value={id} />
      <Button type="submit" disabled={pending || locating}>
        {locating ? "Checking location…" : pending ? "Signing on…" : "Sign on"}
      </Button>
      {atLibrary && (
        <p className="text-xs text-zinc-600">
          Your phone will ask to share your location once. CLG only keeps whether you were at the library.
        </p>
      )}
    </form>
  );
}

export function EndTimeForm({ id, date, bookedEnd }: { id: string; date: string; bookedEnd: string }) {
  const [open, setOpen] = useState(false);
  if (!open) {
    return (
      <button type="button" className="text-xs text-teal-800 underline" onClick={() => setOpen(true)}>
        Finished at a different time?
      </button>
    );
  }
  return (
    <div className="mt-2 w-full rounded-xl bg-zinc-50 p-4">
      <ActionForm action={recordEndTime} submitLabel="Send to CLG">
        <input type="hidden" name="id" value={id} />
        <input type="hidden" name="date" value={date} />
        <Field label="Time you finished" name="end_time" type="time" defaultValue={bookedEnd} required />
        <Field label="Why was it different?" name="note" maxLength={500} required />
      </ActionForm>
    </div>
  );
}

export function ConfirmTimesForm({ id, date, from, to }: { id: string; date: string; from: string; to: string }) {
  return (
    <ActionForm action={confirmTimes} submitLabel="Confirm times">
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="date" value={date} />
      <div className="grid grid-cols-2 gap-4 sm:w-2/3">
        <Field label="From" name="from_time" type="time" defaultValue={from} required />
        <Field label="To" name="to_time" type="time" defaultValue={to} required />
      </div>
    </ActionForm>
  );
}

export function NoticeSettingsForm({
  settings,
}: {
  settings: { first_reminder_hours: number; by_email: boolean; by_text: boolean };
}) {
  return (
    <ActionForm action={saveNoticeSettings} submitLabel="Save">
      <Select label="First reminder" name="first_reminder_hours" defaultValue={String(settings.first_reminder_hours)}>
        {[2, 6, 12, 24, 48, 72, 168].map((h) => (
          <option key={h} value={h}>
            {h === 168 ? "1 week" : `${h} hr`} before
          </option>
        ))}
      </Select>
      <p className="text-xs text-zinc-600">A final reminder always comes 1 hr before. Nothing arrives between 8pm and 8am.</p>
      <fieldset className="space-y-2">
        <legend className="mb-1 text-sm font-medium text-zinc-800">Also send them by</legend>
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" name="by_email" defaultChecked={settings.by_email} className="mt-1" /> Email
        </label>
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" name="by_text" defaultChecked={settings.by_text} className="mt-1" /> Text message
        </label>
        <p className="text-xs text-zinc-600">Email and text reminders start once CLG switches them on.</p>
      </fieldset>
    </ActionForm>
  );
}

// Next term: same again, holidays, and what to change if not.
export function RenewalForm({ id }: { id: string }) {
  const [sameAgain, setSameAgain] = useState("");
  return (
    <ActionForm action={answerRenewal} submitLabel="Send answer">
      <input type="hidden" name="id" value={id} />
      <fieldset className="space-y-2">
        <legend className="mb-1 text-sm font-medium text-zinc-800">Same time and tutor next term?</legend>
        <label className="flex items-start gap-2 text-sm">
          <input type="radio" name="same_again" value="yes" required onChange={() => setSameAgain("yes")} className="mt-1" />{" "}
          Yes, the same again
        </label>
        <label className="flex items-start gap-2 text-sm">
          <input type="radio" name="same_again" value="no" onChange={() => setSameAgain("no")} className="mt-1" />{" "}
          No, something different
        </label>
      </fieldset>
      {sameAgain === "no" && (
        <>
          <Select label="What would you like to change?" name="change_what" defaultValue="time">
            <option value="time">Day and time</option>
            <option value="tutor">Tutor</option>
            <option value="both">Both</option>
          </Select>
          <TextArea label="Why? (helps us find a better fit)" name="change_reason" maxLength={1000} rows={2} />
        </>
      )}
      <fieldset className="space-y-2">
        <legend className="mb-1 text-sm font-medium text-zinc-800">Sessions in the school holidays?</legend>
        <label className="flex items-start gap-2 text-sm">
          <input type="radio" name="holidays" value="yes" required className="mt-1" /> Yes, keep going in the holidays
        </label>
        <label className="flex items-start gap-2 text-sm">
          <input type="radio" name="holidays" value="no" className="mt-1" /> No, pause for the holidays
        </label>
      </fieldset>
      <TextArea label="How is it going? (optional)" name="feedback" maxLength={2000} rows={3} />
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" name="testimonial_ok" className="mt-1" /> CLG may share my feedback as a testimonial
        (first name only)
      </label>
    </ActionForm>
  );
}

export function TermForm() {
  return (
    <ActionForm action={addTerm} submitLabel="Save term">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Select label="State" name="state" defaultValue="SA">
          {["SA", "NSW", "VIC", "QLD", "WA", "TAS", "ACT", "NT"].map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
        <Select label="Term" name="term" defaultValue="1">
          {[1, 2, 3, 4].map((t) => (
            <option key={t} value={t}>
              Term {t}
            </option>
          ))}
        </Select>
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="First day" name="starts_on" type="date" required />
        <Field label="Last day" name="ends_on" type="date" required />
      </div>
      <p className="text-xs text-zinc-600">Saving a term that already exists replaces its dates.</p>
    </ActionForm>
  );
}
