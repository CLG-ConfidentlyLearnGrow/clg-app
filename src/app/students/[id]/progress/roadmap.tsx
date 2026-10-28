import { closeRoadmapTarget, planRoadmapSteps, removeRoadmapStep, tickRoadmapStep } from "@/app/actions/progress";
import { Card, Empty, SubHeading } from "@/components/ui";
import { localToday, shortDate } from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";
import { AddStepForm, AddTargetForm } from "./forms";

type Target = {
  id: string;
  kind: "assessment" | "goal";
  subject: string | null;
  title: string;
  due_on: string | null;
  current_grade: string | null;
  target_grade: string | null;
};
export type Step = {
  id: string;
  target_id: string | null;
  title: string;
  due_on: string | null;
  source: string;
  done_at: string | null;
  created_by: string | null;
};

const SOURCE_NAMES: Record<string, string> = {
  next_step: "from the session note",
  plan: "planned",
  tutor: "from the tutor",
  parent: "from a parent",
  student: "",
};

// The student's roadmap: what they are working towards (assessments and
// goals) broken into small dated steps to tick off. High school students
// drive their own; for younger students the steps mostly come from the
// tutor's next steps, and a parent can tick them off.
export async function Roadmap({
  studentId,
  canPlan,
  canRemoveAny,
  viewerId,
  isStudentSelf = false,
}: {
  studentId: string;
  canPlan: boolean;
  canRemoveAny: boolean;
  viewerId: string;
  isStudentSelf?: boolean;
}) {
  const supabase = await createClient();
  const [targetsRes, stepsRes] = await Promise.all([
    supabase
      .from("roadmap_targets")
      .select("id, kind, subject, title, due_on, current_grade, target_grade")
      .eq("student_id", studentId)
      .eq("status", "open")
      .order("due_on", { ascending: true, nullsFirst: false }),
    supabase
      .from("roadmap_steps")
      .select("id, target_id, title, due_on, source, done_at, created_by")
      .eq("student_id", studentId)
      .order("due_on", { ascending: true, nullsFirst: false })
      .order("created_at")
      .limit(300),
  ]);
  const targets = (targetsRes.data ?? []) as Target[];
  const steps = (stepsRes.data ?? []) as Step[];
  const today = localToday();
  // Loose steps: shown while open, or for a week after they're done.
  const weekAgo = new Date(Date.parse(`${today}T00:00:00Z`) - 7 * 86400000).toISOString();
  const looseSteps = steps.filter((s) => !s.target_id && (!s.done_at || s.done_at >= weekAgo));
  const stepsFor = (id: string) => steps.filter((s) => s.target_id === id);

  const stepList = (list: Step[]) => (
    <ul className="space-y-1.5">
      {list.map((s) => (
        <StepRow
          key={s.id}
          step={s}
          studentId={studentId}
          today={today}
          canPlan={canPlan}
          canRemove={canRemoveAny || s.created_by === viewerId}
        />
      ))}
    </ul>
  );

  return (
    <Card
      title="Roadmap"
      description="What's coming up, broken into small steps to tick off. Each session's next step is added here too."
    >
      {isStudentSelf && (
        <p className="mb-4 text-xs text-zinc-500">Your parent or carer and your tutor can see your roadmap.</p>
      )}
      {targets.length === 0 && looseSteps.length === 0 && (
        <Empty>Nothing on the roadmap yet. Add a school assessment or a goal below.</Empty>
      )}

      {looseSteps.length > 0 && (
        <>
          <SubHeading>This week&apos;s steps</SubHeading>
          {stepList(looseSteps)}
        </>
      )}

      {targets.map((t) => {
        const list = stepsFor(t.id);
        const done = list.filter((s) => s.done_at).length;
        return (
          <div key={t.id} className="mt-6 first:mt-0">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <p className="font-medium">{t.title}</p>
                <p className="text-xs text-zinc-500">
                  {[
                    t.subject,
                    t.due_on && `${t.kind === "assessment" ? "on" : "by"} ${shortDate(t.due_on)}`,
                    (t.current_grade || t.target_grade) &&
                      `grade ${t.current_grade ?? "?"} → aiming for ${t.target_grade ?? "?"}`,
                    list.length > 0 && `${done} of ${list.length} steps done`,
                  ]
                    .filter(Boolean)
                    .join(" · ")}
                </p>
              </div>
              {canPlan && (
                <form action={closeRoadmapTarget} className="flex gap-3">
                  <input type="hidden" name="student_id" value={studentId} />
                  <input type="hidden" name="id" value={t.id} />
                  <button name="status" value="done" className="text-xs text-teal-800 underline">
                    Finished
                  </button>
                  <button name="status" value="dropped" className="text-xs text-zinc-500 underline">
                    Remove
                  </button>
                </form>
              )}
            </div>
            <div className="mt-2">{list.length > 0 ? stepList(list) : null}</div>
            {canPlan && t.kind === "assessment" && list.length === 0 && t.due_on && t.due_on > today && (
              <form action={planRoadmapSteps} className="mt-2">
                <input type="hidden" name="student_id" value={studentId} />
                <input type="hidden" name="id" value={t.id} />
                <button className="text-sm text-teal-800 underline">Plan the steps for me</button>
              </form>
            )}
            {canPlan && (
              <details className="mt-2">
                <summary className="cursor-pointer text-sm text-teal-800 underline">Add a step</summary>
                <div className="mt-3">
                  <AddStepForm studentId={studentId} targetId={t.id} />
                </div>
              </details>
            )}
          </div>
        );
      })}

      {canPlan && (
        <>
          <SubHeading>Add a step for this week</SubHeading>
          <AddStepForm studentId={studentId} />
          <details className="mt-6">
            <summary className="cursor-pointer text-sm font-medium text-teal-800 underline">
              Add a school assessment or a goal
            </summary>
            <div className="mt-3">
              <AddTargetForm studentId={studentId} today={today} />
            </div>
          </details>
        </>
      )}
    </Card>
  );
}

export function StepRow({
  step,
  studentId,
  today,
  canPlan,
  canRemove,
}: {
  step: Step;
  studentId: string;
  today: string;
  canPlan: boolean;
  canRemove: boolean;
}) {
  const late = !step.done_at && step.due_on && step.due_on < today;
  return (
    <li className="flex items-start gap-2 text-sm">
      {canPlan ? (
        <form action={tickRoadmapStep}>
          <input type="hidden" name="student_id" value={studentId} />
          <input type="hidden" name="id" value={step.id} />
          <input type="hidden" name="done" value={step.done_at ? "false" : "true"} />
          <button
            className={`mt-0.5 flex h-5 w-5 items-center justify-center rounded border text-xs ${
              step.done_at ? "border-teal-700 bg-teal-700 text-white" : "border-zinc-400 bg-white"
            }`}
            aria-label={step.done_at ? `Mark "${step.title}" as not done` : `Tick off "${step.title}"`}
          >
            {step.done_at ? "✓" : ""}
          </button>
        </form>
      ) : (
        <span className="mt-0.5 w-5 text-center">{step.done_at ? "✓" : "○"}</span>
      )}
      <span className={`flex-1 ${step.done_at ? "text-zinc-500 line-through" : ""}`}>
        {step.title}
        <span className={`ml-2 text-xs ${late ? "text-red-700" : "text-zinc-500"}`}>
          {[step.due_on && `by ${shortDate(step.due_on)}`, SOURCE_NAMES[step.source]].filter(Boolean).join(", ")}
        </span>
      </span>
      {canRemove && !step.done_at && (
        <form action={removeRoadmapStep}>
          <input type="hidden" name="student_id" value={studentId} />
          <input type="hidden" name="id" value={step.id} />
          <button className="text-xs text-zinc-500 underline">Remove</button>
        </form>
      )}
    </li>
  );
}
