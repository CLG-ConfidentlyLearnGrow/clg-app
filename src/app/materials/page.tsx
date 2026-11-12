// Summary: the tutors' materials library: suggestions for their students' goals, and a search.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { RoleTabs } from "@/components/role-tabs"; // The tabs for each dashboard.
import { Card, Empty, Page, SubHeading, TextLink } from "@/components/ui"; // The card, "nothing yet" note, page frame, small heading and link style.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Checks two-step login, and makes sure someone is signed in.
import { MATERIAL_KINDS, MATERIAL_KIND_NAMES, type MaterialKind, yearRange } from "@/lib/materials"; // Material kinds and names, the kind type, and year ranges in words.
import { YEAR_LEVELS } from "@/lib/students"; // The list of year levels.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// CLG's materials, for tutors. The database lists only published materials
// for subjects and year levels the tutor teaches.

// A material as the database gives it.
type Material = {
  id: string; // its id,
  title: string; // title,
  kind: MaterialKind; // kind,
  subject: string; // subject,
  from_level: string; // lowest year level,
  to_level: string; // highest year level,
  description: string | null; // note for tutors (if any),
  page_count: number | null; // number of pages (if known),
  material_skills: { skill: { code: string | null; description: string; plain_description: string | null } | null }[]; // and its skills.
}; // End of the shape.
// A material suggested for one of the tutor's students.
type Suggestion = {
  student_id: string; // the student,
  student_name: string; // their name,
  goal_title: string; // the goal,
  material_id: string; // the material,
  material_title: string; // its title,
  matching_skills: number; // and how many of the goal's skills it covers.
}; // End of the shape.

const selectClass = "rounded-lg border border-zinc-300 bg-white px-3 py-2"; // The style for the search boxes.

// A link that opens a material's stamped copy in a new tab.
function OpenLink({ id, children }: { id: string; children: React.ReactNode }) {
  return ( // Shows:
    <a // a link:
      href={`/materials/${id}/file`} // to the stamped copy,
      target="_blank" // in a new tab,
      rel="noopener" // safely,
      className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700" // styled as a link.
    >{/* (end of its settings) */}
      {children}{/* The link's words. */}
    </a> // End of the link.
  ); // End of what's shown.
} // End of OpenLink.

// Shows the materials library.
export default async function MaterialsPage({ searchParams }: PageProps<"/materials">) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard"); // Not a tutor or admin: goes to the dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login not set up: sends them to set it up.
  const params = await searchParams; // Reads the address settings.
  const pick = (k: string) => (typeof params[k] === "string" ? (params[k] as string).trim().slice(0, 100) : ""); // Reads one search setting (up to 100 characters, or blank).
  const subject = pick("subject"); // The subject chosen,
  const year = pick("year"); // the year chosen,
  const kind = pick("kind"); // the kind chosen,
  const q = pick("q").toLowerCase(); // and the words, in lower case.
  const supabase = await createClient(); // Connects to the database.

  const [list, suggestions] = await Promise.all([ // Reads two things at once:
    supabase // the materials:
      .from("materials") // (from the materials table)
      .select( // (with these fields:)
        "id, title, kind, subject, from_level, to_level, description, page_count, material_skills(skill:curriculum_skills(code, description, plain_description))", // details and skills,
      ) // (end of the fields)
      .eq("status", "published") // published only,
      .order("subject") // by subject,
      .order("title"), // then title;
    viewer.roles.includes("tutor") ? supabase.rpc("materials_for_my_students") : Promise.resolve({ data: [] }), // and, for tutors, materials for their students' goals.
  ]); // End of the reads.
  const all = (list.data ?? []) as unknown as Material[]; // All the materials this tutor can see.
  const subjects = [...new Set(all.map((m) => m.subject))].sort(); // Their subjects, in order.
  const rank = (y: string) => YEAR_LEVELS.indexOf(y as (typeof YEAR_LEVELS)[number]); // A year level's place in the list.
  const shown = all.filter( // The materials to show:
    (m) => // each one:
      (!subject || m.subject === subject) && // in the chosen subject (if any),
      (!kind || m.kind === kind) && // of the chosen kind (if any),
      (!year || (rank(m.from_level) <= rank(year) && rank(m.to_level) >= rank(year))) && // covering the chosen year (if any),
      (!q || // and matching the words (if any):
        [m.title, m.description ?? "", ...m.material_skills.map((s) => `${s.skill?.code ?? ""} ${s.skill?.plain_description ?? ""} ${s.skill?.description ?? ""}`)] // in its title, note and skills,
          .join(" ") // (joined)
          .toLowerCase() // (in lower case)
          .includes(q)), // (containing the words).
  ); // End of the filter.

  const byStudent = new Map<string, { name: string; goals: Map<string, Suggestion[]> }>(); // The suggestions grouped by student, then goal.
  for (const s of (suggestions.data ?? []) as Suggestion[]) { // For each suggestion:
    const entry = byStudent.get(s.student_id) ?? { name: s.student_name, goals: new Map() }; // the student's group (or a new one),
    entry.goals.set(s.goal_title, [...(entry.goals.get(s.goal_title) ?? []), s]); // adds it under its goal,
    byStudent.set(s.student_id, entry); // and saves the group.
  } // End of the loop.

  const materialsRole = viewer.roles.includes("tutor") ? "tutor" : "admin"; // Which dashboard colour to use.
  return ( // Shows:
    <>{/* (a group:) */}
      <RoleTabs roles={viewer.roles} active={materialsRole} />{/* the dashboard tabs, */}
      <Page // a page:
        role={materialsRole} // in that colour,
        title="Materials" // titled "Materials",
        intro="CLG's own materials for the subjects and year levels you teach. Each opens as a copy with your name and email on every page, and CLG keeps a record of what you open (seen only by admins, kept 2 years). Please use them only in your CLG sessions, and don't share, upload or keep copies." // with the rules for using them.
      >{/* (end of the page's settings) */}
        <p className="text-sm">{/* A line: */}
          <TextLink href="/dashboard/tutor">Back to Home</TextLink>{/* with a link back to Home. */}
        </p>{/* End of the line. */}

        {byStudent.size > 0 && ( // If there are suggestions:
          <Card title="For your students' goals" description="Materials tagged with skills in your students' current goals.">{/* a card: */}
            {[...byStudent.values()].map((st) => ( // for each student:
              <div key={st.name}>{/* a block: */}
                <SubHeading>{st.name}</SubHeading>{/* their name as a small heading, */}
                <ul className="space-y-2 text-sm">{/* a list: */}
                  {[...st.goals].map(([goal, items]) => ( // for each goal:
                    <li key={goal}>{/* a list item: */}
                      <span className="text-zinc-600">{goal}: </span>{/* the goal, */}
                      {items.map((i, n) => ( // for each material:
                        <span key={i.material_id}>{/* (a piece:) */}
                          {n > 0 && ", "}{/* a comma before all but the first, */}
                          <OpenLink id={i.material_id}>{i.material_title}</OpenLink>{/* and a link to open it. */}
                        </span> // (end of the piece)
                      ))}{/* End of the materials loop. */}
                    </li> // End of the list item.
                  ))}{/* End of the goals loop. */}
                </ul>{/* End of the list. */}
              </div> // End of the block.
            ))}{/* End of the students loop. */}
          </Card> // End of the card.
        )}{/* End of the suggestions. */}

        <Card title="Find a material">{/* A card for searching: */}
          <form className="mb-5 flex flex-wrap items-end gap-2 text-sm">{/* a search form (sends the choices in the address): */}
            <label className="space-y-1">{/* a label: */}
              <span className="block text-xs text-zinc-500">Subject</span>{/* "Subject", */}
              <select name="subject" defaultValue={subject} className={selectClass}>{/* a drop-down: */}
                <option value="">All</option>{/* all, */}
                {subjects.map((s) => ( // for each subject:
                  <option key={s}>{s}</option> // an option.
                ))}{/* End of the loop. */}
              </select>{/* End of the drop-down. */}
            </label>{/* End of the label. */}
            <label className="space-y-1">{/* A label: */}
              <span className="block text-xs text-zinc-500">Year level</span>{/* "Year level", */}
              <select name="year" defaultValue={year} className={selectClass}>{/* a drop-down: */}
                <option value="">All</option>{/* all, */}
                {YEAR_LEVELS.map((y) => ( // for each year:
                  <option key={y}>{y}</option> // an option.
                ))}{/* End of the loop. */}
              </select>{/* End of the drop-down. */}
            </label>{/* End of the label. */}
            <label className="space-y-1">{/* A label: */}
              <span className="block text-xs text-zinc-500">Kind</span>{/* "Kind", */}
              <select name="kind" defaultValue={kind} className={selectClass}>{/* a drop-down: */}
                <option value="">All</option>{/* all, */}
                {MATERIAL_KINDS.map((k) => ( // for each kind:
                  <option key={k} value={k}>{/* an option: */}
                    {MATERIAL_KIND_NAMES[k]}{/* its name. */}
                  </option> // (end of the option)
                ))}{/* End of the loop. */}
              </select>{/* End of the drop-down. */}
            </label>{/* End of the label. */}
            <label className="space-y-1">{/* A label: */}
              <span className="block text-xs text-zinc-500">Words or skill code</span>{/* "Words or skill code", */}
              <input name="q" defaultValue={pick("q")} className={selectClass} />{/* a text box. */}
            </label>{/* End of the label. */}
            <button className="rounded-full border border-zinc-300 px-4 py-2">Find</button>{/* The "Find" button. */}
          </form>{/* End of the search form. */}

          {shown.length === 0 ? ( // If nothing to show:
            <Empty>{/* a note: */}
              {all.length === 0 // if they have no materials at all,
                ? "No materials for what you teach yet. Check your subjects and year levels under \"What you teach\" in your dashboard." // what to check,
                : "Nothing matches. Try fewer filters."}{/* otherwise to try fewer filters. */}
            </Empty> // End of the note.
          ) : ( // Otherwise:
            <ul className="divide-y divide-zinc-100">{/* a list: */}
              {shown.map((m) => ( // for each material:
                <li key={m.id} className="py-3 text-sm">{/* a list item: */}
                  <div className="flex flex-wrap items-baseline justify-between gap-2">{/* a row that wraps: */}
                    <OpenLink id={m.id}>{m.title}</OpenLink>{/* a link to open it, */}
                    <span className="text-xs text-zinc-500">{/* small grey details: */}
                      {MATERIAL_KIND_NAMES[m.kind] ?? m.kind} · {m.subject} · {yearRange(m.from_level, m.to_level)}{/* its kind, subject and year levels, */}
                      {m.page_count && m.page_count > 1 ? ` · ${m.page_count} pages` : ""}{/* and pages, if more than one. */}
                    </span>{/* End of the details. */}
                  </div>{/* End of the row. */}
                  {m.description && <p className="mt-1 text-zinc-600">{m.description}</p>}{/* The note for tutors, if any. */}
                  {m.material_skills.length > 0 && ( // If it has skills:
                    <p className="mt-1 text-xs text-zinc-500">{/* a small grey line: */}
                      Skills:{" "}{/* "Skills:", */}
                      {m.material_skills // the skills:
                        .map((s) => s.skill && (s.skill.code ? `${s.skill.code} ` : "") + (s.skill.plain_description || s.skill.description)) // each skill's code and plain words,
                        .filter(Boolean) // leaving out blanks,
                        .join("; ")}{/* joined with semicolons. */}
                    </p> // End of the line.
                  )}{/* End of the skills. */}
                </li> // End of the list item.
              ))}{/* End of the loop. */}
            </ul> // End of the list.
          )}{/* End of the choice. */}
        </Card>{/* End of the card. */}
      </Page>{/* End of the page. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of MaterialsPage.
