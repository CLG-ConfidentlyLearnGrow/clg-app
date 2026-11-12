// Summary: the admin page for one material: open it, tag curriculum skills, publish, and edit details.
//
import { notFound } from "next/navigation"; // Shows the "not found" page.
import { z } from "zod"; // The form-checking library (used to check the id).
import { RoleTabs } from "@/components/role-tabs"; // The tabs for each dashboard.
import { Card, Empty, Page, SubHeading, TextLink } from "@/components/ui"; // The card, "nothing yet" note, page frame, small heading and link style.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is an admin.
import { MATERIAL_STATUS_NAMES, yearRange } from "@/lib/materials"; // Material status names, and year ranges in words.
import { SUBJECT_SUGGESTIONS, YEAR_LEVELS } from "@/lib/students"; // Suggested subjects, and the list of year levels.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { AddSkillsForm, MaterialDetailsForm, PublishForm, TaggedSkill, type SkillOption } from "../forms"; // The forms on this page, and the skill option type.

// Lists the year levels from one to another, e.g. Year 3 to Year 5.
function yearsOf(from: string, to: string) {
  const all = YEAR_LEVELS as readonly string[]; // All the year levels.
  return all.slice(all.indexOf(from), all.indexOf(to) + 1); // The ones from "from" to "to".
} // End of yearsOf.

// One material (admin): its details, its curriculum skills, and publishing.

// Shows the page for one material.
export default async function AdminMaterialPage({ params, searchParams }: PageProps<"/admin/materials/[id]">) {
  const viewer = await requireAdmin(); // Makes sure the person is an admin, and gets who they are.
  const { id } = await params; // The material's id from the address.
  if (!z.uuid().safeParse(id).success) notFound(); // Odd id: not found.
  const sp = await searchParams; // The search settings from the address.
  const q = typeof sp.q === "string" ? sp.q.trim().slice(0, 100) : ""; // The words to search for (up to 100 characters).
  const year = typeof sp.year === "string" && (YEAR_LEVELS as readonly string[]).includes(sp.year) ? sp.year : ""; // The year level to narrow by, if it's a real one.
  const skillSubject = typeof sp.subject === "string" && sp.subject.trim() ? sp.subject.trim().slice(0, 100) : ""; // The subject to search skills in, if given.
  const supabase = await createClient(); // Connects to the database.

  const { data: m } = await supabase // Reads the material:
    .from("materials") // from the materials table,
    .select( // (with these fields:)
      "id, title, kind, subject, from_level, to_level, description, status, no_skills_reason, file_type, file_bytes, page_count, source_path, source_name, published_at", // its details,
    ) // (end of the fields)
    .eq("id", id) // by id,
    .maybeSingle(); // (one at most).
  if (!m) notFound(); // Not found: shows the "not found" page.

  const [tagged, options, opens] = await Promise.all([ // Reads three things at once:
    supabase // its tagged skills:
      .from("material_skills") // (from the material skills table)
      .select( // (with:)
        "skill:curriculum_skills(id, subject, level_band, code, description, plain_description, framework:curriculum_frameworks(code, version))", // each skill's details and its curriculum,
      ) // (end of the fields)
      .eq("material_id", id), // for this material;
    supabase.rpc("skills_for_material", { // the skills that could be tagged:
      p_subject: skillSubject || m.subject, // in the chosen subject (or the material's),
      p_from: m.from_level, // from its lowest year level,
      p_to: m.to_level, // to its highest,
      p_search: q || null, // matching the words (if any),
      p_year: year || null, // and the year (if any);
    }), // (end of the search)
    supabase.from("material_opens").select("id", { count: "exact", head: true }).eq("material_id", id), // and how many times it's been opened.
  ]); // End of the reads.
  const taggedSkills: SkillOption[] = ( // The tagged skills:
    (tagged.data ?? []) as unknown as { // (as the database gives them:)
      skill: Omit<SkillOption, "framework"> & { framework: { code: string; version: string } | null }; // each with its curriculum's code and version,
    }[] // (end of the shape)
  ) // (end of the list)
    .filter((t) => t.skill) // leaving out missing ones,
    .map((t) => ({ ...t.skill, framework: t.skill.framework ? `${t.skill.framework.code} v${t.skill.framework.version}` : "" })); // with the curriculum written as e.g. "AC9 v9.0".
  const taggedIds = new Set(taggedSkills.map((s) => s.id)); // The tagged skills' ids.
  const choices = ((options.data ?? []) as SkillOption[]).filter((s) => !taggedIds.has(s.id)); // The skills to choose from, leaving out ones already tagged.

  return ( // Shows:
    <>{/* (a group:) */}
      <RoleTabs roles={viewer.roles} active="admin" />{/* the dashboard tabs, */}
      <Page role="admin" title={m.title} intro={`${m.subject}, ${yearRange(m.from_level, m.to_level)}. ${MATERIAL_STATUS_NAMES[m.status] ?? m.status}.`}>{/* a page titled with the material, its subject, years and status: */}
        <p className="text-sm">{/* a line of links: */}
          <TextLink href="/admin/materials?section=library">Back to the library</TextLink>{/* back to the library, */}
          {" · "}{/* (a dot) */}
          <a href={`/materials/${m.id}/file`} target="_blank" rel="noopener" className="font-medium text-teal-700 underline">{/* a link that opens the stamped copy in a new tab: */}
            Open it as tutors see it{/* "Open it as tutors see it". */}
          </a>{/* End of the link. */}
          {m.source_path && ( // If there's an editable original:
            <>{/* (a group:) */}
              {" · "}{/* (a dot) */}
              <a href={`/admin/materials/${m.id}/source`} className="font-medium text-teal-700 underline">{/* a link that downloads it: */}
                Download the editable original{/* "Download the editable original". */}
              </a>{/* End of the link. */}
            </> // (end of the group)
          )}{/* End of that part. */}
        </p>{/* End of the line. */}

        <Card // A card:
          title="Curriculum skills" // titled "Curriculum skills",
          description="Tag the specific skills this material works on. Tags decide what it will be suggested for, from a student's goals now and from roadmaps later." // with what tags are for.
        >{/* (end of the card's settings) */}
          <SubHeading>Tagged ({taggedSkills.length})</SubHeading>{/* A small heading with how many are tagged, */}
          {taggedSkills.length === 0 ? ( // if none:
            <Empty>No skills yet.</Empty> // says so.
          ) : ( // Otherwise:
            <ul className="divide-y divide-zinc-100">{/* a list: */}
              {taggedSkills.map((s) => ( // for each tagged skill:
                <TaggedSkill key={s.id} id={m.id} skill={s} /> // the skill with a remove button.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of the choice. */}

          <SubHeading>Add skills</SubHeading>{/* A small heading "Add skills", */}
          <p className="mb-3 text-sm text-zinc-600">{/* a grey line: */}
            Skills from confirmed curricula for {yearRange(m.from_level, m.to_level)}. Narrow by subject, year level or words.{/* what's listed and how to narrow it. */}
          </p>{/* End of the line. */}
          <form className="mb-3 flex flex-wrap items-end gap-2 text-sm">{/* A search form (sends the choices in the address): */}
            <label className="space-y-1">{/* a label: */}
              <span className="block text-xs text-zinc-500">Subject</span>{/* "Subject", */}
              <input // a text box:
                name="subject" // its field name,
                list="skill-subjects" // with suggestions,
                defaultValue={skillSubject || m.subject} // starting with the subject in use,
                className="rounded-lg border border-zinc-300 bg-white px-3 py-2" // styled like the other boxes.
              />{/* (end of the box) */}
              <datalist id="skill-subjects">{/* The suggestions list: */}
                {SUBJECT_SUGGESTIONS.map((s) => ( // for each suggested subject:
                  <option key={s} value={s} /> // an option.
                ))}{/* End of the loop. */}
              </datalist>{/* End of the suggestions. */}
            </label>{/* End of the label. */}
            <label className="space-y-1">{/* A label: */}
              <span className="block text-xs text-zinc-500">Year level</span>{/* "Year level", */}
              <select name="year" defaultValue={year} className="rounded-lg border border-zinc-300 bg-white px-3 py-2">{/* a drop-down, starting on the year in use: */}
                <option value="">All of {yearRange(m.from_level, m.to_level)}</option>{/* all the material's years, */}
                {yearsOf(m.from_level, m.to_level).map((y) => ( // for each year:
                  <option key={y}>{y}</option> // an option.
                ))}{/* End of the loop. */}
              </select>{/* End of the drop-down. */}
            </label>{/* End of the label. */}
            <label className="min-w-48 flex-1 space-y-1">{/* A wider label: */}
              <span className="block text-xs text-zinc-500">Words or code</span>{/* "Words or code", */}
              <input // a text box:
                name="q" // its field name,
                defaultValue={q} // starting with the words in use,
                placeholder="For example fractions or AC9M5N" // an example,
                className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2" // styled like the other boxes.
              />{/* (end of the box) */}
            </label>{/* End of the label. */}
            <button className="rounded-full border border-zinc-300 px-4 py-2">Search</button>{/* The "Search" button. */}
          </form>{/* End of the search form. */}
          {choices.length === 0 ? ( // If no skills were found:
            <Empty>{/* a "nothing found" note: */}
              No skills found. Check the subject and years in the details below, or load the curriculum under{" "}{/* what to check, or where to load the curriculum, */}
              <TextLink href="/admin?section=curriculum">Admin, Curriculum</TextLink>.{/* with a link. */}
            </Empty> // End of the note.
          ) : ( // Otherwise:
            <AddSkillsForm id={m.id} options={choices} /> // the form to add skills.
          )}{/* End of the choice. */}
          {choices.length === 300 && <p className="mt-2 text-xs text-zinc-500">Showing the first 300. Search to find others.</p>}{/* A note when the list is cut at 300. */}
        </Card>{/* End of the card. */}

        <Card title={m.status === "published" ? "Published" : "Publish"}>{/* A card, titled by whether it's published: */}
          <p className="mb-4 text-sm text-zinc-600">{/* a grey line: */}
            {m.status === "published" // if published,
              ? `Tutors who teach ${m.subject} at any of ${yearRange(m.from_level, m.to_level)} can open it. Opened ${opens.count ?? 0} time${opens.count === 1 ? "" : "s"}.` // who can open it and how many times it's been opened,
              : "Once published, tutors who teach this subject at these year levels can open a copy with their name on it."}{/* otherwise what publishing does. */}
          </p>{/* End of the line. */}
          <PublishForm m={m} skillCount={taggedSkills.length} />{/* The publish form. */}
        </Card>{/* End of the card. */}

        <Card collapsible defaultOpen={false} title="Details" description="Title, kind, subject, year levels and the note for tutors.">{/* A closed card for the details: */}
          <MaterialDetailsForm m={m} />{/* the details form, */}
          <p className="mt-4 text-xs text-zinc-500">{/* a small grey line: */}
            File: {m.file_type === "application/pdf" ? `PDF, ${m.page_count ?? "?"} page${m.page_count === 1 ? "" : "s"}` : "picture"},{" "}{/* the file's type and pages, */}
            {Math.max(1, Math.round(m.file_bytes / 1024))} KB. To change the file, add it again as a new material and retire
            this one.{/* how to change the file. */}
          </p>{/* End of the line. */}
        </Card>{/* End of the card. */}
      </Page>{/* End of the page. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of AdminMaterialPage.
