// Summary: the starting page that sends each person to their own dashboard.
//
import { requireFamilyAgreement } from "@/lib/consent"; // Makes sure a family has agreed to the terms.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Checks two-step login, and makes sure someone is signed in.
import { ROLE_ORDER, ROLE_TABS } from "@/lib/roles"; // The order of roles, and each role's dashboard address.
import { Card, Page } from "@/components/ui"; // The card and page frame.

// Sends each person to their first dashboard. Tabs at the top move between
// dashboards for people with more than one role.
export default async function DashboardPage() {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login not set up: sends them to set it up.
  await requireFamilyAgreement(viewer); // A family that hasn't agreed to the terms is sent to agree first.
  const first = ROLE_ORDER.find((r) => viewer.roles.includes(r)); // Their first role, in the usual order.
  if (first) redirect(ROLE_TABS[first].href); // Sends them to that role's dashboard.

  return ( // No role yet: shows:
    <Page title="Welcome">{/* a page titled "Welcome", */}
      <Card>{/* with a card: */}
        <p className="text-sm">Your account is set up, but has no role yet. Please contact CLG.</p>{/* saying to contact CLG. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of DashboardPage.
