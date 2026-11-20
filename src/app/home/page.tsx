// Summary: the Overview page that every dashboard opens on (Carla, 20 Nov
// 2026: "When going home to the home dashboard of each profile, can it
// please be an overview dashboard, so it is a quick look at all the
// important things for that particular person's role"). Home in the top
// bar, the logo and each dashboard tab all come here.
//
// "?as=admin", "?as=tutor", "?as=parent" or "?as=student" picks the
// dashboard. Someone with several roles gets one Overview per dashboard,
// each showing only that role's own things. Without "as" (or with a role
// the person does not have), their first dashboard is shown.
// See docs/features/home-overview.md.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { needsTwoStep, requireViewer, type Role } from "@/lib/auth"; // Whether two-step sign-in is still needed, the signed-in person, and the role type.
import { requireFamilyAgreement } from "@/lib/consent"; // Sends a family to agree to the terms first if they have not.
import { requireStaffName } from "@/lib/staff-name"; // Asks tutors and admins for their first and last name if it is missing.
import { ROLE_ORDER } from "@/lib/roles"; // The usual order of the dashboards.
import { AdminOverview } from "./admin-overview"; // The admin Overview.
import { TutorOverview } from "./tutor-overview"; // The tutor Overview.
import { ParentOverview, StudentOverview } from "./family-overview"; // The parent and student Overviews.

// Shows the Overview for one of the person's dashboards.
export default async function HomePage({ searchParams }: PageProps<"/home">) { // The page itself (reads the address's settings).
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Tutors and admins without two-step sign-in this time set it up first.
  await requireFamilyAgreement(viewer); // A family that has not agreed to the terms is sent to agree first.
  const params = await searchParams; // The address's settings.
  const asked = (typeof params.as === "string" ? params.as : "") as Role; // The dashboard asked for, if any.
  const role = viewer.roles.includes(asked) ? asked : ROLE_ORDER.find((r) => viewer.roles.includes(r)); // That dashboard if they have it, otherwise their first.
  if (!role) redirect("/dashboard"); // No role at all: the welcome page explains what to do.
  if (role === "admin" || role === "tutor") await requireStaffName(viewer, `/home?as=${role}`); // Staff without a first and last name are asked for it first, then come back here.

  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="overview">{/* the dashboard tabs and side menu, with Overview open, */}
      {role === "admin" && <AdminOverview roles={viewer.roles} />}{/* the admin Overview, */}
      {role === "tutor" && <TutorOverview viewerId={viewer.id} roles={viewer.roles} />}{/* or the tutor Overview, */}
      {role === "parent" && <ParentOverview viewerId={viewer.id} roles={viewer.roles} />}{/* or the parent Overview, */}
      {role === "student" && <StudentOverview viewerId={viewer.id} roles={viewer.roles} />}{/* or the student Overview. */}
    </DashboardFrame> // End of the frame.
  ); // End of what is shown.
} // End of HomePage.
