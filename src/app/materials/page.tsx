import { redirect } from "next/navigation";
import { RoleTabs } from "@/components/role-tabs";
import { Card, Empty, Page, SubHeading, TextLink } from "@/components/ui";
import { needsTwoStep, requireViewer } from "@/lib/auth";
import { MATERIAL_KINDS, MATERIAL_KIND_NAMES, type MaterialKind, yearRange } from "@/lib/materials";
import { YEAR_LEVELS } from "@/lib/students";
import { createClient } from "@/lib/supabase/server";

// CLG's materials, for tutors. The database lists only published materials
// for subjects and year levels the tutor teaches.

type Material = {
  id: string;
  title: string;
  kind: MaterialKind;
  subject: string;
  from_level: string;
  to_level: string;
  description: string | null;
  page_count: number | null;
  material_skills: { skill: { code: string | null; description: string; plain_description: string | null } | null }[];
};
type Suggestion = {
  student_id: string;
  student_name: string;
  goal_title: string;
  material_id: string;
  material_title: string;
  matching_skills: number;
};

const selectClass = "rounded-lg border border-zinc-300 bg-white px-3 py-2";

function OpenLink({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <a
      href={`/materials/${id}/file`}
      target="_blank"
      rel="noopener"
      className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700"
    >
      {children}
    </a>
  );
}

export default async function MaterialsPage({ searchParams }: PageProps<"/materials">) {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard");
  if (needsTwoStep(viewer)) redirect("/mfa");
  const params = await searchParams;
  const pick = (k: string) => (typeof params[k] === "string" ? (params[k] as string).trim().slice(0, 100) : "");
  const subject = pick("subject");
  const year = pick("year");
  const kind = pick("kind");
  const q = pick("q").toLowerCase();
  const supabase = await createClient();

  const [list, suggestions] = await Promise.all([
    supabase
      .from("materials")
      .select(
        "id, title, kind, subject, from_level, to_level, description, page_count, material_skills(skill:curriculum_skills(code, description, plain_description))",
      )
      .eq("status", "published")
      .order("subject")
      .order("title"),
    viewer.roles.includes("tutor") ? supabase.rpc("materials_for_my_students") : Promise.resolve({ data: [] }),
  ]);
  const all = (list.data ?? []) as unknown as Material[];
  const subjects = [...new Set(all.map((m) => m.subject))].sort();
  const rank = (y: string) => YEAR_LEVELS.indexOf(y as (typeof YEAR_LEVELS)[number]);
  const shown = all.filter(
    (m) =>
      (!subject || m.subject === subject) &&
      (!kind || m.kind === kind) &&
      (!year || (rank(m.from_level) <= rank(year) && rank(m.to_level) >= rank(year))) &&
      (!q ||
        [m.title, m.description ?? "", ...m.material_skills.map((s) => `${s.skill?.code ?? ""} ${s.skill?.plain_description ?? ""} ${s.skill?.description ?? ""}`)]
          .join(" ")
          .toLowerCase()
          .includes(q)),
  );

  const byStudent = new Map<string, { name: string; goals: Map<string, Suggestion[]> }>();
  for (const s of (suggestions.data ?? []) as Suggestion[]) {
    const entry = byStudent.get(s.student_id) ?? { name: s.student_name, goals: new Map() };
    entry.goals.set(s.goal_title, [...(entry.goals.get(s.goal_title) ?? []), s]);
    byStudent.set(s.student_id, entry);
  }

  return (
    <>
      <RoleTabs roles={viewer.roles} active={viewer.roles.includes("tutor") ? "tutor" : "admin"} />
      <Page
        title="Materials"
        intro="CLG's own materials for the subjects and year levels you teach. Each opens as a copy with your name and email on every page, and CLG keeps a record of what you open (seen only by admins, kept 2 years). Please use them only in your CLG sessions, and don't share, upload or keep copies."
      >
        <p className="text-sm">
          <TextLink href="/dashboard/tutor">Back to your dashboard</TextLink>
        </p>

        {byStudent.size > 0 && (
          <Card title="For your students' goals" description="Materials tagged with skills in your students' current goals.">
            {[...byStudent.values()].map((st) => (
              <div key={st.name}>
                <SubHeading>{st.name}</SubHeading>
                <ul className="space-y-2 text-sm">
                  {[...st.goals].map(([goal, items]) => (
                    <li key={goal}>
                      <span className="text-zinc-600">{goal}: </span>
                      {items.map((i, n) => (
                        <span key={i.material_id}>
                          {n > 0 && ", "}
                          <OpenLink id={i.material_id}>{i.material_title}</OpenLink>
                        </span>
                      ))}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </Card>
        )}

        <Card title="Find a material">
          <form className="mb-5 flex flex-wrap items-end gap-2 text-sm">
            <label className="space-y-1">
              <span className="block text-xs text-zinc-500">Subject</span>
              <select name="subject" defaultValue={subject} className={selectClass}>
                <option value="">All</option>
                {subjects.map((s) => (
                  <option key={s}>{s}</option>
                ))}
              </select>
            </label>
            <label className="space-y-1">
              <span className="block text-xs text-zinc-500">Year level</span>
              <select name="year" defaultValue={year} className={selectClass}>
                <option value="">All</option>
                {YEAR_LEVELS.map((y) => (
                  <option key={y}>{y}</option>
                ))}
              </select>
            </label>
            <label className="space-y-1">
              <span className="block text-xs text-zinc-500">Kind</span>
              <select name="kind" defaultValue={kind} className={selectClass}>
                <option value="">All</option>
                {MATERIAL_KINDS.map((k) => (
                  <option key={k} value={k}>
                    {MATERIAL_KIND_NAMES[k]}
                  </option>
                ))}
              </select>
            </label>
            <label className="space-y-1">
              <span className="block text-xs text-zinc-500">Words or skill code</span>
              <input name="q" defaultValue={pick("q")} className={selectClass} />
            </label>
            <button className="rounded-full border border-zinc-300 px-4 py-2">Find</button>
          </form>

          {shown.length === 0 ? (
            <Empty>
              {all.length === 0
                ? "No materials for what you teach yet. Check your subjects and year levels under \"What you teach\" in your dashboard."
                : "Nothing matches. Try fewer filters."}
            </Empty>
          ) : (
            <ul className="divide-y divide-zinc-100">
              {shown.map((m) => (
                <li key={m.id} className="py-3 text-sm">
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <OpenLink id={m.id}>{m.title}</OpenLink>
                    <span className="text-xs text-zinc-500">
                      {MATERIAL_KIND_NAMES[m.kind] ?? m.kind} · {m.subject} · {yearRange(m.from_level, m.to_level)}
                      {m.page_count && m.page_count > 1 ? ` · ${m.page_count} pages` : ""}
                    </span>
                  </div>
                  {m.description && <p className="mt-1 text-zinc-600">{m.description}</p>}
                  {m.material_skills.length > 0 && (
                    <p className="mt-1 text-xs text-zinc-500">
                      Skills:{" "}
                      {m.material_skills
                        .map((s) => s.skill && (s.skill.code ? `${s.skill.code} ` : "") + (s.skill.plain_description || s.skill.description))
                        .filter(Boolean)
                        .join("; ")}
                    </p>
                  )}
                </li>
              ))}
            </ul>
          )}
        </Card>
      </Page>
    </>
  );
}
