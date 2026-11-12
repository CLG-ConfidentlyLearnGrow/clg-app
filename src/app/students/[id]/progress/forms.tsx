// Summary: the forms on a student's progress page: goals, session notes,
// the student's reflection, family notes, the roadmap, term reviews,
// uploads (evidence) and senior (SACE) subjects. Each form sends its answers
// to a server action in actions/progress.ts.
//
"use client"; // Marks this file as code that runs in the browser.

import { useRef, type ReactNode } from "react"; // React tools: a value that survives re-draws, and the type for "anything that can be shown".
import { // The server actions these forms send to:
  addEvidence, // add an upload,
  addSeniorSubject, // add a senior subject,
  addGoal, // add a goal,
  addRoadmapStep, // add a roadmap step,
  addRoadmapTarget, // add a roadmap target,
  checkTermReview, // CLG checks a term review,
  replyTermReview, // the family replies to a term review,
  reviewEvidence, // the tutor reviews an upload,
  saveTermReview, // save a term review,
  saveFamilyNote, // save a family note,
  saveReflection, // save a student's reflection,
  saveSessionNote, // save a session note,
  updateSeniorSubject, // update a senior subject.
} from "@/app/actions/progress"; // (from the progress actions file)
import { ActionForm } from "@/components/action-form"; // The form wrapper that shows errors and a submit button.
import { Field, Select, TextArea } from "@/components/ui"; // Shared form parts: a text box, a drop-down and a big text box.
import { DOCUMENT_ACCEPT } from "@/lib/documents"; // The file types allowed for uploads.
import { // Names and lists from the progress helpers:
  ATTENDANCE, // attendance choices,
  ATTENDANCE_NAMES, // their names,
  CONFIDENCE_NAMES, // confidence names,
  EVIDENCE_KINDS, // upload kinds,
  EVIDENCE_KIND_NAMES, // their names,
  PARENT_ONLY_KINDS, // kinds only parents can add,
  SENIOR_AREA_NAMES, // senior subject area names,
  RECOMMENDATION_NAMES, // recommendation names,
  SKILL_LEVEL_NAMES, // skill level names,
  nextLevels, // which levels a skill can move to next,
  type SkillLevel, // and the type for a skill level.
} from "@/lib/progress"; // (from the progress helpers file)

// A skill the tutor can tick when adding a goal: its id, words, year band, and whether it starts ticked.
export type SkillOption = { id: string; label: string; levelBand: string; ticked?: boolean }; // (the shape)
// A skill inside a goal: its id, words, current level, and the goal it belongs to.
export type GoalSkill = { id: string; label: string; level: SkillLevel; goal: string }; // (the shape)
// A booked session the note is for: its date and length fill in by themselves.
export type NoteSession = { id: string; date: string; minutes: number; label: string }; // (the shape: its id, date, minutes and a label to show)

// Times how long the note takes, from the first tap in the form to the last
// change, so CLG can check notes stay under three minutes. Only admins see
// the result.
function WritingTimer({ children }: { children: ReactNode }) { // Wraps the note form and records the seconds spent writing.
  const started = useRef<number | null>(null); // When writing started (none yet).
  const out = useRef<HTMLInputElement>(null); // The hidden box that holds the seconds.
  const tick = () => { // Runs on every tap or change in the form:
    const now = Date.now(); // the time now,
    // After a note is saved the form clears, so the next one starts afresh.
    if (started.current === null || out.current?.value === "") started.current = now; // starts the clock on the first tap, or again after a save,
    if (out.current) out.current.value = String(Math.round((now - started.current) / 1000)); // and writes the seconds so far into the hidden box.
  }; // End of tick.
  return ( // Shows:
    <div className="space-y-4" onFocusCapture={tick} onInputCapture={tick} onChangeCapture={tick}>{/* a block that runs tick on every tap or change inside it, */}
      <input type="hidden" name="writing_seconds" ref={out} defaultValue="" />{/* the hidden seconds box (sent with the form), */}
      {children}{/* and the form's own parts. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of WritingTimer.

// The form for adding a learning goal and ticking the skills it covers.
export function AddGoalForm({ // Its settings:
  studentId, // the student,
  subject, // the subject,
  skills, // the skills to choose from,
  startLevel, // and the level to start ticked, if any.
}: { // The settings' types:
  studentId: string; // student id is text,
  subject: string; // subject is text,
  skills: SkillOption[]; // skills is a list of skill choices,
  startLevel?: string | null; // start level is text, nothing, or left out.
}) { // End of the settings.
  return ( // Shows:
    <ActionForm action={addGoal} submitLabel="Add goal">{/* the form, sending to addGoal, with an "Add goal" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <input type="hidden" name="subject" value={subject} />{/* the subject (hidden), */}
      <Field // a text box:
        label="Goal" // labelled "Goal",
        name="title" // sent as title,
        required // must be filled in,
        maxLength={200} // up to 200 letters,
        hint='Write it so a parent understands, for example "Solve two-step equations without prompts".' // with an example of how to write it.
      />{/* (end of the element) */}
      <Field label="Aim to reach it by (optional)" name="target_date" type="date" />{/* An optional date to aim for. */}
      <fieldset className="space-y-1">{/* A group box for the skills: */}
        <legend className="mb-1 text-sm font-medium">Skills this goal covers</legend>{/* its title, */}
        <p className="text-xs text-zinc-500">{/* a small grey note: */}
          {startLevel // if there's a start level,
            ? `Skills at ${startLevel} (the level given for this subject) start ticked. Untick or add others to suit what the student is ready for.` // says those skills start ticked,
            : "Pick by what the student is ready for, not their year level. The year is shown for context only."}{" "}{/* otherwise says to pick by readiness, not year level, then a space. */}
          Skills may change in the first three sessions as you get to know the student.{/* Notes that skills may change early on. */}
        </p>{/* End of the paragraph. */}
        <div className="max-h-72 space-y-1 overflow-y-auto rounded-md border border-zinc-200 p-2">{/* A scrolling bordered box: */}
          {skills.map((s) => ( // for each skill:
            <label key={s.id} className="flex items-start gap-2 text-sm">{/* a label: */}
              <input type="checkbox" name="skill_id" value={s.id} defaultChecked={s.ticked} className="mt-1" />{/* a tick box for the skill (ticked if it should start ticked), */}
              <span>{/* the words: */}
                <span className="text-zinc-500">{s.levelBand}:</span> {s.label}{/* the year band in grey, then the skill. */}
              </span>{/* End of the text. */}
            </label> // End of the label.
          ))}{/* End of the loop. */}
        </div>{/* End of the block. */}
      </fieldset>{/* End of the group box. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AddGoalForm.

// A material that fits the student; skillIds are its skills that are in
// the student's goals.
export type NoteMaterial = { id: string; title: string; kind: string; skillIds: string[] }; // (the shape)

// Ticking a booklet marks its skills as worked on today (at their current
// level), so the tutor only changes the ones that moved.
function MaterialsUsed({ materials, levels }: { materials: NoteMaterial[]; levels: Map<string, SkillLevel> }) { // The list of materials to tick in a session note.
  const box = useRef<HTMLFieldSetElement>(null); // The group box, so the code can find the form it sits in.
  const sorted = [...materials].sort( // Sorts the materials:
    (a, b) => Number(b.kind === "booklet") - Number(a.kind === "booklet") || b.skillIds.length - a.skillIds.length, // booklets first, then those covering the most goal skills.
  ); // End of the sort.
  function picked(m: NoteMaterial, on: boolean) { // Runs when a material is ticked or unticked:
    if (!on) return; // unticked: does nothing.
    const form = box.current?.form; // The form the box sits in.
    for (const id of m.skillIds) { // For each of the material's skills:
      const select = form?.elements.namedItem(`skill_${id}`); // finds that skill's drop-down,
      if (select instanceof HTMLSelectElement && select.value === "") { // if it's still blank,
        select.value = levels.get(id) ?? "not_started"; // sets it to the skill's current level (worked on, no change).
      } // End of the blank check.
    } // End of the loop.
  } // End of picked.
  return ( // Shows:
    <fieldset ref={box} className="space-y-1">{/* the group box: */}
      <legend className="mb-1 text-sm font-medium">Booklet or materials used (optional)</legend>{/* its title, */}
      <p className="text-xs text-zinc-500">Tick what you worked through. Its skills below fill in by themselves.</p>{/* a note on what ticking does, */}
      <div className="max-h-48 space-y-1 overflow-y-auto rounded-md border border-zinc-200 p-2">{/* a scrolling bordered box: */}
        {sorted.map((m) => ( // for each material:
          <label key={m.id} className="flex items-start gap-2 text-sm">{/* a label: */}
            <input // a tick box:
              type="checkbox" // (a tick box)
              name="material_id" // sent as material_id,
              value={m.id} // with the material's id,
              className="mt-1" // nudged down to line up,
              onChange={(e) => picked(m, e.target.checked)} // filling in its skills when ticked.
            />{/* (end of the element) */}
            <span>{/* the words: */}
              {m.title}{/* the material's name, */}
              {m.skillIds.length > 0 && ( // if it covers goal skills:
                <span className="text-zinc-500">{/* in grey: */}
                  {" "}{/* a space, */}
                  ({m.skillIds.length} goal skill{m.skillIds.length === 1 ? "" : "s"}){/* how many goal skills it covers. */}
                </span> // End of the text.
              )}{/* End of this part. */}
            </span>{/* End of the text. */}
          </label> // End of the label.
        ))}{/* End of the loop. */}
      </div>{/* End of the block. */}
    </fieldset> // End of the group box.
  ); // End of what's shown.
} // End of MaterialsUsed.

// The tutor's note after a session: attendance, skills, what went well and next step.
export function SessionNoteForm({ // Its settings:
  studentId, // the student,
  skills, // the skills in the student's goals,
  materials = [], // the materials that fit (none by default),
  session, // the booked session, if any,
  today, // and today's date.
}: { // The settings' types:
  studentId: string; // student id is text,
  skills: GoalSkill[]; // skills is a list of goal skills,
  materials?: NoteMaterial[]; // materials is an optional list,
  session?: NoteSession | null; // session is optional (or nothing),
  today: string; // today is text.
}) { // End of the settings.
  const levels = new Map(skills.map((s) => [s.id, s.level])); // Each skill's current level, looked up by its id.
  return ( // Shows:
    <ActionForm action={saveSessionNote} submitLabel="Save note">{/* the form, sending to saveSessionNote, with a "Save note" button, */}
      <WritingTimer>{/* inside the writing timer: */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      {session && <input type="hidden" name="session_id" value={session.id} />}{/* the session (hidden), if there is one, */}
      {session && ( // if there's a session:
        <p className="rounded-xl bg-zinc-50 px-4 py-3 text-sm">{/* a shaded line: */}
          For the session on <strong>{session.label}</strong>.{/* saying which session it's for. */}
        </p> // End of the paragraph.
      )}{/* End of this part. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">{/* A row of three boxes on wider screens: */}
        {session ? ( // if there's a session:
          <input type="hidden" name="session_date" value={session.date} /> // its date is sent hidden,
        ) : ( // otherwise:
          <Field label="Session date" name="session_date" type="date" defaultValue={today} max={today} required /> // the tutor picks the date (today or earlier).
        )}{/* End of this part. */}
        <Field // A number box:
          label="Minutes" // labelled "Minutes",
          name="minutes" // sent as minutes,
          type="number" // a number,
          min={0} // at least 0,
          max={480} // at most 8 hr,
          step={5} // in 5-minute steps,
          defaultValue={session?.minutes ?? 60} // starting at the session's length, or 60,
          required // must be filled in.
        />{/* (end of the element) */}
        <Select label="Attendance" name="attendance" defaultValue="attended">{/* A drop-down for attendance, starting at "attended": */}
          {ATTENDANCE.map((a) => ( // for each attendance choice:
            <option key={a} value={a}>{/* a choice: */}
              {ATTENDANCE_NAMES[a]}{/* its name. */}
            </option> // End of the choice.
          ))}{/* End of the loop. */}
        </Select>{/* End of the Select. */}
      </div>{/* End of the block. */}

      {materials.length > 0 && <MaterialsUsed materials={materials} levels={levels} />}{/* The materials list, if any fit. */}

      {skills.length > 0 && ( // If the student has goal skills:
        <fieldset className="space-y-2">{/* a group box: */}
          <legend className="mb-1 text-sm font-medium">Skills worked on</legend>{/* its title, */}
          <p className="text-xs text-zinc-500">{/* a small grey note: */}
            Leave a skill blank if you didn&apos;t work on it. Each skill can stay where it is or move one step.{/* says to leave a skill blank if not worked on. */}
          </p>{/* End of the paragraph. */}
          {skills.map((s) => ( // For each skill:
            <label key={s.id} className="block space-y-1 text-sm">{/* a label: */}
              <span>{/* the words: */}
                {s.label} <span className="text-zinc-500">({s.goal})</span>{/* the skill, with its goal in grey. */}
              </span>{/* End of the text. */}
              <select // a drop-down:
                name={`skill_${s.id}`} // named for this skill,
                defaultValue="" // starting blank,
                className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none" // styled like the other boxes.
              >{/* (end of the settings) */}
                <option value="">Not worked on today</option>{/* A blank choice: not worked on. */}
                {nextLevels(s.level).map((l) => ( // For each level it can move to:
                  <option key={l} value={l}>{/* a choice: */}
                    {SKILL_LEVEL_NAMES[l]}{/* the level's name, */}
                    {l === s.level ? " (no change)" : ""}{/* marked "(no change)" if it's the current level. */}
                  </option> // End of the choice.
                ))}{/* End of the loop. */}
              </select>{/* End of the drop-down. */}
            </label> // End of the label.
          ))}{/* End of the loop. */}
        </fieldset> // End of the group box.
      )}{/* End of this part. */}

      <TextArea // A big text box:
        label="What went well" // labelled "What went well",
        name="went_well" // sent as went_well,
        maxLength={1000} // up to 1000 letters,
        hint="One or two sentences, written to the student. The family sees this as written." // with a note that the family sees it.
      />{/* (end of the element) */}
      <TextArea // A big text box:
        label="Next step" // labelled "Next step",
        name="next_step" // sent as next_step,
        maxLength={500} // up to 500 letters,
        hint="One specific thing for the student to do next, written to them. This matters most." // with a note on why it matters.
      />{/* (end of the element) */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">{/* A row of boxes: */}
        <div className="sm:col-span-2">{/* taking two of three columns: */}
          <Field label="Homework or practice (optional)" name="homework" maxLength={1000} />{/* homework (optional). */}
        </div>{/* End of the block. */}
        <Field label="Due (optional)" name="homework_due" type="date" />{/* and its due date (optional). */}
      </div>{/* End of the block. */}
      <Field // A text box:
        label="One thing to try at home (optional)" // labelled for a home tip,
        name="home_tip" // sent as home_tip,
        maxLength={300} // up to 300 letters,
        hint='For the family: a small habit, not re-teaching. For example, "Ask them to explain one fraction at dinner."' // with an example.
      />{/* (end of the element) */}
      <TextArea // A big text box:
        label="Note for CLG staff only (optional)" // labelled staff only,
        name="staff_note" // sent as staff_note,
        maxLength={4000} // up to 4000 letters,
        rows={2} // two rows high,
        hint="Never shown to the student or family. For a child safety concern, use the reporting route in the child safe policy, not this box." // with a reminder to use the child safety route for concerns.
      />{/* (end of the element) */}
      </WritingTimer>{/* End of the writing timer. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SessionNoteForm.

// The student's own reflection on a session note.
export function ReflectionForm({ studentId, noteId }: { studentId: string; noteId: string }) { // (takes the student and the note)
  return ( // Shows:
    <ActionForm action={saveReflection} submitLabel="Send to my tutor">{/* the form, sending to saveReflection, with a "Send to my tutor" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <input type="hidden" name="note_id" value={noteId} />{/* the note (hidden), */}
      <Select label="How confident do you feel about this work?" name="confidence" defaultValue="" required>{/* a required drop-down for confidence: */}
        <option value="" disabled>{/* a blank first choice that can't be picked: */}
          Choose…{/* "Choose…". */}
        </option>{/* End of the choice. */}
        {[1, 2, 3, 4].map((n) => ( // For 1 to 4:
          <option key={n} value={n}>{/* a choice: */}
            {CONFIDENCE_NAMES[n]}{/* its confidence name. */}
          </option> // End of the choice.
        ))}{/* End of the loop. */}
      </Select>{/* End of the Select. */}
      <Field label="What was hard? (optional)" name="what_was_hard" maxLength={500} />{/* What was hard (optional). */}
      <Field label="What will you try before next time? (optional)" name="what_i_will_try" maxLength={500} />{/* What they'll try next (optional). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of ReflectionForm.

// A note from the family to the tutor: progress at home, or feedback.
export function FamilyNoteForm({ studentId }: { studentId: string }) { // (takes the student)
  return ( // Shows:
    <ActionForm action={saveFamilyNote} submitLabel="Send">{/* the form, sending to saveFamilyNote, with a "Send" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <fieldset className="space-y-2">{/* a group box: */}
        <legend className="mb-1 text-sm font-medium">What is it?</legend>{/* its title, */}
        <div className="flex flex-wrap gap-x-6 gap-y-2 text-sm">{/* a row of choices: */}
          <label className="flex items-center gap-2">{/* a label: */}
            <input type="radio" name="kind" value="home_progress" defaultChecked required />{/* a round choice for progress at home (picked to start), */}
            Progress at home{/* its words. */}
          </label>{/* End of the label. */}
          <label className="flex items-center gap-2">{/* a label: */}
            <input type="radio" name="kind" value="feedback" />{/* a round choice for feedback, */}
            Feedback{/* its words. */}
          </label>{/* End of the label. */}
        </div>{/* End of the block. */}
      </fieldset>{/* End of the group box. */}
      <TextArea // A big text box:
        label="Your note" // labelled "Your note",
        name="body" // sent as body,
        rows={4} // four rows high,
        required // must be filled in,
        maxLength={2000} // up to 2000 letters,
        hint="For example, practice done this week, something that clicked, or how sessions are going. For a worry about safety, contact CLG directly." // with examples and a safety reminder.
      />{/* (end of the element) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of FamilyNoteForm.

// Something to work towards: a school assessment (with grades) or a goal.
export function AddTargetForm({ studentId, today }: { studentId: string; today: string }) { // (takes the student and today's date)
  return ( // Shows:
    <ActionForm action={addRoadmapTarget} submitLabel="Add to roadmap">{/* the form, sending to addRoadmapTarget, with an "Add to roadmap" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <Select label="What is it?" name="kind" defaultValue="assessment">{/* a drop-down for the kind, starting at assessment: */}
        <option value="assessment">A school test, assignment or exam</option>{/* a school assessment, */}
        <option value="goal">Something to learn or get better at</option>{/* or a goal. */}
      </Select>{/* End of the drop-down. */}
      <Field label="Name" name="title" required maxLength={200} hint='For example "Term 4 algebra test" or "Read a chapter book on my own".' />{/* The name, with examples. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* A row of two boxes: */}
        <Field label="Subject (optional)" name="subject" maxLength={100} />{/* the subject (optional), */}
        <Field label="Date (needed for an assessment)" name="due_on" type="date" min={today} />{/* and the date (today or later). */}
      </div>{/* End of the block. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* A row of two boxes: */}
        <Field label="Grade now (optional)" name="current_grade" maxLength={20} hint="As the school writes it, e.g. C or 62%." />{/* the grade now, */}
        <Field label="Grade aiming for (optional)" name="target_grade" maxLength={20} />{/* and the grade aiming for. */}
      </div>{/* End of the block. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* A row of two boxes: */}
        <Field label="Task sheet (optional)" name="task_sheet" type="file" accept={DOCUMENT_ACCEPT} hint="A PDF or photo." />{/* the task sheet file, */}
        <Field label="Rubric or marking guide (optional)" name="rubric" type="file" accept={DOCUMENT_ACCEPT} />{/* and the rubric file. */}
      </div>{/* End of the block. */}
      <label className="flex items-start gap-2 text-sm">{/* A label: */}
        <input type="checkbox" name="plan" defaultChecked className="mt-1" />{/* a tick box to plan study steps (ticked to start), */}
        <span>{/* the words: */}
          Plan study steps for me{/* the main words, */}
          <span className="block text-xs text-zinc-500">{/* a small grey note below: */}
            Adds short practice sessions in the days before the date. You can change them.{/* says what planning does. */}
          </span>{/* End of the text. */}
        </span>{/* End of the text. */}
      </label>{/* End of the label. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AddTargetForm.

// Adds one study step, either loose or under a roadmap target.
export function AddStepForm({ studentId, targetId }: { studentId: string; targetId?: string }) { // (takes the student and, optionally, the target)
  return ( // Shows:
    <ActionForm action={addRoadmapStep} submitLabel="Add step">{/* the form, sending to addRoadmapStep, with an "Add step" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      {targetId && <input type="hidden" name="target_id" value={targetId} />}{/* the target (hidden), if given, */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">{/* a row of boxes: */}
        <div className="sm:col-span-2">{/* taking two of three columns: */}
          <Field label="Step" name="title" required maxLength={300} hint="Small and specific, for example “Do 10 practice questions on area”." />{/* the step, with an example. */}
        </div>{/* End of the block. */}
        <Field label="By (optional)" name="due_on" type="date" />{/* and an optional date. */}
      </div>{/* End of the block. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AddStepForm.

// A term review as saved so far.
export type ReviewDraft = { // (the shape)
  id: string; // its id,
  summary: string | null; // how the term went,
  next_focus: string | null; // the focus for next term,
  recommendation: string | null; // the recommendation,
  recommendation_note: string | null; // and a note on it.
}; // End of the shape.

// The tutor's term review. Written to the family, checked by CLG first.
export function TermReviewForm({ studentId, review }: { studentId: string; review: ReviewDraft }) { // (takes the student and the review so far)
  return ( // Shows:
    <ActionForm action={saveTermReview} submitLabel="Save">{/* the form, sending to saveTermReview, with a "Save" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <input type="hidden" name="review_id" value={review.id} />{/* the review (hidden), */}
      <p className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">{/* an amber warning box: */}
        Please write this review yourself. Don&apos;t copy any student information (names, work, results or notes) into
        ChatGPT, Copilot, Gemini or any other AI tool. Student information must stay in the CLG app.{/* (keeps student information out of AI tools) */}
      </p>{/* End of the paragraph. */}
      <TextArea // A big text box:
        label="How the term went" // labelled "How the term went",
        name="summary" // sent as summary,
        rows={4} // four rows high,
        maxLength={2000} // up to 2000 letters,
        defaultValue={review.summary ?? ""} // filled with what's saved,
        hint="Against the goals above: what they can do now that they couldn't, and what's still building. The family reads this as written." // with a note on what to write.
      />{/* (end of the element) */}
      <TextArea // A big text box:
        label="Focus for next term" // labelled "Focus for next term",
        name="next_focus" // sent as next_focus,
        rows={3} // three rows high,
        maxLength={1000} // up to 1000 letters,
        defaultValue={review.next_focus ?? ""} // filled with what's saved,
        hint="The goals you suggest next, and one thing to keep practising over the holidays." // with a note on what to write.
      />{/* (end of the element) */}
      <Select label="Your recommendation" name="recommendation" defaultValue={review.recommendation ?? ""}>{/* A drop-down for the recommendation, starting at what's saved: */}
        <option value="">Choose…</option>{/* a blank first choice, */}
        {Object.entries(RECOMMENDATION_NAMES).map(([k, label]) => ( // for each recommendation:
          <option key={k} value={k}>{/* a choice: */}
            {label}{/* its name. */}
          </option> // End of the choice.
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <Field // A text box:
        label="Why (optional)" // labelled "Why",
        name="recommendation_note" // sent as recommendation_note,
        maxLength={500} // up to 500 letters,
        defaultValue={review.recommendation_note ?? ""} // filled with what's saved.
      />{/* (end of the element) */}
      <label className="flex items-start gap-2 text-sm">{/* A label: */}
        <input type="checkbox" name="submit" className="mt-1" />{/* a tick box to send it for checking, */}
        <span>Send to CLG to check now (leave unticked to save a draft)</span>{/* its words. */}
      </label>{/* End of the label. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of TermReviewForm.

// The family's reply to a term review, and whether they want a call.
export function TermReviewReplyForm({ studentId, reviewId }: { studentId: string; reviewId: string }) { // (takes the student and the review)
  return ( // Shows:
    <ActionForm action={replyTermReview} submitLabel="Send">{/* the form, sending to replyTermReview, with a "Send" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <input type="hidden" name="review_id" value={reviewId} />{/* the review (hidden), */}
      <TextArea label="Your reply (optional)" name="reply" rows={3} maxLength={2000} />{/* the reply (optional), */}
      <label className="flex items-start gap-2 text-sm">{/* a label: */}
        <input type="checkbox" name="wants_call" className="mt-1" />{/* a tick box to ask for a call, */}
        <span>I&apos;d like a call to talk about next term</span>{/* its words. */}
      </label>{/* End of the label. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of TermReviewReplyForm.

// CLG approves a term review or sends it back to the tutor.
export function CheckTermReviewForm({ reviewId }: { reviewId: string }) { // (takes the review)
  return ( // Shows:
    <ActionForm action={checkTermReview} submitLabel="Save">{/* the form, sending to checkTermReview, with a "Save" button, */}
      <input type="hidden" name="review_id" value={reviewId} />{/* the review (hidden), */}
      <Select label="Decision" name="decision" defaultValue="" required>{/* a required drop-down for the decision: */}
        <option value="" disabled>{/* a blank first choice that can't be picked: */}
          Choose…{/* "Choose…". */}
        </option>{/* End of the choice. */}
        <option value="approve">Approve: the family can see it</option>{/* approve, */}
        <option value="return">Send back to the tutor</option>{/* or send back. */}
      </Select>{/* End of the drop-down. */}
      <Field label="What needs changing (when sending back)" name="reason" maxLength={500} />{/* Why it's going back (when it is). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of CheckTermReviewForm.

// Upload a school report, NAPLAN results, marked work or a work sample. On a
// phone, the file picker offers the camera.
export function EvidenceUploadForm({ // Its settings:
  studentId, // the student,
  today, // today's date,
  isStaff, // whether the person is CLG staff,
  canAddReports, // and whether they may add school reports.
}: { // The settings' types:
  studentId: string; // student id is text,
  today: string; // today is text,
  isStaff: boolean; // staff or not,
  canAddReports: boolean; // may add reports or not.
}) { // End of the settings.
  return ( // Shows:
    <ActionForm action={addEvidence} submitLabel="Upload">{/* the form, sending to addEvidence, with an "Upload" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <Field // a file box:
        label="File or photo" // labelled "File or photo",
        name="file" // sent as file,
        type="file" // a file picker,
        required // must be filled in,
        accept={DOCUMENT_ACCEPT} // allowing PDFs and photos,
        hint="A PDF, or a clear photo of each page. Up to 3.5 MB. Please cover any other children's names." // with size and privacy notes.
      />{/* (end of the element) */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* A row of two boxes: */}
        <Select label="What is it?" name="kind" defaultValue={isStaff ? "work_sample" : "graded_work"}>{/* a drop-down for the kind (staff start at work sample, families at graded work): */}
          {EVIDENCE_KINDS.filter((k) => canAddReports || !PARENT_ONLY_KINDS.includes(k)).map((k) => ( // for each kind this person may add:
            <option key={k} value={k}>{/* a choice: */}
              {EVIDENCE_KIND_NAMES[k]}{/* its name. */}
            </option> // End of the choice.
          ))}{/* End of the loop. */}
        </Select>{/* End of the Select. */}
        <Field label="Name" name="title" required maxLength={200} hint='For example "Term 2 report" or "Fractions test".' />{/* The name, with examples. */}
      </div>{/* End of the block. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">{/* A row of three boxes: */}
        <Field label="Subject (optional)" name="subject" maxLength={100} />{/* subject, */}
        <Field label="Date (optional)" name="dated_on" type="date" max={today} />{/* date (today or earlier), */}
        <Field label="Grade or mark (optional)" name="grade" maxLength={30} hint='As written, e.g. "B+" or "15/20".' />{/* grade or mark. */}
      </div>{/* End of the block. */}
      <TextArea label="Anything to add (optional)" name="note" rows={2} maxLength={1000} />{/* Anything to add (optional). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of EvidenceUploadForm.

// The tutor looks at an upload: a short comment for the family and the
// skills from the student's goals that it shows.
export function EvidenceReviewForm({ // Its settings:
  studentId, // the student,
  evidenceId, // the upload,
  skills, // the goal skills to choose from,
  comment, // the comment so far,
  linked, // and the skills already linked.
}: { // The settings' types:
  studentId: string; // student id is text,
  evidenceId: string; // upload id is text,
  skills: { id: string; label: string }[]; // skills is a list of ids and words,
  comment: string | null; // comment is text or nothing,
  linked: string[]; // linked is a list of skill ids.
}) { // End of the settings.
  return ( // Shows:
    <ActionForm action={reviewEvidence} submitLabel="Save">{/* the form, sending to reviewEvidence, with a "Save" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <input type="hidden" name="evidence_id" value={evidenceId} />{/* the upload (hidden), */}
      <TextArea // a big text box:
        label="Comment for the family (optional)" // labelled for the family,
        name="comment" // sent as comment,
        rows={2} // two rows high,
        maxLength={1000} // up to 1000 letters,
        defaultValue={comment ?? ""} // filled with what's saved,
        hint="What it shows and what you'll work on next." // with a note on what to write.
      />{/* (end of the element) */}
      {skills.length > 0 && ( // If there are goal skills:
        <fieldset className="space-y-1">{/* a group box: */}
          <legend className="mb-1 text-sm font-medium">Skills it shows (from the student&apos;s goals)</legend>{/* its title, */}
          {skills.map((s) => ( // for each skill:
            <label key={s.id} className="flex items-start gap-2 text-sm">{/* a label: */}
              <input type="checkbox" name="skill_id" value={s.id} defaultChecked={linked.includes(s.id)} className="mt-1" />{/* a tick box (ticked if already linked), */}
              <span>{s.label}</span>{/* the skill's words. */}
            </label> // End of the label.
          ))}{/* End of the loop. */}
        </fieldset> // End of the group box.
      )}{/* End of this part. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of EvidenceReviewForm.

// A senior subject the student is planning, studying or has finished.
export function SeniorSubjectForm({ // Its settings:
  studentId, // the student,
  certificate, // the certificate (for example SACE),
  thisYear, // and this year.
}: { // The settings' types:
  studentId: string; // student id is text,
  certificate: string; // certificate is text,
  thisYear: number; // year is a number.
}) { // End of the settings.
  return ( // Shows:
    <ActionForm action={addSeniorSubject} submitLabel="Add subject">{/* the form, sending to addSeniorSubject, with an "Add subject" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <input type="hidden" name="certificate" value={certificate} />{/* the certificate (hidden), */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">{/* a row of boxes: */}
        <div className="sm:col-span-2">{/* taking two of three columns: */}
          <Field label="Subject" name="subject" required maxLength={100} hint='As the school names it, e.g. "General Mathematics".' />{/* the subject name, with an example. */}
        </div>{/* End of the block. */}
        <Field label="Year (optional)" name="school_year" type="number" min={2020} max={2100} defaultValue={thisYear} />{/* The year, starting at this year. */}
      </div>{/* End of the block. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">{/* A row of three drop-downs: */}
        <Select label="Stage" name="stage" defaultValue="1">{/* the stage, starting at Stage 1: */}
          <option value="1">Stage 1 (usually Year 11)</option>{/* Stage 1, */}
          <option value="2">Stage 2 (usually Year 12)</option>{/* Stage 2. */}
        </Select>{/* End of the drop-down. */}
        <Select label="Credits" name="credits" defaultValue="10">{/* the credits, starting at 10: */}
          <option value="10">10 (one semester)</option>{/* 10, */}
          <option value="20">20 (full year)</option>{/* 20. */}
        </Select>{/* End of the drop-down. */}
        <Select label="Counts towards" name="area" defaultValue="">{/* what it counts towards, starting at nothing: */}
          <option value="">Nothing compulsory</option>{/* nothing compulsory, */}
          {Object.entries(SENIOR_AREA_NAMES).map(([k, v]) => ( // for each area:
            <option key={k} value={k}>{/* a choice: */}
              {v}{/* its name. */}
            </option> // End of the choice.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
      </div>{/* End of the block. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">{/* A row of boxes: */}
        <Select label="Status" name="status" defaultValue="studying">{/* the status, starting at studying: */}
          <option value="planned">Planning to take</option>{/* planned, */}
          <option value="studying">Studying now</option>{/* studying, */}
          <option value="finished">Finished</option>{/* finished. */}
        </Select>{/* End of the drop-down. */}
        <Field label="Grade (if finished)" name="grade" maxLength={3} hint="A to E at Stage 1; A+ to E- at Stage 2." />{/* the grade, with the grade scale. */}
      </div>{/* End of the block. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SeniorSubjectForm.

// Updates a senior subject's status and grade.
export function SeniorResultForm({ studentId, id, status, grade }: { studentId: string; id: string; status: string; grade: string | null }) { // (takes the student, subject row, status and grade)
  return ( // Shows:
    <ActionForm action={updateSeniorSubject} submitLabel="Save">{/* the form, sending to updateSeniorSubject, with a "Save" button, */}
      <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
      <input type="hidden" name="id" value={id} />{/* the subject row (hidden), */}
      <div className="grid grid-cols-2 gap-4">{/* a row of two boxes: */}
        <Select label="Status" name="status" defaultValue={status}>{/* the status, starting at what's saved: */}
          <option value="planned">Planning to take</option>{/* planned, */}
          <option value="studying">Studying now</option>{/* studying, */}
          <option value="finished">Finished</option>{/* finished. */}
        </Select>{/* End of the drop-down. */}
        <Field label="Grade" name="grade" maxLength={3} defaultValue={grade ?? ""} />{/* the grade, starting at what's saved. */}
      </div>{/* End of the block. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SeniorResultForm.
