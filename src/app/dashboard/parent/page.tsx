import { requireFamilyAgreement } from "@/lib/consent";
import { redirect } from "next/navigation";
import { Card, Empty, TextLink } from "@/components/ui";
import { RoleTabs } from "@/components/role-tabs";
import { CountBadge } from "@/components/count-badge";
import { getToDoCounts } from "@/lib/to-do-counts";
import { SectionShell } from "@/components/section-shell";
import { SessionAnswersCard, getOffersToAnswer } from "@/components/session-answers-card"; // The "waiting for your answer" card and its count.
import { requireViewer } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AddChildForm } from "../add-child-form";
import { EditChildForm } from "../edit-child-form";
import { OwnLoginForm } from "../own-login-form";
import { NewUpdates, TutorList, loadStudentsAndTutors, missingDetails } from "../shared";

type SubjectRow = {
  student_id: string;
  subject: string;
  working_level: string | null;
  course_code?: string | null;
  course_url?: string | null;
};

// Falls back to the basic fields if the university/TAFE database update
// hasn't been run yet, so children and their subjects still show.
async function loadSubjects(supabase: Awaited<ReturnType<typeof createClient>>): Promise<SubjectRow[]> {
  const full = await supabase
    .from("student_subjects")
    .select("student_id, subject, working_level, course_code, course_url")
    .order("added_at");
  if (!full.error) return (full.data ?? []) as SubjectRow[];
  const core = await supabase.from("student_subjects").select("student_id, subject, working_level").order("added_at");
  return (core.data ?? []) as SubjectRow[];
}

const SECTIONS = [
  { id: "children", label: "Your children" },
  { id: "add", label: "Add a child" },
] as const;

export default async function ParentDashboard({ searchParams }: PageProps<"/dashboard/parent">) {
  const viewer = await requireViewer();
  await requireFamilyAgreement(viewer);
  if (!viewer.roles.includes("parent")) redirect("/dashboard");
  const params = await searchParams;
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "children";

  const supabase = await createClient();
  const { students, assignments } = await loadStudentsAndTutors();
  const [links, subjectRows, logins] = await Promise.all([
    supabase.from("parent_student_links").select("student_id, verified_at"),
    loadSubjects(supabase),
    supabase.from("students").select("id, account_id"),
  ]);
  const subjectsOf = (id: string) =>
    subjectRows
      .filter((r) => r.student_id === id)
      .map((r) => ({
        subject: r.subject,
        level: r.working_level as string | null,
        course_code: r.course_code ?? null,
        course_url: r.course_url ?? null,
      }));
  // Children 16 or over without their own login can be given one.
  const hasLogin = new Set((logins.data ?? []).filter((r) => r.account_id).map((r) => r.id));
  const sixteenAgo = new Date();
  sixteenAgo.setFullYear(sixteenAgo.getFullYear() - 16);
  const canHaveLogin = (s: { id: string; date_of_birth: string | null }) =>
    !hasLogin.has(s.id) && !!s.date_of_birth && s.date_of_birth <= sixteenAgo.toISOString().slice(0, 10);
  const verified = new Set((links.data ?? []).filter((l) => l.verified_at).map((l) => l.student_id));
  const waiting = students.some((s) => !verified.has(s.id));
  // Children CLG set up for the family, with details still to give.
  const unfinished = students
    .map((s) => ({ child: s, missing: missingDetails(s, subjectsOf(s.id).length) }))
    .filter((u) => u.missing.length > 0);

  // Numbers where something needs doing: details to finish, billing to set up.
  const todo = await getToDoCounts(viewer.roles);
  const offers = await getOffersToAnswer(); // Session times waiting for this parent's approval.

  return (
    <>
      <RoleTabs roles={viewer.roles} active="parent" />
      <SectionShell
        basePath="/dashboard/parent"
        label="Parent"
        role="parent"
        section={section}
        sections={SECTIONS.map((s) => ({ ...s, count: s.id === "children" ? todo.get("parent", "children") : undefined }))}
      >
        {/* Session times to approve, and new notices, on every section so they aren't missed. */}
        <SessionAnswersCard waiting={offers.as_family} notices={todo.get("sessions", "notices") ?? 0} who="family" />
        {section === "children" && (
          <>
            {unfinished.map(({ child, missing }) => (
              <Card
                key={child.id}
                title={`Please finish ${child.full_name}'s details`}
                description={`CLG has started ${child.full_name}'s profile. Please add the ${missing.join(", ")}, so we can match the right tutor.`}
              >
                <EditChildForm child={child} subjects={subjectsOf(child.id)} />
              </Card>
            ))}
            {waiting && (
              <Card title="What happens next">
                <ol className="list-decimal space-y-2 pl-5 text-sm">
                  <li>CLG checks your child&apos;s details. We may contact you to confirm them.</li>
                  <li>We match your child with a tutor who suits their year level, subject and location.</li>
                  <li>
                    Once that&apos;s done, you&apos;ll see your child&apos;s tutor here, plus a{" "}
                    <strong>Progress</strong> page with their goals and a next step after each session.
                  </li>
                </ol>
                <p className="mt-3 text-sm text-zinc-500">You don&apos;t need to do anything else for now.</p>
              </Card>
            )}
            <NewUpdates />
            <p className="text-sm">
              <TextLink href="/billing">Billing: your plan, invoices and credit</TextLink>{" "}
              <CountBadge n={todo.get("family", "billing")} className="bg-parent-strong text-white" />
            </p>
            <Card title="Your children">
              {students.length === 0 ? (
                <Empty>
                  No children added yet. <TextLink href="/dashboard/parent?section=add">Add your child</TextLink> to get
                  started.
                </Empty>
              ) : (
                <ul className="divide-y divide-zinc-100">
                  {students.map((s) => (
                    <li key={s.id} className="py-3 text-sm first:pt-0 last:pb-0">
                      <div className="flex flex-wrap items-baseline justify-between gap-2">
                        <span>
                          <span className="font-medium">{s.full_name}</span>
                          <span className="text-zinc-600">
                            {s.year_level && ` · ${s.year_level}`}
                            {s.school && ` · ${s.school}`}
                          </span>
                        </span>
                        {verified.has(s.id) ? (
                          <TextLink href={`/students/${s.id}/progress?view=family`}>Progress</TextLink>
                        ) : (
                          <span className="rounded-full bg-zinc-100 px-3 py-0.5 text-xs text-zinc-600">
                            CLG is checking the details
                          </span>
                        )}
                      </div>
                      <p className="mt-1 text-zinc-600">
                        {subjectsOf(s.id).length > 0 ? `Help with: ${subjectsOf(s.id)
                              .map((x) => (x.level ? `${x.subject} (working at ${x.level})` : x.subject))
                              .join(", ")}` : "No subjects chosen yet"}
                      </p>
                      <TutorList assignments={assignments.filter((a) => a.student_id === s.id)} />
                      <details className="group mt-2">
                        <summary className="text-sm text-teal-800 underline hover:font-bold">
                          <span className="group-open:hidden">See or change details</span>
                          <span className="hidden group-open:inline">Close details</span>
                        </summary>
                        <div className="mt-3 rounded-xl border border-zinc-200 p-4">
                          <EditChildForm child={s} subjects={subjectsOf(s.id)} />
                        </div>
                      </details>
                      {canHaveLogin(s) && (
                        <details className="group mt-2">
                          <summary className="text-sm text-teal-800 underline hover:font-bold">
                            Give {s.full_name} their own login
                          </summary>
                          <div className="mt-3 rounded-xl border border-zinc-200 p-4">
                            <OwnLoginForm studentId={s.id} name={s.full_name} />
                          </div>
                        </details>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          </>
        )}
        {section === "add" && (
          <Card title="Add a child">
            <AddChildForm />
          </Card>
        )}
        {!viewer.roles.includes("student") && (
          <p className="text-sm text-zinc-600">
            Want to learn with CLG yourself? <TextLink href="/dashboard/learn">Add a student profile</TextLink>
          </p>
        )}
      </SectionShell>
    </>
  );
}
