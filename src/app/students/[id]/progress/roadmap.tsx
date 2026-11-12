// Summary: the student's roadmap card: assessments and goals broken into dated steps to tick off.
//
import { closeRoadmapTarget, planRoadmapSteps, removeRoadmapStep, tickRoadmapStep } from "@/app/actions/progress"; // The server actions to finish a target, plan steps, remove a step and tick a step.
import { Card, Empty, SubHeading } from "@/components/ui"; // The card, "nothing yet" note and small heading.
import { dollars } from "@/lib/billing/money"; // Money as dollars.
import { localToday, shortDate } from "@/lib/scheduling"; // Today's date, and dates in short form.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { AddStepForm, AddTargetForm } from "./forms"; // The forms for adding a step and a target.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while sending.

// An assessment or goal on the roadmap.
type Target = {
  id: string; // its id,
  kind: "assessment" | "goal"; // assessment or goal,
  subject: string | null; // the subject (if any),
  title: string; // what it is,
  due_on: string | null; // when it's due (if set),
  current_grade: string | null; // the grade now (if given),
  target_grade: string | null; // and the grade they're aiming for (if given).
}; // End of the shape.
type AddOnStatus = { has_it: boolean; mode: string; name: string; price_cents: number | null; price_period: string }; // The study plans add-on: whether this student has it, its mode, name and price.

// A step on the roadmap.
export type Step = {
  id: string; // its id,
  target_id: string | null; // the target it belongs to (if any),
  title: string; // what to do,
  due_on: string | null; // when it's due (if set),
  source: string; // where it came from,
  done_at: string | null; // when it was ticked off (if it was),
  created_by: string | null; // and who added it.
}; // End of the shape.

const SOURCE_NAMES: Record<string, string> = { // Words for where a step came from:
  next_step: "from the session note", // a session's next step,
  plan: "planned", // planned by the app,
  tutor: "from the tutor", // the tutor,
  parent: "from a parent", // a parent,
  student: "", // the student (no words needed).
}; // End of the list.

// The student's roadmap: what they are working towards (assessments and
// goals) broken into small dated steps to tick off. High school students
// drive their own; for younger students the steps mostly come from the
// tutor's next steps, and a parent can tick them off.
export async function Roadmap({
  studentId, // the student,
  canPlan, // whether this person can plan (tick, add, finish),
  canRemoveAny, // whether they can remove anyone's steps (tutor or admin),
  viewerId, // who is looking,
  isStudentSelf = false, // and whether it's the student's own login (no by default).
}: { // (their types:)
  studentId: string; // an id,
  canPlan: boolean; // true or false,
  canRemoveAny: boolean; // true or false,
  viewerId: string; // an id,
  isStudentSelf?: boolean; // true or false (optional).
}) { // (end of the settings)
  const supabase = await createClient(); // Connects to the database.
  const [targetsRes, stepsRes, filesRes, addOnRes] = await Promise.all([ // Reads four things at once:
    supabase // the open targets:
      .from("roadmap_targets") // (from the roadmap targets table)
      .select("id, kind, subject, title, due_on, current_grade, target_grade") // with their details,
      .eq("student_id", studentId) // for this student,
      .eq("status", "open") // still open,
      .order("due_on", { ascending: true, nullsFirst: false }), // soonest first (no date last);
    supabase // the steps:
      .from("roadmap_steps") // (from the roadmap steps table)
      .select("id, target_id, title, due_on, source, done_at, created_by") // with their details,
      .eq("student_id", studentId) // for this student,
      .order("due_on", { ascending: true, nullsFirst: false }) // soonest first (no date last),
      .order("created_at") // then oldest first,
      .limit(300), // at most 300;
    // Task sheets and rubrics attached to assessments.
    supabase // the files on assessments:
      .from("learning_evidence") // (from the uploads table)
      .select("id, target_id, kind") // their id, target and kind,
      .eq("student_id", studentId) // for this student,
      .not("target_id", "is", null) // only those linked to a target,
      .order("uploaded_at"), // oldest first;
    // Study plans are an add-on: free for now, paid later (docs/features/add-ons.md).
    supabase.rpc("add_on_for_student", { p_code: "study_plans", p_student: studentId }), // and whether the student has the study plans add-on.
  ]); // End of the reads.
  const addOn = ((addOnRes.data ?? []) as AddOnStatus[])[0]; // The add-on status.
  // If the add-on can't be read, the database still decides what is allowed.
  const hasStudyPlans = addOn ? addOn.has_it : true; // True if they have it (or it couldn't be read).
  // Assessments, goals and planned study steps need the add-on.
  const canStudyPlan = canPlan && hasStudyPlans; // True if this person can plan and the student has study plans.
  // Only the tutor (or an admin) adds steps; families and students tick them off.
  const canAddSteps = canRemoveAny; // True if this person can add steps.
  const files = (filesRes.data ?? []) as { id: string; target_id: string; kind: string }[]; // The files.
  const targets = (targetsRes.data ?? []) as Target[]; // The targets.
  const steps = (stepsRes.data ?? []) as Step[]; // The steps.
  const today = localToday(); // Today's date.
  // Loose steps: shown while open, or for a week after they're done.
  const weekAgo = new Date(Date.parse(`${today}T00:00:00Z`) - 7 * 86400000).toISOString(); // The time a week ago.
  const looseSteps = steps.filter((s) => !s.target_id && (!s.done_at || s.done_at >= weekAgo)); // Steps not linked to a target: open, or done in the last week.
  const stepsFor = (id: string) => steps.filter((s) => s.target_id === id); // The steps for one target.

  const stepList = (list: Step[]) => ( // Shows a list of steps:
    <ul className="space-y-1.5">{/* a list: */}
      {list.map((s) => ( // for each step:
        <StepRow // a step row:
          key={s.id} // (its key)
          step={s} // the step,
          studentId={studentId} // the student,
          today={today} // today,
          canPlan={canPlan} // whether this person can tick it,
          canRemove={canRemoveAny || s.created_by === viewerId} // and whether they can remove it (their own, or any for staff).
        /> // (end of the row)
      ))}{/* End of the loop. */}
    </ul> // End of the list.
  ); // End of stepList.

  return ( // Shows:
    <Card // a card:
      title="Roadmap" // titled "Roadmap",
      description="What's coming up, broken into small steps to tick off. Each session's next step is added here too." // with a short explanation.
    >{/* (end of the card's settings) */}
      {isStudentSelf && ( // For the student's own login:
        <p className="mb-4 text-xs text-zinc-500">Your parent or carer and your tutor can see your roadmap.</p> // a note on who can see it.
      )}{/* End of that part. */}
      {targets.length === 0 && looseSteps.length === 0 && ( // If the roadmap is empty:
        <Empty>{/* a note: */}
          {canStudyPlan // if they can plan:
            ? "Nothing on the roadmap yet. Add a school assessment or a goal below." // suggests adding an assessment or goal,
            : "Nothing on the roadmap yet. Each session's next step will appear here."}{/* otherwise says steps will appear here. */}
        </Empty> // End of the note.
      )}{/* End of that part. */}

      {looseSteps.length > 0 && ( // If there are loose steps:
        <>{/* (a group:) */}
          <SubHeading>This week&apos;s steps</SubHeading>{/* a small heading, */}
          {stepList(looseSteps)}{/* and the steps. */}
        </> // (end of the group)
      )}{/* End of that part. */}

      {targets.map((t) => { // For each target:
        const list = stepsFor(t.id); // its steps,
        const done = list.filter((s) => s.done_at).length; // and how many are done.
        return ( // Shows:
          <div key={t.id} className="mt-6 first:mt-0">{/* a block: */}
            <div className="flex flex-wrap items-start justify-between gap-2">{/* a row: */}
              <div>{/* a group: */}
                <p className="font-medium">{t.title}</p>{/* the target's title, */}
                <p className="text-xs text-zinc-500">{/* a small grey line: */}
                  {[ // made of:
                    t.subject, // the subject,
                    t.due_on && `${t.kind === "assessment" ? "on" : "by"} ${shortDate(t.due_on)}`, // when it's due,
                    (t.current_grade || t.target_grade) && // if there are grades:
                      `grade ${t.current_grade ?? "?"} → aiming for ${t.target_grade ?? "?"}`, // the grade now and the aim,
                    list.length > 0 && `${done} of ${list.length} steps done`, // and how many steps are done,
                  ] // (end of the parts)
                    .filter(Boolean) // leaving out blanks,
                    .join(" · ")}{/* joined with dots. */}
                </p>{/* End of the line. */}
              </div>{/* End of the group. */}
              {canPlan && ( // If this person can plan:
                <form action={closeRoadmapTarget} className="flex gap-3">{/* a form for finishing or removing it: */}
                  <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
                  <input type="hidden" name="id" value={t.id} />{/* the target (hidden), */}
                  <BusyButton name="status" value="done" className="text-xs text-teal-800 underline">{/* a "Finished" button: */}
                    Finished{/* (its words) */}
                  </BusyButton>{/* (end of the button) */}
                  <BusyButton name="status" value="dropped" className="text-xs text-zinc-500 underline">{/* a "Remove" button: */}
                    Remove{/* (its words) */}
                  </BusyButton>{/* (end of the button) */}
                </form> // End of the form.
              )}{/* End of that part. */}
            </div>{/* End of the row. */}
            {files.some((f) => f.target_id === t.id) && ( // If it has files:
              <p className="mt-1 flex flex-wrap gap-3 text-sm">{/* a line of links: */}
                {files // the files:
                  .filter((f) => f.target_id === t.id) // for this target,
                  .map((f) => ( // for each:
                    <a // a link:
                      key={f.id} // (its key)
                      href={`/evidence/${f.id}/file`} // that opens the file,
                      target="_blank" // in a new tab,
                      rel="noopener" // safely,
                      className="text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700" // styled as a link.
                    >{/* (end of its settings) */}
                      {f.kind === "rubric" ? "Rubric" : "Task sheet"}{/* "Rubric" or "Task sheet". */}
                    </a> // End of the link.
                  ))}{/* End of the loop. */}
              </p> // End of the line.
            )}{/* End of the files. */}
            <div className="mt-2">{list.length > 0 ? stepList(list) : null}</div>{/* The steps, if any. */}
            {canStudyPlan && t.kind === "assessment" && list.length === 0 && t.due_on && t.due_on > today && ( // An assessment with no steps and a future date, if they have study plans:
              <form action={planRoadmapSteps} className="mt-2">{/* a form that plans steps: */}
                <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
                <input type="hidden" name="id" value={t.id} />{/* the target (hidden), */}
                <BusyButton className="text-sm text-teal-800 underline">Plan study steps for me</BusyButton>{/* and the button. */}
              </form> // End of the form.
            )}{/* End of that part. */}
            {canAddSteps && ( // If this person can add steps:
              <details className="mt-2">{/* a section that opens when clicked: */}
                <summary className="cursor-pointer text-sm text-teal-800 underline">Add a step</summary>{/* its heading "Add a step", */}
                <div className="mt-3">{/* a block: */}
                  <AddStepForm studentId={studentId} targetId={t.id} />{/* the step form for this target. */}
                </div>{/* End of the block. */}
              </details> // End of the section.
            )}{/* End of that part. */}
          </div> // End of the block.
        ); // End of what's shown for this target.
      })}{/* End of the targets loop. */}

      {canAddSteps && ( // If this person can add steps:
        <>{/* (a group:) */}
          <SubHeading>Add a step for this week</SubHeading>{/* a small heading, */}
          <AddStepForm studentId={studentId} />{/* and the step form for this week. */}
        </> // (end of the group)
      )}{/* End of that part. */}
      {canStudyPlan && ( // If they can plan with study plans:
        <details className="mt-6">{/* a section that opens when clicked: */}
          <summary className="cursor-pointer text-sm font-medium text-teal-800 underline">{/* its heading: */}
            Add a school assessment or a goal{/* "Add a school assessment or a goal". */}
          </summary>{/* End of the heading. */}
          <div className="mt-3">{/* A block: */}
            <AddTargetForm studentId={studentId} today={today} />{/* the target form. */}
          </div>{/* End of the block. */}
        </details> // End of the section.
      )}{/* End of that part. */}
      {canPlan && !hasStudyPlans && addOn?.mode === "paid" && ( // If study plans are paid and the student doesn't have them:
        <p className="mt-6 rounded-xl bg-zinc-50 px-4 py-3 text-sm text-zinc-700">{/* a grey note: */}
          Study plans (adding assessments and goals, and planned study steps) are an add-on{/* what study plans are, */}
          {addOn.price_cents ? `, ${dollars(addOn.price_cents)} a ${addOn.price_period}` : ""}. Ask CLG if you&apos;d
          like them.{/* and to ask CLG. */}
        </p> // End of the note.
      )}{/* End of that part. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of Roadmap.

// One step: a tick box (or tick mark), its words, and a remove button.
export function StepRow({
  step, // the step,
  studentId, // the student,
  today, // today's date,
  canPlan, // whether this person can tick it,
  canRemove, // and whether they can remove it.
}: { // (their types:)
  step: Step; // a step,
  studentId: string; // an id,
  today: string; // a date,
  canPlan: boolean; // true or false,
  canRemove: boolean; // true or false.
}) { // (end of the settings)
  const late = !step.done_at && step.due_on && step.due_on < today; // True if it's not done and its date has passed.
  return ( // Shows:
    <li className="flex items-start gap-2 text-sm">{/* a list item in one row: */}
      {canPlan ? ( // if this person can tick it:
        <form action={tickRoadmapStep}>{/* a form that ticks or unticks it: */}
          <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
          <input type="hidden" name="id" value={step.id} />{/* the step (hidden), */}
          <input type="hidden" name="done" value={step.done_at ? "false" : "true"} />{/* done or not done (hidden), */}
          <BusyButton spinnerOnly // a small square button that shows only a spinner while busy:
            className={`mt-0.5 flex h-5 w-5 items-center justify-center rounded border text-xs ${
              step.done_at ? "border-teal-700 bg-teal-700 text-white" : "border-zinc-400 bg-white"
            }`} // styled filled when done, empty when not,
            aria-label={step.done_at ? `Mark "${step.title}" as not done` : `Tick off "${step.title}"`} // with words for screen readers.
          >{/* (end of its settings) */}
            {step.done_at ? "✓" : ""}{/* A tick when done. */}
          </BusyButton>{/* End of the button. */}
        </form> // End of the form.
      ) : ( // Otherwise:
        <span className="mt-0.5 w-5 text-center">{step.done_at ? "✓" : "○"}</span> // a tick or a circle.
      )}{/* End of the choice. */}
      <span className={`flex-1 ${step.done_at ? "text-zinc-500 line-through" : ""}`}>{/* The words, crossed out when done: */}
        {step.title}{/* the step, */}
        <span className={`ml-2 text-xs ${late ? "text-red-700" : "text-zinc-500"}`}>{/* small details, red if late: */}
          {[step.due_on && `by ${shortDate(step.due_on)}`, SOURCE_NAMES[step.source]].filter(Boolean).join(", ")}{/* when it's due, and where it came from. */}
        </span>{/* End of the details. */}
      </span>{/* End of the words. */}
      {canRemove && !step.done_at && ( // If this person can remove it and it's not done:
        <form action={removeRoadmapStep}>{/* a form that removes it: */}
          <input type="hidden" name="student_id" value={studentId} />{/* the student (hidden), */}
          <input type="hidden" name="id" value={step.id} />{/* the step (hidden), */}
          <BusyButton className="text-xs text-zinc-500 underline">Remove</BusyButton>{/* and the "Remove" button. */}
        </form> // End of the form.
      )}{/* End of that part. */}
    </li> // End of the list item.
  ); // End of what's shown.
} // End of StepRow.
