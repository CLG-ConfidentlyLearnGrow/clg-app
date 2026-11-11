// Summary: the page where an adult adds a student profile to their own account.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { Card, Page } from "@/components/ui"; // The card and page frame.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Checks two-step login, and makes sure someone is signed in.
import { LearnerForm } from "./learner-form"; // The form for the student profile.

// "Become a learner too": add a student profile to this account.
export default async function LearnPage() {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login not set up: sends them to set it up.
  if (viewer.roles.includes("student")) redirect("/dashboard/student"); // Already a student: sends them to their student dashboard.
  return ( // Shows:
    <Page // a page:
      title="Learn with CLG too" // titled "Learn with CLG too",
      intro="Add a student profile to your account. You keep the same login and get a Student tab next to your other dashboards. You need to be 16 or over." // with a short explanation.
    >{/* (end of the page's settings) */}
      <Card>{/* A card: */}
        <LearnerForm />{/* holding the form. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of LearnPage.
