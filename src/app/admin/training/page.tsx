// Summary: the training admin page (owner and operations): the list of
// modules and a form to add one, everyone's progress and certification,
// the handbook pages, and training settings.
//
import Link from "next/link"; // Links between pages.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, Table, TextLink } from "@/components/ui"; // The card, "nothing yet" note, table and link style.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is a full admin.
import { plainDate } from "@/lib/billing/money"; // Dates in words.
import { adelaideToday } from "@/lib/billing/run"; // Today's date in Adelaide.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { AUDIENCE_NAMES, CERT_NAMES, STAGE_NAMES, STATE_NAMES, STATE_STYLES, hrs, timeText, type Audience, type CertState, type Stage, type TrainingState } from "@/lib/training"; // Training words, colours and shapes.
import { HandbookForm, NewModuleForm, SettingsForm } from "./forms"; // The admin forms.

// The page's sections.
const SECTIONS = [ // Each section's id and words:
  { id: "modules", label: "Modules" }, // the modules,
  { id: "progress", label: "Progress" }, // everyone's progress,
  { id: "handbook", label: "Handbook" }, // the handbook,
  { id: "settings", label: "Settings" }, // the settings.
] as const; // End of the list (fixed).

// One row of the progress table from the database.
type ProgressRow = { account_id: string; full_name: string; module_id: string; module_title: string; state: TrainingState; due_on: string | null; completed_on: string | null; expires_on: string | null }; // a person, a module, and where they're up to.
// One person's certification from the database.
type PersonRow = { account_id: string; full_name: string; is_tutor: boolean; is_admin: boolean; cert_state: CertState; certified_since: string | null; quarter_minutes: number; last_quarter_minutes: number; target_minutes: number; matching_held: boolean }; // a person and their certification.

// Shows the training admin page.
export default async function AdminTrainingPage({ searchParams }: PageProps<"/admin/training">) { // Reads the address's settings.
  const viewer = await requireAdmin(); // Only owner and operations admins.
  const params = await searchParams; // The address's settings.
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "modules"; // The section asked for (modules by default).
  const supabase = await createClient(); // Connects to the database.
  const [mods, progress, people, pages, settings, attempts] = await Promise.all([ // Reads six things at once:
    supabase.from("training_modules").select("id, title, audience, stage, required, holds_matching, minutes, status, position, version, training_questions(count), training_lessons(count)").order("position").order("title"), // the modules (with lesson and question counts),
    supabase.rpc("training_progress"), // everyone's progress on compulsory modules,
    supabase.rpc("training_people"), // everyone's certification,
    supabase.from("handbook_pages").select("id, title, urgent, audience, status, position, updated_at").order("urgent", { ascending: false }).order("position").order("title"), // the handbook pages,
    supabase.from("training_settings").select("grace_days, quarter_minutes, video_max_mb").eq("id", true).maybeSingle(), // the settings,
    supabase.from("training_attempts").select("module_id, score, total").gte("created_at", new Date(Date.parse(`${adelaideToday()}T00:00:00Z`) - 90 * 86400000).toISOString()), // and quiz tries in the last 90 days (86,400,000 ms is one day).
  ]); // End of the reads.
  const modules = (mods.data ?? []) as unknown as { id: string; title: string; audience: Audience; stage: Stage; required: boolean; holds_matching: boolean; minutes: number; status: string; position: number; version: number; training_questions: { count: number }[]; training_lessons: { count: number }[] }[]; // The modules.
  const rows = (progress.data ?? []) as ProgressRow[]; // The progress rows.
  const persons = (people.data ?? []) as PersonRow[]; // The people.
  const overdue = rows.filter((r) => r.state === "overdue"); // Overdue rows.
  const tries = (attempts.data ?? []) as { module_id: string; score: number; total: number }[]; // Quiz tries.
  const firstTryRate = (id: string) => { // How often a module's quiz is passed first time (roughly):
    const t = tries.filter((a) => a.module_id === id); // its tries,
    if (t.length === 0) return null; // none: nothing to show,
    return Math.round((t.filter((a) => a.score === a.total).length / t.length) * 100); // otherwise the share of tries with everything right.
  }; // End of firstTryRate.
  const s = settings.data ?? { grace_days: 28, quarter_minutes: 180, video_max_mb: 500 }; // The settings (or the starting values).

  return ( // Shows:
    <DashboardFrame // the dashboard frame:
      role="admin" // the admin dashboard,
      roles={viewer.roles} // the person's roles,
      current="training-admin" // this page's tab open,
      sub={section} // on the open section,
      items={SECTIONS.map((x) => ({ ...x, href: `/admin/training?section=${x.id}`, count: x.id === "progress" ? overdue.length || undefined : undefined }))} // with the sections under the tab (overdue counted).
    >{/* (end of the frame's settings) */}
      {section === "modules" && ( // The modules section:
        <>{/* (a group:) */}
          <Card title="Training modules" description="Each module has lessons and a quiz (100% needed, unlimited tries). Drafts are only seen by admins. Retire a published module instead of deleting it, so its records stay.">{/* the list card: */}
            {modules.length === 0 ? <Empty>No modules yet. Add the first one below.</Empty> : ( // none: says so; otherwise:
              <Table headings={["Module", "For", "Time", "Lessons / questions", "Passed first try", "Status"]}>{/* a table: */}
                {modules.map((m) => { // each module:
                  const rate = firstTryRate(m.id); // its first-try pass rate,
                  return ( // a row:
                    <tr key={m.id}>{/* (the row) */}
                      <td><TextLink href={`/admin/training/${m.id}`}>{m.title}</TextLink><span className="block text-xs text-zinc-500">{STAGE_NAMES[m.stage]}{m.required ? " · Compulsory" : ""}{m.holds_matching ? " · Before new students" : ""}{m.version > 1 ? ` · Version ${m.version}` : ""}</span></td>{/* the name (linking to edit it) and its details, */}
                      <td>{AUDIENCE_NAMES[m.audience]}</td>{/* who it's for, */}
                      <td>{timeText(m.minutes)}</td>{/* its time, */}
                      <td>{m.training_lessons[0]?.count ?? 0} / {m.training_questions[0]?.count ?? 0}</td>{/* how many lessons and questions, */}
                      <td>{rate === null ? "-" : `${rate}%`}</td>{/* how often the quiz is passed first time (low means a lesson may need rewriting), */}
                      <td className="capitalize">{m.status}</td>{/* and its status. */}
                    </tr> // End of the row.
                  ); // End of what's shown.
                })}{/* End of the modules. */}
              </Table> // End of the table.
            )}{/* End of the choice. */}
          </Card>{/* End of the list card. */}
          <Card title="Add a module" description="It starts as a draft. Add lessons and quiz questions, then publish it." collapsible defaultOpen={modules.length === 0}>{/* the add card: */}
            <NewModuleForm />{/* the form. */}
          </Card>{/* End of the add card. */}
        </> // End of the group.
      )}{/* End of the modules section. */}

      {section === "progress" && ( // The progress section:
        <>{/* (a group:) */}
          <Card title="Certification and holds" description={`CLG certified means all compulsory modules are done, plus ${hrs(s.quarter_minutes)} of training each quarter after that. "New matches held" means a safety module is overdue, so the tutor can't take new students (their current students stay).`}>{/* the people card: */}
            {persons.length === 0 ? <Empty>No tutors or admin staff yet.</Empty> : ( // none: says so; otherwise:
              <Table headings={["Name", "Certification", "This quarter", "Last quarter", "New matches"]}>{/* a table: */}
                {persons.map((p) => ( // each person:
                  <tr key={p.account_id}>{/* a row: */}
                    <td>{p.full_name}<span className="block text-xs text-zinc-500">{[p.is_tutor && "Tutor", p.is_admin && "Admin"].filter(Boolean).join(", ")}</span></td>{/* their name and roles, */}
                    <td>{CERT_NAMES[p.cert_state]}{p.certified_since ? <span className="block text-xs text-zinc-500">since {plainDate(p.certified_since)}</span> : null}</td>{/* their certification, */}
                    <td>{hrs(p.quarter_minutes)} of {hrs(p.target_minutes)}</td>{/* this quarter's hours, */}
                    <td>{hrs(p.last_quarter_minutes)}</td>{/* last quarter's hours, */}
                    <td>{p.matching_held ? <span className="font-semibold text-red-800">Held</span> : p.is_tutor ? "OK" : "-"}</td>{/* whether new matches are held. */}
                  </tr> // End of the row.
                ))}{/* End of the people. */}
              </Table> // End of the table.
            )}{/* End of the choice. */}
          </Card>{/* End of the people card. */}
          <Card title="Compulsory modules" description="Everyone's progress. Reminders go out automatically before things are due, and you're told about anything overdue.">{/* the progress card: */}
            {rows.length === 0 ? <Empty>No compulsory modules are published yet.</Empty> : ( // none: says so; otherwise:
              <Table headings={["Name", "Module", "Status", "Date"]}>{/* a table: */}
                {rows.map((r) => ( // each person and module:
                  <tr key={`${r.account_id}-${r.module_id}`}>{/* a row: */}
                    <td>{r.full_name}</td>{/* the person, */}
                    <td>{r.module_title}</td>{/* the module, */}
                    <td><span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${STATE_STYLES[r.state]}`}>{STATE_NAMES[r.state]}</span></td>{/* where they're up to, */}
                    <td className="text-xs">{r.state === "done" || r.state === "renew_soon" ? `Done ${plainDate(r.completed_on)}${r.expires_on ? `, redo by ${plainDate(r.expires_on)}` : ""}` : r.due_on ? `Due ${plainDate(r.due_on)}` : "-"}</td>{/* and the relevant date. */}
                  </tr> // End of the row.
                ))}{/* End of the rows. */}
              </Table> // End of the table.
            )}{/* End of the choice. */}
          </Card>{/* End of the progress card. */}
        </> // End of the group.
      )}{/* End of the progress section. */}

      {section === "handbook" && ( // The handbook section:
        <>{/* (a group:) */}
          <Card title="Handbook pages" description="The go-to guide for tutors and staff. Pin the 'Something's happened' page so it shows at the top in red.">{/* the list card: */}
            {(pages.data ?? []).length === 0 ? <Empty>No pages yet.</Empty> : ( // none: says so; otherwise:
              <Table headings={["Page", "For", "Status", "Updated"]}>{/* a table: */}
                {(pages.data ?? []).map((p) => ( // each page:
                  <tr key={p.id}>{/* a row: */}
                    <td><Link href={`/admin/training/handbook/${p.id}`} className={`underline underline-offset-4 ${p.urgent ? "font-semibold text-red-800" : "text-teal-700"}`}>{p.title}</Link></td>{/* the heading (linking to edit it), */}
                    <td>{AUDIENCE_NAMES[p.audience as Audience]}</td>{/* who it's for, */}
                    <td className="capitalize">{p.status}</td>{/* its status, */}
                    <td className="text-xs">{plainDate(String(p.updated_at).slice(0, 10))}</td>{/* and when it was updated. */}
                  </tr> // End of the row.
                ))}{/* End of the pages. */}
              </Table> // End of the table.
            )}{/* End of the choice. */}
          </Card>{/* End of the list card. */}
          <Card title="Add a page" collapsible defaultOpen={(pages.data ?? []).length === 0}>{/* the add card: */}
            <HandbookForm />{/* the form. */}
          </Card>{/* End of the add card. */}
        </> // End of the group.
      )}{/* End of the handbook section. */}

      {section === "settings" && ( // The settings section:
        <Card title="Training settings">{/* the settings card: */}
          <SettingsForm graceDays={s.grace_days} quarterMinutes={s.quarter_minutes} videoMaxMb={s.video_max_mb} />{/* the form. */}
        </Card> // End of the card.
      )}{/* End of the settings section. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of AdminTrainingPage.
