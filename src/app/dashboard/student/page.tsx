// Summary: the student dashboard: on-hold notice, new updates, this week's
// steps, tutors, and a link to the progress page.
//
import { requireFamilyAgreement } from "@/lib/consent"; // Sends the person to agree to the family terms first if they haven't.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { Card, Empty, TextLink } from "@/components/ui"; // Shared page parts: a card, an empty-state line and a text link.
import { RoleTabs } from "@/components/role-tabs"; // The tabs for each dashboard the person can use.
import { CountBadge } from "@/components/count-badge"; // The small to-do number badge.
import { getToDoCounts } from "@/lib/to-do-counts"; // Reads the to-do numbers.
import { SectionShell } from "@/components/section-shell"; // The page frame with a side menu.
import { requireViewer } from "@/lib/auth"; // Gets the signed-in person (or sends them to sign in).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { addDays, localToday } from "@/lib/scheduling"; // Date helpers: add days, and today's date.
import { StepRow, type Step } from "@/app/students/[id]/progress/roadmap"; // One roadmap step row, and the step type.
import { NewUpdates, TutorList, loadStudentsAndTutors } from "../shared"; // Shared dashboard parts: new updates, the tutor list, and a loader for students and tutors.

const SECTIONS = [{ id: "learning", label: "Your learning" }] as const; // The side menu's one section.

export default async function StudentDashboard() { // The page itself.
  const viewer = await requireViewer(); // The signed-in person.
  await requireFamilyAgreement(viewer); // Makes sure they've agreed to the family terms.
  if (!viewer.roles.includes("student")) redirect("/dashboard"); // Not a student: sends them to their main dashboard.
  const supabase = await createClient(); // Connects to the database.
  const [{ assignments: all }, own] = await Promise.all([ // Reads two things at once:
    loadStudentsAndTutors(), // every student and tutor this person can see,
    supabase.from("students").select("id").eq("account_id", viewer.id).maybeSingle(), // and their own student record (if any).
  ]); // End of the reads.
  const onHold = await supabase.rpc("my_support_on_hold"); // Whether their sessions are on hold (billing).
  // Only this person's own learning, even if they are also a parent or tutor.
  const me = own.data; // Their student record.
  const assignments = all.filter((a) => a.student_id === me?.id); // Just their own tutors.
  // Steps due in the next week (or overdue), from the student's roadmap.
  const today = localToday(); // Today's date.
  const stepsRes = me // Reads their steps:
    ? await supabase // if they have a student record,
        .from("roadmap_steps") // from roadmap_steps,
        .select("id, target_id, title, due_on, source, done_at, created_by") // these details,
        .eq("student_id", me.id) // for them,
        .is("done_at", null) // not yet done,
        .lte("due_on", addDays(today, 7)) // due within a week (or overdue),
        .order("due_on") // soonest first,
        .limit(10) // up to 10.
    : null; // otherwise nothing.
  const steps = (stepsRes?.data ?? []) as Step[]; // The steps.

  // Numbers where something needs doing: overdue steps, and billing for an
  // adult learner who pays for themselves (a parent sees billing on theirs).
  const todo = await getToDoCounts(viewer.roles); // The to-do numbers.
  const familyBilling = viewer.roles.includes("parent") ? undefined : todo.get("family", "billing"); // Billing's number, unless a parent sees it on their own dashboard.

  return ( // Shows:
    <>{/* (a group) */}
      <RoleTabs roles={viewer.roles} active="student" />{/* the dashboard tabs, with Student open, */}
      <SectionShell // the page frame:
        basePath="/dashboard/student" // at this address,
        label="Student" // labelled "Student",
        role="student" // in the student colours,
        section="learning" // on the learning section,
        sections={SECTIONS.map((s) => ({ ...s, count: todo.forRole("student") }))} // with the student to-do total on the menu.
      >{/* (end of the frame's settings) */}
        {familyBilling && ( // If billing needs something:
          <p className="text-sm">{/* a line: */}
            <TextLink href="/billing">Billing: your plan, invoices and credit</TextLink>{" "}{/* a link to billing, then a space, */}
            <CountBadge n={familyBilling} className="bg-student-strong text-white" />{/* and its number. */}
          </p> // End of the line.
        )}{/* End of this part. */}
        {onHold.data === true && ( // If sessions are on hold:
          <Card title="Sessions on hold">{/* a card: */}
            <p className="text-sm">{/* a line: */}
              Your sessions are on hold for now. Please check with your parent or carer, or see{" "}{/* saying so, and where to check, */}
              <TextLink href="/billing">Billing</TextLink>.{/* with a link to billing. */}
            </p>{/* End of the line. */}
          </Card> // End of the card.
        )}{/* End of this part. */}
        {me && <NewUpdates studentIds={[me.id]} />}{/* New updates, if they have a student record. */}
        {me && steps.length > 0 && ( // If they have steps this week:
          <Card title="Your steps this week">{/* a card: */}
            <ul className="space-y-1.5">{/* a list: */}
              {steps.map((s) => ( // for each step:
                <StepRow key={s.id} step={s} studentId={me.id} today={today} canPlan canRemove={false} /> // its row (they can tick it, not remove it).
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
          </Card> // End of the card.
        )}{/* End of this part. */}
        <Card title="Your tutors">{/* The "Your tutors" card: */}
          {assignments.length === 0 ? <Empty>No tutor yet.</Empty> : <TutorList assignments={assignments} />}{/* none yet, or the list of tutors. */}
        </Card>{/* End of the card. */}
        {me && ( // If they have a student record:
          <Card title="Your next step and progress">{/* a card: */}
            <TextLink href={`/students/${me.id}/progress?view=family`}>Open your progress page</TextLink>{/* a link to their progress page. */}
          </Card> // End of the card.
        )}{/* End of this part. */}
      </SectionShell>{/* End of the page frame. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of StudentDashboard.
