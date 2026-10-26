import { redirect } from "next/navigation";
import { needsTwoStep, requireViewer } from "@/lib/auth";
import { ROLE_ORDER, ROLE_TABS } from "@/lib/roles";
import { Card, Page } from "@/components/ui";

// Sends each person to their first dashboard. Tabs at the top move between
// dashboards for people with more than one role.
export default async function DashboardPage() {
  const viewer = await requireViewer();
  if (needsTwoStep(viewer)) redirect("/mfa");
  const first = ROLE_ORDER.find((r) => viewer.roles.includes(r));
  if (first) redirect(ROLE_TABS[first].href);

  return (
    <Page title="Welcome">
      <Card>
        <p className="text-sm">Your account is set up, but has no role yet. Please contact CLG.</p>
      </Card>
    </Page>
  );
}
