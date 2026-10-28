import { requireFamilyAgreement } from "@/lib/consent";
import { redirect } from "next/navigation";
import { Card, Empty, TextLink } from "@/components/ui";
import { RoleTabs } from "@/components/role-tabs";
import { SectionShell } from "@/components/section-shell";
import { requireViewer } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { addDays, localToday } from "@/lib/scheduling";
import { StepRow, type Step } from "@/app/students/[id]/progress/roadmap";
import { NewUpdates, TutorList, loadStudentsAndTutors } from "../shared";

const SECTIONS = [{ id: "learning", label: "Your learning" }] as const;

export default async function StudentDashboard() {
  const viewer = await requireViewer();
  await requireFamilyAgreement(viewer);
  if (!viewer.roles.includes("student")) redirect("/dashboard");
  const supabase = await createClient();
  const [{ assignments: all }, own] = await Promise.all([
    loadStudentsAndTutors(),
    supabase.from("students").select("id").eq("account_id", viewer.id).maybeSingle(),
  ]);
  const onHold = await supabase.rpc("my_support_on_hold");
  // Only this person's own learning, even if they are also a parent or tutor.
  const me = own.data;
  const assignments = all.filter((a) => a.student_id === me?.id);
  // Steps due in the next week (or overdue), from the student's roadmap.
  const today = localToday();
  const stepsRes = me
    ? await supabase
        .from("roadmap_steps")
        .select("id, target_id, title, due_on, source, done_at, created_by")
        .eq("student_id", me.id)
        .is("done_at", null)
        .lte("due_on", addDays(today, 7))
        .order("due_on")
        .limit(10)
    : null;
  const steps = (stepsRes?.data ?? []) as Step[];

  return (
    <>
      <RoleTabs roles={viewer.roles} active="student" />
      <SectionShell basePath="/dashboard/student" label="Student" section="learning" sections={[...SECTIONS]}>
        {onHold.data === true && (
          <Card title="Sessions on hold">
            <p className="text-sm">
              Your sessions are on hold for now. Please check with your parent or carer, or see{" "}
              <TextLink href="/billing">Billing</TextLink>.
            </p>
          </Card>
        )}
        {me && <NewUpdates studentIds={[me.id]} />}
        {me && steps.length > 0 && (
          <Card title="Your steps this week">
            <ul className="space-y-1.5">
              {steps.map((s) => (
                <StepRow key={s.id} step={s} studentId={me.id} today={today} canPlan canRemove={false} />
              ))}
            </ul>
          </Card>
        )}
        <Card title="Your tutors">
          {assignments.length === 0 ? <Empty>No tutor yet.</Empty> : <TutorList assignments={assignments} />}
        </Card>
        {me && (
          <Card title="Your next step and progress">
            <TextLink href={`/students/${me.id}/progress?view=family`}>Open your progress page</TextLink>
          </Card>
        )}
      </SectionShell>
    </>
  );
}
