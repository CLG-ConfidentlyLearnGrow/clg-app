"use client";

import { useActionState, useState, type ReactNode } from "react";
import {
  addLibrary,
  answerBooking,
  cancelSession,
  recordOutcome,
  requestBooking,
  saveTutorPlaces,
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
    </ActionForm>
  );
}
