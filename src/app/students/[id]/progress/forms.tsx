"use client";

import { useRef, type ReactNode } from "react";
import {
  addEvidence,
  addSeniorSubject,
  addGoal,
  addRoadmapStep,
  addRoadmapTarget,
  checkTermReview,
  replyTermReview,
  reviewEvidence,
  saveTermReview,
  saveFamilyNote,
  saveReflection,
  saveSessionNote,
  updateSeniorSubject,
} from "@/app/actions/progress";
import { ActionForm } from "@/components/action-form";
import { Field, Select, TextArea } from "@/components/ui";
import { DOCUMENT_ACCEPT } from "@/lib/documents";
import {
  ATTENDANCE,
  ATTENDANCE_NAMES,
  CONFIDENCE_NAMES,
  EVIDENCE_KINDS,
  EVIDENCE_KIND_NAMES,
  SENIOR_AREA_NAMES,
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

// A material that fits the student; skillIds are its skills that are in
// the student's goals.
export type NoteMaterial = { id: string; title: string; kind: string; skillIds: string[] };

// Ticking a booklet marks its skills as worked on today (at their current
// level), so the tutor only changes the ones that moved.
function MaterialsUsed({ materials, levels }: { materials: NoteMaterial[]; levels: Map<string, SkillLevel> }) {
  const box = useRef<HTMLFieldSetElement>(null);
  const sorted = [...materials].sort(
    (a, b) => Number(b.kind === "booklet") - Number(a.kind === "booklet") || b.skillIds.length - a.skillIds.length,
  );
  function picked(m: NoteMaterial, on: boolean) {
    if (!on) return;
    const form = box.current?.form;
    for (const id of m.skillIds) {
      const select = form?.elements.namedItem(`skill_${id}`);
      if (select instanceof HTMLSelectElement && select.value === "") {
        select.value = levels.get(id) ?? "not_started";
      }
    }
  }
  return (
    <fieldset ref={box} className="space-y-1">
      <legend className="mb-1 text-sm font-medium">Booklet or materials used (optional)</legend>
      <p className="text-xs text-zinc-500">Tick what you worked through. Its skills below fill in by themselves.</p>
      <div className="max-h-48 space-y-1 overflow-y-auto rounded-md border border-zinc-200 p-2">
        {sorted.map((m) => (
          <label key={m.id} className="flex items-start gap-2 text-sm">
            <input
              type="checkbox"
              name="material_id"
              value={m.id}
              className="mt-1"
              onChange={(e) => picked(m, e.target.checked)}
            />
            <span>
              {m.title}
              {m.skillIds.length > 0 && (
                <span className="text-zinc-500">
                  {" "}
                  ({m.skillIds.length} goal skill{m.skillIds.length === 1 ? "" : "s"})
                </span>
              )}
            </span>
          </label>
        ))}
      </div>
    </fieldset>
  );
}

export function SessionNoteForm({
  studentId,
  skills,
  materials = [],
  session,
  today,
}: {
  studentId: string;
  skills: GoalSkill[];
  materials?: NoteMaterial[];
  session?: NoteSession | null;
  today: string;
}) {
  const levels = new Map(skills.map((s) => [s.id, s.level]));
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

      {materials.length > 0 && <MaterialsUsed materials={materials} levels={levels} />}

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

// Upload a school report, NAPLAN results, marked work or a work sample. On a
// phone, the file picker offers the camera.
export function EvidenceUploadForm({ studentId, today, isStaff }: { studentId: string; today: string; isStaff: boolean }) {
  return (
    <ActionForm action={addEvidence} submitLabel="Upload">
      <input type="hidden" name="student_id" value={studentId} />
      <Field
        label="File or photo"
        name="file"
        type="file"
        required
        accept={DOCUMENT_ACCEPT}
        hint="A PDF, or a clear photo of each page. Up to 3.5 MB. Please cover any other children's names."
      />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Select label="What is it?" name="kind" defaultValue={isStaff ? "work_sample" : "graded_work"}>
          {EVIDENCE_KINDS.map((k) => (
            <option key={k} value={k}>
              {EVIDENCE_KIND_NAMES[k]}
            </option>
          ))}
        </Select>
        <Field label="Name" name="title" required maxLength={200} hint='For example "Term 2 report" or "Fractions test".' />
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Field label="Subject (optional)" name="subject" maxLength={100} />
        <Field label="Date (optional)" name="dated_on" type="date" max={today} />
        <Field label="Grade or mark (optional)" name="grade" maxLength={30} hint='As written, e.g. "B+" or "15/20".' />
      </div>
      <TextArea label="Anything to add (optional)" name="note" rows={2} maxLength={1000} />
    </ActionForm>
  );
}

// The tutor looks at an upload: a short comment for the family and the
// skills from the student's goals that it shows.
export function EvidenceReviewForm({
  studentId,
  evidenceId,
  skills,
  comment,
  linked,
}: {
  studentId: string;
  evidenceId: string;
  skills: { id: string; label: string }[];
  comment: string | null;
  linked: string[];
}) {
  return (
    <ActionForm action={reviewEvidence} submitLabel="Save">
      <input type="hidden" name="student_id" value={studentId} />
      <input type="hidden" name="evidence_id" value={evidenceId} />
      <TextArea
        label="Comment for the family (optional)"
        name="comment"
        rows={2}
        maxLength={1000}
        defaultValue={comment ?? ""}
        hint="What it shows and what you'll work on next."
      />
      {skills.length > 0 && (
        <fieldset className="space-y-1">
          <legend className="mb-1 text-sm font-medium">Skills it shows (from the student&apos;s goals)</legend>
          {skills.map((s) => (
            <label key={s.id} className="flex items-start gap-2 text-sm">
              <input type="checkbox" name="skill_id" value={s.id} defaultChecked={linked.includes(s.id)} className="mt-1" />
              <span>{s.label}</span>
            </label>
          ))}
        </fieldset>
      )}
    </ActionForm>
  );
}

// A senior subject the student is planning, studying or has finished.
export function SeniorSubjectForm({
  studentId,
  certificate,
  thisYear,
}: {
  studentId: string;
  certificate: string;
  thisYear: number;
}) {
  return (
    <ActionForm action={addSeniorSubject} submitLabel="Add subject">
      <input type="hidden" name="student_id" value={studentId} />
      <input type="hidden" name="certificate" value={certificate} />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <Field label="Subject" name="subject" required maxLength={100} hint='As the school names it, e.g. "General Mathematics".' />
        </div>
        <Field label="Year (optional)" name="school_year" type="number" min={2020} max={2100} defaultValue={thisYear} />
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Select label="Stage" name="stage" defaultValue="1">
          <option value="1">Stage 1 (usually Year 11)</option>
          <option value="2">Stage 2 (usually Year 12)</option>
        </Select>
        <Select label="Credits" name="credits" defaultValue="10">
          <option value="10">10 (one semester)</option>
          <option value="20">20 (full year)</option>
        </Select>
        <Select label="Counts towards" name="area" defaultValue="">
          <option value="">Nothing compulsory</option>
          {Object.entries(SENIOR_AREA_NAMES).map(([k, v]) => (
            <option key={k} value={k}>
              {v}
            </option>
          ))}
        </Select>
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Select label="Status" name="status" defaultValue="studying">
          <option value="planned">Planning to take</option>
          <option value="studying">Studying now</option>
          <option value="finished">Finished</option>
        </Select>
        <Field label="Grade (if finished)" name="grade" maxLength={3} hint="A to E at Stage 1; A+ to E- at Stage 2." />
      </div>
    </ActionForm>
  );
}

export function SeniorResultForm({ studentId, id, status, grade }: { studentId: string; id: string; status: string; grade: string | null }) {
  return (
    <ActionForm action={updateSeniorSubject} submitLabel="Save">
      <input type="hidden" name="student_id" value={studentId} />
      <input type="hidden" name="id" value={id} />
      <div className="grid grid-cols-2 gap-4">
        <Select label="Status" name="status" defaultValue={status}>
          <option value="planned">Planning to take</option>
          <option value="studying">Studying now</option>
          <option value="finished">Finished</option>
        </Select>
        <Field label="Grade" name="grade" maxLength={3} defaultValue={grade ?? ""} />
      </div>
    </ActionForm>
  );
}
