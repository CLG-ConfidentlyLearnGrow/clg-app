// Summary: the admin materials page: add materials, the library list, and who opened what.
//
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, Table, TextLink } from "@/components/ui"; // The card, "nothing yet" note, table and link style.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is an admin.
import { MATERIAL_KIND_NAMES, type MaterialKind, yearRange } from "@/lib/materials"; // Material kind names, the kind type, and year ranges in words.
import { LOCAL_TIME_ZONE } from "@/lib/scheduling"; // CLG's local time zone (Adelaide).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { UploadMaterialsForm } from "./upload-form"; // The upload form.

// Materials library (admin): add materials, tag and publish them, and see
// who has opened what.

const SECTIONS = [ // The page's sections:
  { id: "add", label: "Add materials" }, // add materials,
  { id: "library", label: "Library" }, // the library,
  { id: "opens", label: "Who opened what" }, // who opened what.
] as const; // End of the list (fixed).

const STATUS_FILTERS = [ // The library's "show" choices:
  { id: "all", label: "All" }, // all,
  { id: "needs", label: "Needs tagging" }, // needs tagging,
  { id: "draft", label: "Drafts" }, // drafts,
  { id: "published", label: "Published" }, // published,
  { id: "retired", label: "Retired" }, // retired.
] as const; // End of the list (fixed).

// Busy use worth a look: this many different materials in 7 days.
const BUSY_WEEK = 40; // The number.

// A material as the library list needs it.
type Row = {
  id: string; // its id,
  title: string; // title,
  kind: MaterialKind; // kind,
  subject: string; // subject,
  from_level: string; // lowest year level,
  to_level: string; // highest year level,
  status: string; // status,
  no_skills_reason: string | null; // why no skills fit (if given),
  material_skills: { count: number }[]; // and how many skills are tagged.
}; // End of the shape.

const when = (iso: string) => // Writes a time like "3 Nov, 4:30 pm":
  new Intl.DateTimeFormat("en-AU", { // (the format:)
    timeZone: LOCAL_TIME_ZONE, // in local time,
    day: "numeric", // day number,
    month: "short", // short month,
    hour: "numeric", // hour,
    minute: "2-digit", // minutes with two digits.
  }).format(new Date(iso)); // (applied to the time)

// Shows the admin materials page.
export default async function AdminMaterialsPage({ searchParams }: PageProps<"/admin/materials">) {
  const viewer = await requireAdmin(); // Makes sure the person is an admin, and gets who they are.
  const params = await searchParams; // Reads the address settings.
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "library"; // The section asked for (library by default).
  const filter = STATUS_FILTERS.find((f) => f.id === params.show)?.id ?? "all"; // The "show" choice (all by default).
  const q = typeof params.q === "string" ? params.q.trim().slice(0, 100) : ""; // The search words (up to 100 characters).
  const supabase = await createClient(); // Connects to the database.

  const [list, summary, recent] = await Promise.all([ // Reads three things at once:
    supabase // the materials:
      .from("materials") // (from the materials table)
      .select("id, title, kind, subject, from_level, to_level, status, no_skills_reason, material_skills(count)") // with their details and skill count,
      .order("subject") // by subject,
      .order("title"), // then title;
    supabase.rpc("material_open_summary", { p_days: 7 }), // who opened most in the last 7 days;
    supabase // and the latest opens:
      .from("material_opens") // (from the opens table)
      .select("id, opened_at, account:accounts(full_name), material:materials(id, title)") // with who and which material,
      .order("opened_at", { ascending: false }) // newest first,
      .limit(50), // at most 50.
  ]); // End of the reads.
  const all = (list.data ?? []) as unknown as Row[]; // All the materials.
  const untagged = (r: Row) => (r.material_skills[0]?.count ?? 0) === 0 && !r.no_skills_reason; // True if a material has no skills and no reason.
  const needs = all.filter((r) => r.status === "draft" || untagged(r)); // Materials that are drafts or untagged.
  const shown = all // The materials to show:
    .filter((r) => // matching the "show" choice:
      filter === "all" ? true : filter === "needs" ? r.status === "draft" || untagged(r) : r.status === filter, // (all, needs tagging, or that status)
    ) // (end of that filter)
    .filter((r) => !q || `${r.title} ${r.subject}`.toLowerCase().includes(q.toLowerCase())); // and the search words.
  const busy = ((summary.data ?? []) as { account_id: string; full_name: string; opens: number; different_materials: number; last_opened: string }[]); // Who opened most.
  const recentRows = (recent.data ?? []) as unknown as { // The latest opens:
    id: number; // each with its id,
    opened_at: string; // when,
    account: { full_name: string } | null; // who,
    material: { id: string; title: string } | null; // and which material.
  }[]; // (end of the shape)

  return ( // Shows:
    <>{/* (a group:) */}
      {/* The dashboard tabs and admin menu, with this page's own sections shown under its tab: */}
      <DashboardFrame // the dashboard frame:
        role="admin" // the admin dashboard,
        roles={viewer.roles} // the person's roles (for the tabs and numbers),
        current="materials" // this page's tab open,
        sub={section} // on the open section,
        items={SECTIONS.map((s) => ({ ...s, href: `/admin/materials?section=${s.id}`, count: s.id === "library" ? needs.length || undefined : undefined }))} // with this page's sections (and their numbers) under the tab.
      >{/* (end of the frame's settings) */}
        <p className="text-sm">{/* A line: */}
          <TextLink href="/materials">See the library as tutors do</TextLink>{/* a link to the tutors' view. */}
        </p>{/* End of the line. */}

        {section === "add" && ( // The add section:
          <Card // a card:
            title="Add materials" // titled "Add materials",
            description="Upload one file or many. They're saved as drafts; then tag each with its curriculum skills and publish it. Tutors see a material only once it's published, and only for subjects and year levels they teach." // with what happens next.
          >{/* (end of the card's settings) */}
            <UploadMaterialsForm />{/* The upload form. */}
          </Card> // End of the card.
        )}{/* End of the add section. */}

        {section === "library" && ( // The library section:
          <Card // a card:
            title="Library" // titled "Library",
            description={`${all.length} material${all.length === 1 ? "" : "s"}. ${needs.length} need tagging or publishing.`} // with how many there are and how many need work.
          >{/* (end of the card's settings) */}
            <form className="mb-4 flex flex-wrap items-end gap-2 text-sm" action="/admin/materials">{/* A search form: */}
              <input type="hidden" name="section" value="library" />{/* stays on the library section, */}
              <label className="space-y-1">{/* a label: */}
                <span className="block text-xs text-zinc-500">Show</span>{/* "Show", */}
                <select name="show" defaultValue={filter} className="rounded-lg border border-zinc-300 bg-white px-3 py-2">{/* a drop-down: */}
                  {STATUS_FILTERS.map((f) => ( // for each choice:
                    <option key={f.id} value={f.id}>{/* an option: */}
                      {f.label}{/* its words. */}
                    </option> // (end of the option)
                  ))}{/* End of the loop. */}
                </select>{/* End of the drop-down. */}
              </label>{/* End of the label. */}
              <label className="space-y-1">{/* A label: */}
                <span className="block text-xs text-zinc-500">Search</span>{/* "Search", */}
                <input name="q" defaultValue={q} className="rounded-lg border border-zinc-300 bg-white px-3 py-2" />{/* a text box. */}
              </label>{/* End of the label. */}
              <button className="rounded-full border border-zinc-300 px-4 py-2">Go</button>{/* The "Go" button. */}
            </form>{/* End of the search form. */}
            {shown.length === 0 ? ( // If nothing to show:
              <Empty>{/* a note: */}
                {all.length === 0 ? ( // if there are no materials at all:
                  <>{/* (a group:) */}
                    Nothing yet. <TextLink href="/admin/materials?section=add">Add your first materials</TextLink>.{/* a link to add the first ones, */}
                  </> // (end of the group)
                ) : ( // otherwise:
                  "Nothing matches." // "Nothing matches."
                )}{/* End of the choice. */}
              </Empty> // End of the note.
            ) : ( // Otherwise:
              <Table headings={["Title", "Subject", "Years", "Skills", "Status"]}>{/* a table with these headings: */}
                {shown.map((r) => { // for each material:
                  const count = r.material_skills[0]?.count ?? 0; // how many skills it has.
                  return ( // Shows:
                    <tr key={r.id}>{/* a row: */}
                      <td>{/* a cell: */}
                        <TextLink href={`/admin/materials/${r.id}`}>{r.title}</TextLink>{/* a link to its page, */}
                        <span className="block text-xs text-zinc-500">{MATERIAL_KIND_NAMES[r.kind] ?? r.kind}</span>{/* and its kind below. */}
                      </td>{/* End of the cell. */}
                      <td>{r.subject}</td>{/* The subject, */}
                      <td>{yearRange(r.from_level, r.to_level)}</td>{/* the year levels, */}
                      <td>{count ? count : r.no_skills_reason ? "None fit" : <span className="text-red-700">Not tagged</span>}</td>{/* the skill count, "None fit", or "Not tagged" in red, */}
                      <td className="capitalize">{r.status}</td>{/* and the status. */}
                    </tr> // End of the row.
                  ); // End of what's shown for this material.
                })}{/* End of the loop. */}
              </Table> // End of the table.
            )}{/* End of the choice. */}
          </Card> // End of the card.
        )}{/* End of the library section. */}

        {section === "opens" && ( // The opens section:
          <>{/* (a group:) */}
            <Card // a card:
              title="Last 7 days, by person" // titled "Last 7 days, by person",
              description={`Tutors can open up to 30 different materials a day. Anyone opening ${BUSY_WEEK} or more different materials in a week is marked, in case it's worth a chat.`} // with the daily limit and the busy mark.
            >{/* (end of the card's settings) */}
              {busy.length === 0 ? ( // If nobody opened anything:
                <Empty>No one has opened a material this week.</Empty> // says so.
              ) : ( // Otherwise:
                <Table headings={["Person", "Different materials", "Opens", "Last opened"]}>{/* a table with these headings: */}
                  {busy.map((b) => ( // for each person:
                    <tr key={b.account_id}>{/* a row: */}
                      <td>{/* a cell: */}
                        {b.full_name}{/* their name, */}
                        {b.different_materials >= BUSY_WEEK && ( // and a "Busy week" mark if they opened many:
                          <span className="ml-2 rounded-full bg-amber-100 px-2 text-xs text-amber-900">Busy week</span> // (the mark)
                        )}{/* (end of the mark) */}
                      </td>{/* End of the cell. */}
                      <td>{b.different_materials}</td>{/* How many different materials, */}
                      <td>{b.opens}</td>{/* how many opens, */}
                      <td>{when(b.last_opened)}</td>{/* and when they last opened one. */}
                    </tr> // End of the row.
                  ))}{/* End of the loop. */}
                </Table> // End of the table.
              )}{/* End of the choice. */}
            </Card>{/* End of the card. */}
            <Card title="Latest opens" description="The last 50. Records are kept for 2 years.">{/* A card of the latest opens: */}
              {recentRows.length === 0 ? ( // if none:
                <Empty>None yet.</Empty> // says so.
              ) : ( // Otherwise:
                <Table headings={["When", "Person", "Material"]}>{/* a table with these headings: */}
                  {recentRows.map((o) => ( // for each open:
                    <tr key={o.id}>{/* a row: */}
                      <td>{when(o.opened_at)}</td>{/* when, */}
                      <td>{o.account?.full_name}</td>{/* who, */}
                      <td>{/* a cell: */}
                        {o.material && <TextLink href={`/admin/materials/${o.material.id}`}>{o.material.title}</TextLink>}{/* a link to the material. */}
                      </td>{/* End of the cell. */}
                    </tr> // End of the row.
                  ))}{/* End of the loop. */}
                </Table> // End of the table.
              )}{/* End of the choice. */}
            </Card>{/* End of the card. */}
          </> // (end of the group)
        )}{/* End of the opens section. */}
      </DashboardFrame>{/* End of the dashboard frame. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of AdminMaterialsPage.
