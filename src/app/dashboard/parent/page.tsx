import { requireFamilyAgreement } from "@/lib/consent";
import { redirect } from "next/navigation";
import { Card, Empty, TextLink } from "@/components/ui";
import { RoleTabs } from "@/components/role-tabs";
import { SectionShell } from "@/components/section-shell";
import { requireViewer } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AddChildForm } from "../add-child-form";
import { EditChildForm } from "../edit-child-form";
import { TutorList, loadStudentsAndTutors } from "../shared";

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
  const [links, subjectRows] = await Promise.all([
    supabase.from("parent_student_links").select("student_id, verified_at"),
    supabase.from("student_subjects").select("student_id, subject, working_level").order("added_at"),
  ]);
  const subjectsOf = (id: string) =>
    (subjectRows.data ?? [])
      .filter((r) => r.student_id === id)
      .map((r) => ({ subject: r.subject, level: r.working_level as string | null }));
  const verified = new Set((links.data ?? []).filter((l) => l.verified_at).map((l) => l.student_id));
  const waiting = students.some((s) => !verified.has(s.id));

  return (
    <>
      <RoleTabs roles={viewer.roles} active="parent" />
      <SectionShell basePath="/dashboard/parent" label="Parent" section={section} sections={[...SECTIONS]}>
        {section === "children" && (
          <>
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
            <p className="text-sm">
              <TextLink href="/billing">Billing: your plan, invoices and credit</TextLink>
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
      </SectionShell>
    </>
  );
}
