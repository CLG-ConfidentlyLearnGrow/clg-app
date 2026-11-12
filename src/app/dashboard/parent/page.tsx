// Summary: the parent dashboard: children's details to finish, what happens
// next, updates, billing, each child (tutor, progress, details, own login), and adding a child.
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
import { AddChildForm } from "../add-child-form"; // The "add a child" form.
import { EditChildForm } from "../edit-child-form"; // The "change a child's details" form.
import { OwnLoginForm } from "../own-login-form"; // The "give a child their own login" form.
import { NewUpdates, TutorList, loadStudentsAndTutors, missingDetails } from "../shared"; // Shared dashboard parts: updates, tutor list, the student loader, and missing details.

type SubjectRow = { // One subject a child wants help with:
  student_id: string; // the child,
  subject: string; // the subject,
  working_level: string | null; // the level they're working at (if known),
  course_code?: string | null; // a university or TAFE unit code (if any),
  course_url?: string | null; // and a link to the unit (if any).
}; // End of SubjectRow.

// Falls back to the basic fields if the university/TAFE database update
// hasn't been run yet, so children and their subjects still show.
async function loadSubjects(supabase: Awaited<ReturnType<typeof createClient>>): Promise<SubjectRow[]> { // Reads each child's subjects.
  const full = await supabase // Tries the full read:
    .from("student_subjects") // from student_subjects,
    .select("student_id, subject, working_level, course_code, course_url") // with unit code and link,
    .order("added_at"); // oldest first.
  if (!full.error) return (full.data ?? []) as SubjectRow[]; // Worked: returns them.
  const core = await supabase.from("student_subjects").select("student_id, subject, working_level").order("added_at"); // Otherwise reads just the basic fields.
  return (core.data ?? []) as SubjectRow[]; // Returns those.
} // End of loadSubjects.

const SECTIONS = [ // The side menu's sections:
  { id: "children", label: "Your children" }, // the children list,
  { id: "add", label: "Add a child" }, // the add-a-child form.
] as const; // End of the sections.

export default async function ParentDashboard({ searchParams }: PageProps<"/dashboard/parent">) { // The page itself (reads the address's settings).
  const viewer = await requireViewer(); // The signed-in person.
  await requireFamilyAgreement(viewer); // Makes sure they've agreed to the family terms.
  if (!viewer.roles.includes("parent")) redirect("/dashboard"); // Not a parent: sends them to their main dashboard.
  const params = await searchParams; // The address's settings.
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "children"; // Which section is open (children if none or unknown).

  const supabase = await createClient(); // Connects to the database.
  const { students, assignments } = await loadStudentsAndTutors(); // The children and their tutors.
  const [links, subjectRows, logins] = await Promise.all([ // Reads three things at once:
    supabase.from("parent_student_links").select("student_id, verified_at"), // which children CLG has checked,
    loadSubjects(supabase), // the children's subjects,
    supabase.from("students").select("id, account_id"), // and which children have their own login.
  ]); // End of the reads.
  const subjectsOf = (id: string) => // Gives one child's subjects:
    subjectRows // from all the subjects,
      .filter((r) => r.student_id === id) // just this child's,
      .map((r) => ({ // each as:
        subject: r.subject, // the subject,
        level: r.working_level as string | null, // the level,
        course_code: r.course_code ?? null, // the unit code,
        course_url: r.course_url ?? null, // and the unit link.
      })); // End of subjectsOf.
  // Children 16 or over without their own login can be given one.
  const hasLogin = new Set((logins.data ?? []).filter((r) => r.account_id).map((r) => r.id)); // The children who already have their own login.
  const sixteenAgo = new Date(); // Today's date,
  sixteenAgo.setFullYear(sixteenAgo.getFullYear() - 16); // moved back 16 years.
  const canHaveLogin = (s: { id: string; date_of_birth: string | null }) => // Whether a child can be given a login:
    !hasLogin.has(s.id) && !!s.date_of_birth && s.date_of_birth <= sixteenAgo.toISOString().slice(0, 10); // no login yet, and born at least 16 years ago.
  const verified = new Set((links.data ?? []).filter((l) => l.verified_at).map((l) => l.student_id)); // The children CLG has checked.
  const waiting = students.some((s) => !verified.has(s.id)); // Whether any child is still waiting for CLG's check.
  // Children CLG set up for the family, with details still to give.
  const unfinished = students // Children with details still to give:
    .map((s) => ({ child: s, missing: missingDetails(s, subjectsOf(s.id).length) })) // each child with what's missing,
    .filter((u) => u.missing.length > 0); // keeping only those missing something.

  // Numbers where something needs doing: details to finish, billing to set up.
  const todo = await getToDoCounts(viewer.roles); // The to-do numbers.

  return ( // Shows:
    <>{/* (a group) */}
      <RoleTabs roles={viewer.roles} active="parent" />{/* the dashboard tabs, with Parent open, */}
      <SectionShell // the page frame:
        basePath="/dashboard/parent" // at this address,
        label="Parent" // labelled "Parent",
        role="parent" // in the parent colours,
        section={section} // on the open section,
        sections={SECTIONS.map((s) => ({ ...s, count: s.id === "children" ? todo.get("parent", "children") : undefined }))} // with the children's to-do number on the menu.
      >{/* (end of the frame's settings) */}
        {section === "children" && ( // The children section:
          <>{/* (a group) */}
            {unfinished.map(({ child, missing }) => ( // for each child with details to finish:
              <Card // a card:
                key={child.id} // one per child,
                title={`Please finish ${child.full_name}'s details`} // asking to finish their details,
                description={`CLG has started ${child.full_name}'s profile. Please add the ${missing.join(", ")}, so we can match the right tutor.`} // saying what's missing and why.
              >{/* (end of the card's settings) */}
                <EditChildForm child={child} subjects={subjectsOf(child.id)} />{/* the form to fill them in. */}
              </Card> // End of the card.
            ))}{/* End of the loop. */}
            {waiting && ( // If a child is waiting for CLG's check:
              <Card title="What happens next">{/* a "What happens next" card: */}
                <ol className="list-decimal space-y-2 pl-5 text-sm">{/* a numbered list: */}
                  <li>CLG checks your child&apos;s details. We may contact you to confirm them.</li>{/* step 1: CLG checks the details, */}
                  <li>We match your child with a tutor who suits their year level, subject and location.</li>{/* step 2: CLG finds a tutor, */}
                  <li>{/* step 3: */}
                    Once that&apos;s done, you&apos;ll see your child&apos;s tutor here, plus a{" "}{/* the tutor and progress page will show, */}
                    <strong>Progress</strong> page with their goals and a next step after each session.{/* with goals and next steps. */}
                  </li>{/* End of step 3. */}
                </ol>{/* End of the list. */}
                <p className="mt-3 text-sm text-zinc-500">You don&apos;t need to do anything else for now.</p>{/* Nothing else to do for now. */}
              </Card> // End of the card.
            )}{/* End of this part. */}
            <NewUpdates />{/* New updates. */}
            <p className="text-sm">{/* a line: */}
              <TextLink href="/billing">Billing: your plan, invoices and credit</TextLink>{" "}{/* a link to billing, then a space, */}
              <CountBadge n={todo.get("family", "billing")} className="bg-parent-strong text-white" />{/* and its to-do number. */}
            </p>{/* End of the line. */}
            <Card title="Your children">{/* the "Your children" card: */}
              {students.length === 0 ? ( // if no children yet:
                <Empty>{/* a line: */}
                  No children added yet. <TextLink href="/dashboard/parent?section=add">Add your child</TextLink> to get
                  started.{/* with a link to add a child. */}
                </Empty> // End of the line.
              ) : ( // otherwise:
                <ul className="divide-y divide-zinc-100">{/* a list: */}
                  {students.map((s) => ( // for each child:
                    <li key={s.id} className="py-3 text-sm first:pt-0 last:pb-0">{/* a row: */}
                      <div className="flex flex-wrap items-baseline justify-between gap-2">{/* the top line: */}
                        <span>{/* (a group) */}
                          <span className="font-medium">{s.full_name}</span>{/* the child's name, */}
                          <span className="text-zinc-600">{/* in grey: */}
                            {s.year_level && ` · ${s.year_level}`}{/* their year level (if known), */}
                            {s.school && ` · ${s.school}`}{/* and school (if known). */}
                          </span>{/* End of the grey part. */}
                        </span>{/* End of the group. */}
                        {verified.has(s.id) ? ( // If CLG has checked them:
                          <TextLink href={`/students/${s.id}/progress?view=family`}>Progress</TextLink> // a link to their progress page.
                        ) : ( // otherwise:
                          <span className="rounded-full bg-zinc-100 px-3 py-0.5 text-xs text-zinc-600">{/* a grey tag: */}
                            CLG is checking the details{/* saying CLG is checking. */}
                          </span> // End of the tag.
                        )}{/* End of this part. */}
                      </div>{/* End of the top line. */}
                      <p className="mt-1 text-zinc-600">{/* a line listing the subjects (and levels) they get help with, or saying none yet: */}
                        {subjectsOf(s.id).length > 0 ? `Help with: ${subjectsOf(s.id)
                              .map((x) => (x.level ? `${x.subject} (working at ${x.level})` : x.subject))
                              .join(", ")}` : "No subjects chosen yet"}{/* (end of the subjects) */}
                      </p>{/* End of the line. */}
                      <TutorList assignments={assignments.filter((a) => a.student_id === s.id)} />{/* their tutors. */}
                      <details className="group mt-2">{/* a fold-out section: */}
                        <summary className="text-sm text-teal-800 underline hover:font-bold">{/* its heading: */}
                          <span className="group-open:hidden">See or change details</span>{/* "See or change details" when closed, */}
                          <span className="hidden group-open:inline">Close details</span>{/* "Close details" when open. */}
                        </summary>{/* End of the heading. */}
                        <div className="mt-3 rounded-xl border border-zinc-200 p-4">{/* a box: */}
                          <EditChildForm child={s} subjects={subjectsOf(s.id)} />{/* the form to change their details. */}
                        </div>{/* End of the box. */}
                      </details>{/* End of the fold-out. */}
                      {canHaveLogin(s) && ( // If they can have their own login:
                        <details className="group mt-2">{/* a fold-out section: */}
                          <summary className="text-sm text-teal-800 underline hover:font-bold">{/* its heading: */}
                            Give {s.full_name} their own login{/* offers to give them their own login. */}
                          </summary>{/* End of the heading. */}
                          <div className="mt-3 rounded-xl border border-zinc-200 p-4">{/* a box: */}
                            <OwnLoginForm studentId={s.id} name={s.full_name} />{/* the own-login form. */}
                          </div>{/* End of the box. */}
                        </details> // End of the fold-out.
                      )}{/* End of this part. */}
                    </li> // End of the row.
                  ))}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}
          </> // End of the group.
        )}{/* End of the children section. */}
        {section === "add" && ( // The add-a-child section:
          <Card title="Add a child">{/* a card: */}
            <AddChildForm />{/* the form. */}
          </Card> // End of the card.
        )}{/* End of this part. */}
        {!viewer.roles.includes("student") && ( // If they aren't a student too:
          <p className="text-sm text-zinc-600">{/* a line: */}
            Want to learn with CLG yourself? <TextLink href="/dashboard/learn">Add a student profile</TextLink>{/* offering to add a student profile for themselves. */}
          </p> // End of the line.
        )}{/* End of this part. */}
      </SectionShell>{/* End of the page frame. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of ParentDashboard.
