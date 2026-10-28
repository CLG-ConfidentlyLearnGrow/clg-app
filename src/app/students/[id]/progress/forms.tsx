"use client";

import { useRef, type ReactNode } from "react";
import {
  addGoal,
  addRoadmapStep,
  addRoadmapTarget,
  checkTermReview,
  replyTermReview,
  saveTermReview,
  saveFamilyNote,
  saveReflection,
  saveSessionNote,
} from "@/app/actions/progress";
import { ActionForm } from "@/components/action-form";
import { Field, Select, TextArea } from "@/components/ui";
import {
  ATTENDANCE,
  ATTENDANCE_NAMES,
  CONFIDENCE_NAMES,
  RECOMMENDATION_NAMES,
  SKILL_LEVEL_NAMES,
  nextLevels,
  type SkillLevel,
} from "@/lib/progress";

export type SkillOption = { id: string; label: string; levelBand: string; ticked?: boolean };
export type GoalSkill = { id: string; label: string; level: SkillLevel; goal: string };
// A booked session the note is for: its date and length fill in by themselves.
export type NoteSession = { id: string; date: string; minutes: number; label: string };

// Times how long the note takes, from the first tap in the form to the last
// change, so CLG can check notes stay under three minutes. Only admins see
// the result.
function WritingTimer({ children }: { children: ReactNode }) {
  const started = useRef<number | null>(null);
  const out = useRef<HTMLInputElement>(null);
  const tick = () => {
    const now = Date.now();
    // After a note is saved the form clears, so the next one starts afresh.
    if (started.current === null || out.current?.value === "") started.current = now;
    if (out.current) out.current.value = String(Math.round((now - started.current) / 1000));
  };
  return (
    <div className="space-y-4" onFocusCapture={tick} onInputCapture={tick} onChangeCapture={tick}>
      <input type="hidden" name="writing_seconds" ref={out} defaultValue="" />
      {children}
    </div>
  );
}

export function AddGoalForm({
  studentId,
  subject,
  skills,
  startLevel,
}: {
  studentId: string;
  subject: string;
  skills: SkillOption[];
  startLevel?: string | null;
}) {
  return (
    <ActionForm action={addGoal} submitLabel="Add goal">
      <input type="hidden" name="student_id" value={studentId} />
      <input type="hidden" name="subject" value={subject} />
      <Field
        label="Goal"
        name="title"
        required
        maxLength={200}
        hint='Write it so a parent understands, for example "Solve two-step equations without prompts".'
      />
      <Field label="Aim to reach it by (optional)" name="target_date" type="date" />
      <fieldset className="space-y-1">
        <legend className="mb-1 text-sm font-medium">Skills this goal covers</legend>
        <p className="text-xs text-zinc-500">
          {startLevel
            ? `Skills at ${startLevel} (the level given for this subject) start ticked. Untick or add others to suit what the student is ready for.`
            : "Pick by what the student is ready for, not their year level. The year is shown for context only."}{" "}
          Skills may change in the first three sessions as you get to know the student.
        </p>
        <div className="max-h-72 space-y-1 overflow-y-auto rounded-md border border-zinc-200 p-2">
          {skills.map((s) => (
            <label key={s.id} className="flex items-start gap-2 text-sm">
              <input type="checkbox" name="skill_id" value={s.id} defaultChecked={s.ticked} className="mt-1" />
              <span>
                <span className="text-zinc-500">{s.levelBand}:</span> {s.label}
              </span>
            </label>
          ))}
        </div>
      </fieldset>
    </ActionForm>
  );
}

export function SessionNoteForm({
  studentId,
  skills,
  session,
  today,
}: {
  studentId: string;
  skills: GoalSkill[];
  session?: NoteSession | null;
  today: string;
}) {
  return (
    <ActionForm action={saveSessionNote} submitLabel="Save note">
      <WritingTimer>
      <input type="hidden" name="student_id" value={studentId} />
      {session && <input type="hidden" name="session_id" value={session.id} />}
      {session && (
        <p className="rounded-xl bg-zinc-50 px-4 py-3 text-sm">
          For the session on <strong>{session.label}</strong>.
        </p>
      )}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {session ? (
          <input type="hidden" name="session_date" value={session.date} />
        ) : (
          <Field label="Session date" name="session_date" type="date" defaultValue={today} max={today} required />
        )}
        <Field
          label="Minutes"
          name="minutes"
          type="number"
          min={0}
          max={480}
          step={5}
          defaultValue={session?.minutes ?? 60}
          required
        />
        <Select label="Attendance" name="attendance" defaultValue="attended">
          {ATTENDANCE.map((a) => (
            <option key={a} value={a}>
              {ATTENDANCE_NAMES[a]}
            </option>
          ))}
        </Select>
      </div>

      {skills.length > 0 && (
        <fieldset className="space-y-2">
          <legend className="mb-1 text-sm font-medium">Skills worked on</legend>
          <p className="text-xs text-zinc-500">
            Leave a skill blank if you didn&apos;t work on it. Each skill can stay where it is or move one step.
          </p>
          {skills.map((s) => (
            <label key={s.id} className="block space-y-1 text-sm">
              <span>
                {s.label} <span className="text-zinc-500">({s.goal})</span>
              </span>
              <select
                name={`skill_${s.id}`}
                defaultValue=""
                className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"
              >
                <option value="">Not worked on today</option>
                {nextLevels(s.level).map((l) => (
                  <option key={l} value={l}>
                    {SKILL_LEVEL_NAMES[l]}
                    {l === s.level ? " (no change)" : ""}
                  </option>
                ))}
              </select>
            </label>
          ))}
        </fieldset>
      )}

      <TextArea
        label="What went well"
        name="went_well"
        maxLength={1000}
        hint="One or two sentences, written to the student. The family sees this as written."
      />
      <TextArea
        label="Next step"
        name="next_step"
        maxLength={500}
        hint="One specific thing for the student to do next, written to them. This matters most."
      />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <Field label="Homework or practice (optional)" name="homework" maxLength={1000} />
        </div>
        <Field label="Due (optional)" name="homework_due" type="date" />
      </div>
      <Field
        label="One thing to try at home (optional)"
        name="home_tip"
        maxLength={300}
        hint='For the family: a small habit, not re-teaching. For example, "Ask them to explain one fraction at dinner."'
      />
      <TextArea
        label="Note for CLG staff only (optional)"
        name="staff_note"
        maxLength={4000}
        rows={2}
        hint="Never shown to the student or family. For a child safety concern, use the reporting route in the child safe policy, not this box."
      />
      </WritingTimer>
    </ActionForm>
  );
}

export function ReflectionForm({ studentId, noteId }: { studentId: string; noteId: string }) {
  return (
    <ActionForm action={saveReflection} submitLabel="Send to my tutor">
      <input type="hidden" name="student_id" value={studentId} />
      <input type="hidden" name="note_id" value={noteId} />
      <Select label="How confident do you feel about this work?" name="confidence" defaultValue="" required>
        <option value="" disabled>
          Choose…
        </option>
        {[1, 2, 3, 4].map((n) => (
          <option key={n} value={n}>
            {CONFIDENCE_NAMES[n]}
          </option>
        ))}
      </Select>
      <Field label="What was hard? (optional)" name="what_was_hard" maxLength={500} />
      <Field label="What will you try before next time? (optional)" name="what_i_will_try" maxLength={500} />
    </ActionForm>
  );
}

export function FamilyNoteForm({ studentId }: { studentId: string }) {
  return (
    <ActionForm action={saveFamilyNote} submitLabel="Send">
      <input type="hidden" name="student_id" value={studentId} />
      <Select label="What is it?" name="kind" defaultValue="home_progress" required>
        <option value="home_progress">Progress at home</option>
        <option value="feedback">Feedback</option>
      </Select>
      <TextArea
        label="Your note"
        name="body"
        rows={4}
        required
        maxLength={2000}
        hint="For example, practice done this week, something that clicked, or how sessions are going. For a worry about safety, contact CLG directly."
      />
    </ActionForm>
  );
}

// Something to work towards: a school assessment (with grades) or a goal.
export function AddTargetForm({ studentId, today }: { studentId: string; today: string }) {
  return (
    <ActionForm action={addRoadmapTarget} submitLabel="Add to roadmap">
      <input type="hidden" name="student_id" value={studentId} />
      <Select label="What is it?" name="kind" defaultValue="assessment">
        <option value="assessment">A school test, assignment or exam</option>
        <option value="goal">Something to learn or get better at</option>
      </Select>
      <Field label="Name" name="title" required maxLength={200} hint='For example "Term 4 algebra test" or "Read a chapter book on my own".' />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="Subject (optional)" name="subject" maxLength={100} />
        <Field label="Date (needed for an assessment)" name="due_on" type="date" min={today} />
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="Grade now (optional)" name="current_grade" maxLength={20} hint="As the school writes it, e.g. C or 62%." />
        <Field label="Grade aiming for (optional)" name="target_grade" maxLength={20} />
      </div>
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" name="plan" defaultChecked className="mt-1" />
        <span>
          For an assessment, plan the steps for me: short practice spread over the days before, testing yourself
          rather than re-reading. You can change them after.
        </span>
      </label>
    </ActionForm>
  );
}

export function AddStepForm({ studentId, targetId }: { studentId: string; targetId?: string }) {
  return (
    <ActionForm action={addRoadmapStep} submitLabel="Add step">
      <input type="hidden" name="student_id" value={studentId} />
      {targetId && <input type="hidden" name="target_id" value={targetId} />}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <Field label="Step" name="title" required maxLength={300} hint="Small and specific, for example “Do 10 practice questions on area”." />
        </div>
        <Field label="By (optional)" name="due_on" type="date" />
      </div>
    </ActionForm>
  );
}

export type ReviewDraft = {
  id: string;
  summary: string | null;
  next_focus: string | null;
  recommendation: string | null;
  recommendation_note: string | null;
};

// The tutor's term review. Written to the family, checked by CLG first.
export function TermReviewForm({ studentId, review }: { studentId: string; review: ReviewDraft }) {
  return (
    <ActionForm action={saveTermReview} submitLabel="Save">
      <input type="hidden" name="student_id" value={studentId} />
      <input type="hidden" name="review_id" value={review.id} />
      <TextArea
        label="How the term went"
        name="summary"
        rows={4}
        maxLength={2000}
        defaultValue={review.summary ?? ""}
        hint="Against the goals above: what they can do now that they couldn't, and what's still building. The family reads this as written."
      />
      <TextArea
        label="Focus for next term"
        name="next_focus"
        rows={3}
        maxLength={1000}
        defaultValue={review.next_focus ?? ""}
        hint="The goals you suggest next, and one thing to keep practising over the holidays."
      />
      <Select label="Your recommendation" name="recommendation" defaultValue={review.recommendation ?? ""}>
        <option value="">Choose…</option>
        {Object.entries(RECOMMENDATION_NAMES).map(([k, label]) => (
          <option key={k} value={k}>
            {label}
          </option>
        ))}
      </Select>
      <Field
        label="Why (optional)"
        name="recommendation_note"
        maxLength={500}
        defaultValue={review.recommendation_note ?? ""}
      />
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" name="submit" className="mt-1" />
        <span>Send to CLG to check now (leave unticked to save a draft)</span>
      </label>
    </ActionForm>
  );
}

export function TermReviewReplyForm({ studentId, reviewId }: { studentId: string; reviewId: string }) {
  return (
    <ActionForm action={replyTermReview} submitLabel="Send">
      <input type="hidden" name="student_id" value={studentId} />
      <input type="hidden" name="review_id" value={reviewId} />
      <TextArea label="Your reply (optional)" name="reply" rows={3} maxLength={2000} />
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" name="wants_call" className="mt-1" />
        <span>I&apos;d like a call to talk about next term</span>
      </label>
    </ActionForm>
  );
}

export function CheckTermReviewForm({ reviewId }: { reviewId: string }) {
  return (
    <ActionForm action={checkTermReview} submitLabel="Save">
      <input type="hidden" name="review_id" value={reviewId} />
      <Select label="Decision" name="decision" defaultValue="" required>
        <option value="" disabled>
          Choose…
        </option>
        <option value="approve">Approve: the family can see it</option>
        <option value="return">Send back to the tutor</option>
      </Select>
      <Field label="What needs changing (when sending back)" name="reason" maxLength={500} />
    </ActionForm>
  );
}
