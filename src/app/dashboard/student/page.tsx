import { redirect } from "next/navigation";
import { Card, Empty, TextLink } from "@/components/ui";
import { RoleTabs } from "@/components/role-tabs";
import { SectionShell } from "@/components/section-shell";
import { requireViewer } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { TutorList, loadStudentsAndTutors } from "../shared";

const SECTIONS = [{ id: "learning", label: "Your learning" }] as const;

export default async function StudentDashboard() {
  const viewer = await requireViewer();
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
