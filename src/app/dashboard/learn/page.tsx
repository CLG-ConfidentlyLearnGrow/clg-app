import { redirect } from "next/navigation";
import { Card, Page } from "@/components/ui";
import { needsTwoStep, requireViewer } from "@/lib/auth";
import { LearnerForm } from "./learner-form";

// "Become a learner too": add a student profile to this account.
export default async function LearnPage() {
  const viewer = await requireViewer();
  if (needsTwoStep(viewer)) redirect("/mfa");
  if (viewer.roles.includes("student")) redirect("/dashboard/student");
  return (
    <Page
      title="Learn with CLG too"
      intro="Add a student profile to your account. You keep the same login and get a Student tab next to your other dashboards. You need to be 16 or over."
    >
      <Card>
        <LearnerForm />
      </Card>
    </Page>
  );
}
