// Summary: the public "Apply to tutor" form. It sends the answers (and an
// optional CV) to the server, keeps everything typed if there's a problem,
// and shows a thank-you note once the application is sent.
//
"use client"; // Runs in the browser, so the form can keep answers and show the reply.

import { useState, useTransition, type FormEvent } from "react"; // React's memory, busy-state and form event helpers.
import { submitTutorApplication } from "@/app/actions/tutor-applications"; // The server action that saves the application.
import { StateSelect } from "@/components/state-select"; // A list to pick the state.
import { Field, FormMessage, Select, SubHeading, TextArea, TextLink } from "@/components/ui"; // Form boxes, headings, messages and links.
import { STATES, STATE_NAMES } from "@/lib/checks"; // The Australian states and their names.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import {
  FIRST_AID_STATUSES, // The first aid answers.
  FIRST_AID_STATUS_NAMES, // Their words.
  RRHAN_STATUSES, // The RRHAN-EC answers.
  RRHAN_STATUS_NAMES, // Their words.
  TEACH_MODES, // How someone can teach.
  TEACH_MODE_NAMES, // Their words.
  WWCC_STATUSES, // The Working with Children Check answers.
  WWCC_STATUS_NAMES, // Their words.
} from "@/lib/tutor-applications"; // (shared words for applications)

// The form. "started" is the signed "form opened at" stamp from the server.
export function ApplyForm({ started }: { started: string }) {
  const [state, setState] = useState<FormState>({}); // The latest reply (error or thanks).
  const [pending, startTransition] = useTransition(); // Whether the application is being sent.
  const [wwcc, setWwcc] = useState<string>("held"); // The Working with Children Check answer, to show or hide its details.

  // Sends the application. Done by hand (not the form's own sending) so the
  // browser never clears a long form when there's a problem to fix.
  function onSubmit(e: FormEvent<HTMLFormElement>) { // Runs when the form is sent (after the browser's own checks pass).
    e.preventDefault(); // Stops the browser sending it the usual way.
    const data = new FormData(e.currentTarget); // Every answer, including the CV.
    startTransition(async () => { // While sending (the button shows it's busy):
      const reply = await submitTutorApplication({}, data); // sends the application,
      setState(reply); // and shows the reply.
      if (reply.message) window.scrollTo({ top: 0, behavior: "smooth" }); // On success, scrolls up to the thank-you note.
    }); // End of sending.
  } // End of onSubmit.

  if (state.message) { // Sent:
    return ( // shows a thank-you note instead of the form:
      <div role="status" className="space-y-3 rounded-xl border border-teal-200 bg-teal-50 px-5 py-4 text-sm text-teal-900">{/* a green box read out by screen readers: */}
        <p className="font-semibold">{state.message}</p>{/* the thanks, */}
        <p>We read every application and will be in touch, usually within two weeks. If you&apos;re shortlisted, we&apos;ll invite you to an interview and contact your referees.</p>{/* what happens next, */}
        <p><TextLink href="/">Back to the CLG home page</TextLink></p>{/* and a way back. */}
      </div> // End of the box.
    ); // End of what's shown.
  } // End of the sent case.

  return ( // Otherwise shows the form:
    <form onSubmit={onSubmit} className="space-y-4">{/* the form, */}
      <input type="hidden" name="started" value={started} />{/* the signed "form opened at" stamp (spam check), */}
      {/* A box people never see: bots fill in every box, so anything typed here marks a bot. */}
      <div aria-hidden="true" className="absolute -left-[9999px] h-px w-px overflow-hidden">
        <label>{/* (its label:) */}
          Website (leave this empty){/* its words, */}
          <input type="text" name="website" tabIndex={-1} autoComplete="off" defaultValue="" />{/* and the box (skipped by the Tab key). */}
        </label>{/* End of the label. */}
      </div>{/* End of the hidden box. */}

      <SubHeading>About you</SubHeading>{/* The "About you" part: */}
      <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label="First name" name="first_name" autoComplete="given-name" required maxLength={100} />{/* first name, */}
        <Field label="Last name" name="last_name" autoComplete="family-name" required maxLength={100} />{/* last name, */}
        <Field label="Email" name="email" type="email" autoComplete="email" required maxLength={254} />{/* email, */}
        <Field label="Phone" name="phone" type="tel" autoComplete="tel" required minLength={6} maxLength={30} />{/* phone, */}
        <StateSelect label="State you live in" />{/* state, */}
        <Field label="Suburb or town" name="suburb" autoComplete="address-level2" required maxLength={100} />{/* suburb or town. */}
      </div>{/* End of the columns. */}
      <Select label="How would you like to tutor?" name="teach_mode" required defaultValue="">{/* In person, online or both: */}
        <option value="" disabled>Choose one</option>{/* a prompt, */}
        {TEACH_MODES.map((m) => <option key={m} value={m}>{TEACH_MODE_NAMES[m]}</option>)}{/* and each choice. */}
      </Select>{/* End of the list. */}
      <fieldset className="space-y-1">{/* Right to work: */}
        <legend className="text-sm font-medium text-zinc-800">Do you have the right to work in Australia?</legend>{/* the question, */}
        <div className="flex gap-6 text-sm">{/* two choices side by side: */}
          <label className="flex items-center gap-2"><input type="radio" name="right_to_work" value="yes" required /> Yes</label>{/* yes, */}
          <label className="flex items-center gap-2"><input type="radio" name="right_to_work" value="no" /> No</label>{/* no. */}
        </div>{/* End of the choices. */}
      </fieldset>{/* End of the question. */}

      <SubHeading>What and when you can teach</SubHeading>{/* The teaching part: */}
      <TextArea // subjects:
        label="Subjects and year levels" // its words,
        name="subjects" // its name,
        required // must be filled in,
        minLength={3} // at least a few letters,
        maxLength={2000} // up to 2,000 characters,
        hint="For example: Mathematics Years 7 to 10, Chemistry Year 11 and 12, English Year 3 to 6." // an example.
      />{/* End of subjects. */}
      <TextArea // availability:
        label="When are you free?" // its words,
        name="availability" // its name,
        required // must be filled in,
        minLength={3} // at least a few letters,
        maxLength={1000} // up to 1,000 characters,
        hint="Days and times, for example: Monday and Wednesday after 3:30pm, Saturday mornings." // an example.
      />{/* End of availability. */}
      <Field label="Hours a week you'd like (optional)" name="weekly_hours" type="number" min={1} max={40} step={1} inputMode="numeric" />{/* hours a week. */}

      <SubHeading>Qualifications and experience</SubHeading>{/* The background part: */}
      <TextArea // qualifications:
        label="Qualifications" // its words,
        name="qualifications" // its name,
        required // must be filled in,
        minLength={3} // at least a few letters,
        maxLength={3000} // up to 3,000 characters,
        hint="Degrees, current study (with your year), teaching qualifications, and anything else relevant." // what to include.
      />{/* End of qualifications. */}
      <Field label="Teacher registration number (optional)" name="teacher_registration" maxLength={100} hint="If you're a registered teacher, for example with the Teachers Registration Board of SA." />{/* teacher registration, */}
      <TextArea // experience:
        label="Teaching or tutoring experience" // its words,
        name="experience" // its name,
        required // must be filled in,
        minLength={3} // at least a few letters,
        maxLength={3000} // up to 3,000 characters,
        rows={4} // four lines tall,
        hint="Where, who with (ages and year levels), and for how long. Coaching, mentoring and volunteering count too." // what to include.
      />{/* End of experience. */}

      <SubHeading>Child safety checks</SubHeading>{/* The checks part: */}
      <p className="text-sm text-zinc-600">{/* a note: */}
        Everyone who tutors with CLG needs a current Working with Children Check and RRHAN-EC training before working with students. First aid is encouraged. If you don&apos;t have these yet, you can still apply: we&apos;ll help you get them.{/* what's needed, and that they can still apply. */}
      </p>{/* End of the note. */}
      <Select label="Working with Children Check" name="wwcc_status" required value={wwcc} onChange={(e) => setWwcc(e.target.value)}>{/* The check answer: */}
        {WWCC_STATUSES.map((s) => <option key={s} value={s}>{WWCC_STATUS_NAMES[s]}</option>)}{/* each choice. */}
      </Select>{/* End of the list. */}
      {wwcc === "held" && ( // If they have one:
        <div className="grid gap-4 sm:grid-cols-3">{/* three boxes across on wider screens: */}
          <Field label="Check number" name="wwcc_number" maxLength={50} />{/* its number, */}
          <Select label="State that issued it" name="wwcc_state" defaultValue="SA">{/* its state: */}
            {STATES.map((s) => <option key={s} value={s}>{STATE_NAMES[s]}</option>)}{/* each state. */}
          </Select>{/* End of the list. */}
          <Field label="Expiry date" name="wwcc_expiry" type="date" />{/* its expiry. */}
        </div> // End of the boxes.
      )}{/* End of the check details. */}
      <div className="grid gap-4 sm:grid-cols-2">{/* two lists side by side: */}
        <Select label="RRHAN-EC training (Fundamentals and Masterclass)" name="rrhan_ec_status" required defaultValue="">{/* RRHAN-EC: */}
          <option value="" disabled>Choose one</option>{/* a prompt, */}
          {RRHAN_STATUSES.map((s) => <option key={s} value={s}>{RRHAN_STATUS_NAMES[s]}</option>)}{/* and each choice. */}
        </Select>{/* End of the list. */}
        <Select label="First aid certificate" name="first_aid_status" required defaultValue="">{/* First aid: */}
          <option value="" disabled>Choose one</option>{/* a prompt, */}
          {FIRST_AID_STATUSES.map((s) => <option key={s} value={s}>{FIRST_AID_STATUS_NAMES[s]}</option>)}{/* and each choice. */}
        </Select>{/* End of the list. */}
      </div>{/* End of the lists. */}

      <SubHeading>Two referees</SubHeading>{/* The referees part: */}
      <p className="text-sm text-zinc-600">{/* a note: */}
        At least one should be a recent supervisor or manager. Ideally, one has seen you work with children or young people. Please don&apos;t use family members.{/* who makes a good referee. */}
      </p>{/* End of the note. */}
      {[1, 2].map((n) => ( // For each of the two referees:
        <fieldset key={n} className="space-y-3 rounded-xl border border-zinc-200 p-4">{/* a bordered group: */}
          <legend className="px-1 text-sm font-medium text-zinc-800">Referee {n}</legend>{/* its heading, */}
          <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
            <Field label="Name" name={`ref${n}_name`} required minLength={2} maxLength={200} />{/* their name, */}
            <Field label="How they know you" name={`ref${n}_relationship`} required minLength={2} maxLength={300} hint="For example: my manager at ... for 2 years." />{/* how they know them, */}
            <Field label="Email" name={`ref${n}_email`} type="email" maxLength={254} />{/* their email, */}
            <Field label="Phone" name={`ref${n}_phone`} type="tel" maxLength={30} hint="Give an email, a phone number, or both." />{/* their phone. */}
          </div>{/* End of the columns. */}
        </fieldset> // End of the group.
      ))}{/* End of the referees. */}
      <label className="flex items-start gap-2 text-sm">{/* Referee permission: */}
        <input type="checkbox" name="referee_consent" required className="mt-1" />{/* a tick box that must be ticked, */}
        <span>My referees know I&apos;ve named them and are happy for CLG to contact them.</span>{/* and its words. */}
      </label>{/* End of the line. */}

      <SubHeading>In your own words</SubHeading>{/* The statement part: */}
      <TextArea // why CLG:
        label="Why would you like to tutor with CLG?" // its words,
        name="statement" // its name,
        required // must be filled in,
        minLength={30} // at least a sentence or two,
        maxLength={3000} // up to 3,000 characters,
        rows={4} // four lines tall,
      />{/* End of the statement. */}
      <TextArea // a time they helped:
        label="Tell us about a time you helped a young person understand something they found difficult." // its words,
        name="helped_example" // its name,
        required // must be filled in,
        minLength={30} // at least a sentence or two,
        maxLength={3000} // up to 3,000 characters,
        rows={4} // four lines tall,
        hint="What was hard for them, what you did, and how you knew it had worked. Please leave out the young person's name." // what to include.
      />{/* End of the example. */}
      <Field label="How did you hear about CLG? (optional)" name="heard_from" maxLength={200} />{/* how they heard. */}
      <label className="block space-y-1">{/* The CV: */}
        <span className="text-sm font-medium text-zinc-800">Your CV (optional, PDF)</span>{/* its words, */}
        <input type="file" name="cv" accept="application/pdf" className="block w-full text-sm" />{/* the file picker (PDFs only), */}
        <span className="block text-xs text-zinc-500">Up to 3.5MB. In Word, choose File, then Save as, then PDF.</span>{/* and help. */}
      </label>{/* End of the CV. */}

      <SubHeading>Declarations</SubHeading>{/* The declarations part: */}
      <label className="flex items-start gap-2 text-sm">{/* The first declaration: */}
        <input type="checkbox" name="declared_true" required className="mt-1" />{/* a tick box that must be ticked, */}
        <span>The information in this application is true and complete. I agree CLG may contact my referees and verify my Working with Children Check and other checks.</span>{/* and its words. */}
      </label>{/* End of the line. */}
      <label className="flex items-start gap-2 text-sm">{/* The second declaration: */}
        <input type="checkbox" name="declared_suitable" required className="mt-1" />{/* a tick box that must be ticked, */}
        <span>I am not prohibited from working with children, and I know of no reason I would be unsuitable to work with children and young people.</span>{/* and its words. */}
      </label>{/* End of the line. */}

      <FormMessage state={state} />{/* Any problem, shown next to the button so it's seen. */}
      <button // the send button:
        type="submit" // sends the form,
        disabled={pending} // switched off while sending,
        className="rounded-full bg-teal-700 px-6 py-3 text-sm font-medium text-white shadow-sm transition hover:bg-teal-800 disabled:opacity-60" // a filled button, faded while busy,
      >{/* (end of the button's settings) */}
        {pending ? "Sending…" : "Send my application"}{/* its words ("Sending…" while busy). */}
      </button>{/* End of the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of ApplyForm.
