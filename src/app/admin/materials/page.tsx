import { RoleTabs } from "@/components/role-tabs";
import { SectionShell } from "@/components/section-shell";
import { Card, Empty, Table, TextLink } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { MATERIAL_KIND_NAMES, type MaterialKind, yearRange } from "@/lib/materials";
import { LOCAL_TIME_ZONE } from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";
import { UploadMaterialsForm } from "./upload-form";

// Materials library (admin): add materials, tag and publish them, and see
// who has opened what.

const SECTIONS = [
  { id: "add", label: "Add materials" },
  { id: "library", label: "Library" },
  { id: "opens", label: "Who opened what" },
] as const;

const STATUS_FILTERS = [
  { id: "all", label: "All" },
  { id: "needs", label: "Needs tagging" },
  { id: "draft", label: "Drafts" },
  { id: "published", label: "Published" },
  { id: "retired", label: "Retired" },
] as const;

// Busy use worth a look: this many different materials in 7 days.
const BUSY_WEEK = 40;

type Row = {
  id: string;
  title: string;
  kind: MaterialKind;
  subject: string;
  from_level: string;
  to_level: string;
  status: string;
  no_skills_reason: string | null;
  material_skills: { count: number }[];
};

const when = (iso: string) =>
  new Intl.DateTimeFormat("en-AU", {
    timeZone: LOCAL_TIME_ZONE,
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(iso));

export default async function AdminMaterialsPage({ searchParams }: PageProps<"/admin/materials">) {
  const viewer = await requireAdmin();
  const params = await searchParams;
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "library";
  const filter = STATUS_FILTERS.find((f) => f.id === params.show)?.id ?? "all";
  const q = typeof params.q === "string" ? params.q.trim().slice(0, 100) : "";
  const supabase = await createClient();

  const [list, summary, recent] = await Promise.all([
    supabase
      .from("materials")
      .select("id, title, kind, subject, from_level, to_level, status, no_skills_reason, material_skills(count)")
      .order("subject")
      .order("title"),
    supabase.rpc("material_open_summary", { p_days: 7 }),
    supabase
      .from("material_opens")
      .select("id, opened_at, account:accounts(full_name), material:materials(id, title)")
      .order("opened_at", { ascending: false })
      .limit(50),
  ]);
  const all = (list.data ?? []) as unknown as Row[];
  const untagged = (r: Row) => (r.material_skills[0]?.count ?? 0) === 0 && !r.no_skills_reason;
  const needs = all.filter((r) => r.status === "draft" || untagged(r));
  const shown = all
    .filter((r) =>
      filter === "all" ? true : filter === "needs" ? r.status === "draft" || untagged(r) : r.status === filter,
    )
    .filter((r) => !q || `${r.title} ${r.subject}`.toLowerCase().includes(q.toLowerCase()));
  const busy = ((summary.data ?? []) as { account_id: string; full_name: string; opens: number; different_materials: number; last_opened: string }[]);
  const recentRows = (recent.data ?? []) as unknown as {
    id: number;
    opened_at: string;
    account: { full_name: string } | null;
    material: { id: string; title: string } | null;
  }[];

  return (
    <>
      <RoleTabs roles={viewer.roles} active="admin" />
      <SectionShell
        basePath="/admin/materials"
        label="Materials"
        section={section}
        sections={SECTIONS.map((s) => ({ ...s, count: s.id === "library" ? needs.length || undefined : undefined }))}
      >
        <p className="text-sm">
          <TextLink href="/admin">Back to admin</TextLink>
          {" · "}
          <TextLink href="/materials">See the library as tutors do</TextLink>
        </p>

        {section === "add" && (
          <Card
            title="Add materials"
            description="Upload one file or many. They're saved as drafts; then tag each with its curriculum skills and publish it. Tutors see a material only once it's published, and only for subjects and year levels they teach."
          >
            <UploadMaterialsForm />
          </Card>
        )}

        {section === "library" && (
          <Card
            title="Library"
            description={`${all.length} material${all.length === 1 ? "" : "s"}. ${needs.length} need tagging or publishing.`}
          >
            <form className="mb-4 flex flex-wrap items-end gap-2 text-sm" action="/admin/materials">
              <input type="hidden" name="section" value="library" />
              <label className="space-y-1">
                <span className="block text-xs text-zinc-500">Show</span>
                <select name="show" defaultValue={filter} className="rounded-lg border border-zinc-300 bg-white px-3 py-2">
                  {STATUS_FILTERS.map((f) => (
                    <option key={f.id} value={f.id}>
                      {f.label}
                    </option>
                  ))}
                </select>
              </label>
              <label className="space-y-1">
                <span className="block text-xs text-zinc-500">Search</span>
                <input name="q" defaultValue={q} className="rounded-lg border border-zinc-300 bg-white px-3 py-2" />
              </label>
              <button className="rounded-full border border-zinc-300 px-4 py-2">Go</button>
            </form>
            {shown.length === 0 ? (
              <Empty>
                {all.length === 0 ? (
                  <>
                    Nothing yet. <TextLink href="/admin/materials?section=add">Add your first materials</TextLink>.
                  </>
                ) : (
                  "Nothing matches."
                )}
              </Empty>
            ) : (
              <Table headings={["Title", "Subject", "Years", "Skills", "Status"]}>
                {shown.map((r) => {
                  const count = r.material_skills[0]?.count ?? 0;
                  return (
                    <tr key={r.id}>
                      <td>
                        <TextLink href={`/admin/materials/${r.id}`}>{r.title}</TextLink>
                        <span className="block text-xs text-zinc-500">{MATERIAL_KIND_NAMES[r.kind] ?? r.kind}</span>
                      </td>
                      <td>{r.subject}</td>
                      <td>{yearRange(r.from_level, r.to_level)}</td>
                      <td>{count ? count : r.no_skills_reason ? "None fit" : <span className="text-red-700">Not tagged</span>}</td>
                      <td className="capitalize">{r.status}</td>
                    </tr>
                  );
                })}
              </Table>
            )}
          </Card>
        )}

        {section === "opens" && (
          <>
            <Card
              title="Last 7 days, by person"
              description={`Tutors can open up to 30 different materials a day. Anyone opening ${BUSY_WEEK} or more different materials in a week is marked, in case it's worth a chat.`}
            >
              {busy.length === 0 ? (
                <Empty>No one has opened a material this week.</Empty>
              ) : (
                <Table headings={["Person", "Different materials", "Opens", "Last opened"]}>
                  {busy.map((b) => (
                    <tr key={b.account_id}>
                      <td>
                        {b.full_name}
                        {b.different_materials >= BUSY_WEEK && (
                          <span className="ml-2 rounded-full bg-amber-100 px-2 text-xs text-amber-900">Busy week</span>
                        )}
                      </td>
                      <td>{b.different_materials}</td>
                      <td>{b.opens}</td>
                      <td>{when(b.last_opened)}</td>
                    </tr>
                  ))}
                </Table>
              )}
            </Card>
            <Card title="Latest opens" description="The last 50. Records are kept for 2 years.">
              {recentRows.length === 0 ? (
                <Empty>None yet.</Empty>
              ) : (
                <Table headings={["When", "Person", "Material"]}>
                  {recentRows.map((o) => (
                    <tr key={o.id}>
                      <td>{when(o.opened_at)}</td>
                      <td>{o.account?.full_name}</td>
                      <td>
                        {o.material && <TextLink href={`/admin/materials/${o.material.id}`}>{o.material.title}</TextLink>}
                      </td>
                    </tr>
                  ))}
                </Table>
              )}
            </Card>
          </>
        )}
      </SectionShell>
    </>
  );
}
