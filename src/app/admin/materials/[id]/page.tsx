import { notFound } from "next/navigation";
import { z } from "zod";
import { RoleTabs } from "@/components/role-tabs";
import { Card, Empty, Page, SubHeading, TextLink } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { MATERIAL_STATUS_NAMES, yearRange } from "@/lib/materials";
import { createClient } from "@/lib/supabase/server";
import { AddSkillsForm, MaterialDetailsForm, PublishForm, TaggedSkill, type SkillOption } from "../forms";

// One material (admin): its details, its curriculum skills, and publishing.

export default async function AdminMaterialPage({ params, searchParams }: PageProps<"/admin/materials/[id]">) {
  const viewer = await requireAdmin();
  const { id } = await params;
  if (!z.uuid().safeParse(id).success) notFound();
  const sp = await searchParams;
  const q = typeof sp.q === "string" ? sp.q.trim().slice(0, 100) : "";
  const supabase = await createClient();

  const { data: m } = await supabase
    .from("materials")
    .select(
      "id, title, kind, subject, from_level, to_level, description, status, no_skills_reason, file_type, file_bytes, page_count, source_path, source_name, published_at",
    )
    .eq("id", id)
    .maybeSingle();
  if (!m) notFound();

  const [tagged, options, opens] = await Promise.all([
    supabase
      .from("material_skills")
      .select(
        "skill:curriculum_skills(id, subject, level_band, code, description, plain_description, framework:curriculum_frameworks(code, version))",
      )
      .eq("material_id", id),
    supabase.rpc("skills_for_material", { p_subject: m.subject, p_from: m.from_level, p_to: m.to_level, p_search: q || null }),
    supabase.from("material_opens").select("id", { count: "exact", head: true }).eq("material_id", id),
  ]);
  const taggedSkills: SkillOption[] = (
    (tagged.data ?? []) as unknown as {
      skill: Omit<SkillOption, "framework"> & { framework: { code: string; version: string } | null };
    }[]
  )
    .filter((t) => t.skill)
    .map((t) => ({ ...t.skill, framework: t.skill.framework ? `${t.skill.framework.code} v${t.skill.framework.version}` : "" }));
  const taggedIds = new Set(taggedSkills.map((s) => s.id));
  const choices = ((options.data ?? []) as SkillOption[]).filter((s) => !taggedIds.has(s.id));

  return (
    <>
      <RoleTabs roles={viewer.roles} active="admin" />
      <Page title={m.title} intro={`${m.subject}, ${yearRange(m.from_level, m.to_level)}. ${MATERIAL_STATUS_NAMES[m.status] ?? m.status}.`}>
        <p className="text-sm">
          <TextLink href="/admin/materials?section=library">Back to the library</TextLink>
          {" · "}
          <a href={`/materials/${m.id}/file`} target="_blank" rel="noopener" className="font-medium text-teal-700 underline">
            Open it as tutors see it
          </a>
          {m.source_path && (
            <>
              {" · "}
              <a href={`/admin/materials/${m.id}/source`} className="font-medium text-teal-700 underline">
                Download the editable original
              </a>
            </>
          )}
        </p>

        <Card
          title="Curriculum skills"
          description="Tag the specific skills this material works on. Tags decide what it will be suggested for, from a student's goals now and from roadmaps later."
        >
          <SubHeading>Tagged ({taggedSkills.length})</SubHeading>
          {taggedSkills.length === 0 ? (
            <Empty>No skills yet.</Empty>
          ) : (
            <ul className="divide-y divide-zinc-100">
              {taggedSkills.map((s) => (
                <TaggedSkill key={s.id} id={m.id} skill={s} />
              ))}
            </ul>
          )}

          <SubHeading>Add skills</SubHeading>
          <p className="mb-3 text-sm text-zinc-600">
            Showing skills from confirmed curricula for {m.subject}, {yearRange(m.from_level, m.to_level)}. Search to narrow the
            list (code or words).
          </p>
          <form className="mb-3 flex gap-2 text-sm">
            <input
              name="q"
              defaultValue={q}
              placeholder="For example fractions or AC9M5N"
              className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2"
            />
            <button className="rounded-full border border-zinc-300 px-4 py-2">Search</button>
          </form>
          {choices.length === 0 ? (
            <Empty>
              No skills found. Check the subject and years in the details below, or load the curriculum under{" "}
              <TextLink href="/admin?section=curriculum">Admin, Curriculum</TextLink>.
            </Empty>
          ) : (
            <AddSkillsForm id={m.id} options={choices} />
          )}
          {choices.length === 300 && <p className="mt-2 text-xs text-zinc-500">Showing the first 300. Search to find others.</p>}
        </Card>

        <Card title={m.status === "published" ? "Published" : "Publish"}>
          <p className="mb-4 text-sm text-zinc-600">
            {m.status === "published"
              ? `Tutors who teach ${m.subject} at any of ${yearRange(m.from_level, m.to_level)} can open it. Opened ${opens.count ?? 0} time${opens.count === 1 ? "" : "s"}.`
              : "Once published, tutors who teach this subject at these year levels can open a copy with their name on it."}
          </p>
          <PublishForm m={m} skillCount={taggedSkills.length} />
        </Card>

        <Card collapsible defaultOpen={false} title="Details" description="Title, kind, subject, year levels and the note for tutors.">
          <MaterialDetailsForm m={m} />
          <p className="mt-4 text-xs text-zinc-500">
            File: {m.file_type === "application/pdf" ? `PDF, ${m.page_count ?? "?"} page${m.page_count === 1 ? "" : "s"}` : "picture"},{" "}
            {Math.max(1, Math.round(m.file_bytes / 1024))} KB. To change the file, add it again as a new material and retire
            this one.
          </p>
        </Card>
      </Page>
    </>
  );
}
