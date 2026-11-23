// Summary: the Decision steps page (Carla, 22 Nov 2026), from How We Do
// Things v1.0, section 4. Each staff member sees their decision steps
// record (one line per kind of problem: their step, when it moved and a
// note), notes on it, and their own decisions log. Carla (CLG's owner) opens
// anyone's record, moves steps and changes the kinds of problem. Operations
// admins open tutors' records and add notes. See docs/features/decision-steps.md.
//
import Link from "next/link"; // Links between pages.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty } from "@/components/ui"; // Shared page parts: card and "nothing yet" line.
import { getAdminLevel, needsTwoStep, requireViewer } from "@/lib/auth"; // The admin level, the two-step check, and signing in.
import { STEP_NAMES, stepLabel, type RecordLine } from "@/lib/decision-steps"; // The step words and the record line shape.
import { plainDate, plainDateTime } from "@/lib/privacy"; // Dates in words, Adelaide time.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { staffRole } from "@/lib/training"; // Works out which dashboard the page belongs to.
import { KindForm, LogForm, MoveStepForm, NoteForm } from "./forms"; // The page's forms.

// One note, log entry, kind and person as the page reads them.
type Note = { id: string; kind_id: string | null; author_id: string | null; body: string; created_at: string }; // A note.
type LogEntry = { id: string; kind_id: string | null; problem: string; options: string; choice: string; done: boolean; created_at: string }; // A log entry.
type Kind = { id: string; audience: "admin" | "tutor"; title: string; start_step: number; goal_step: number; goal_note: string | null; active: boolean; position: number }; // A kind of problem.
type Person = { account_id: string; full_name: string; roles: string[] }; // Someone whose record they can open.

// Shows the page (tutors and admin staff).
export default async function DecisionsPage({ searchParams }: PageProps<"/decisions">) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard"); // Not a tutor or admin: to their dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login not set up: sends them to set it up.
  const params = await searchParams; // Reads the address settings.
  const role = staffRole(params.as, viewer.roles); // The dashboard to show it in.
  const level = viewer.roles.includes("admin") ? await getAdminLevel() : null; // Their admin level, if any.
  const isOwner = level === "owner"; // Carla, who moves steps.
  const canNote = isOwner || level === "operations"; // Who adds notes (Operations for tutors only; the database checks).
  const supabase = await createClient(); // Connects to the database.
  const people = canNote ? (((await supabase.rpc("decision_record_people")).data ?? []) as Person[]) : []; // The records they can open (Carla and Operations).
  const asked = typeof params.person === "string" ? params.person : ""; // The person chosen in the address, if any.
  const person = people.find((p) => p.account_id === asked); // That person, if they may open them.
  const who = person ? person.account_id : viewer.id; // Whose record is shown: the chosen person, or their own.
  const [{ data: lines }, { data: notes }, { data: log }, { data: kinds }] = await Promise.all([ // Reads four things at once:
    supabase.rpc("decision_record", { p_account: who }), // the record,
    supabase.from("decision_notes").select("id, kind_id, author_id, body, created_at").eq("account_id", who).order("created_at", { ascending: false }).limit(100), // the notes,
    supabase.from("decision_log").select("id, kind_id, problem, options, choice, done, created_at").eq("account_id", who).order("created_at", { ascending: false }).limit(100), // the decisions log,
    isOwner ? supabase.from("decision_kinds").select("id, audience, title, start_step, goal_step, goal_note, active, position").order("audience").order("position") : Promise.resolve({ data: [] }), // and, for Carla, every kind of problem.
  ]); // End of the reads.
  const record = (lines ?? []) as RecordLine[]; // The record's lines.
  const noteList = (notes ?? []) as Note[]; // The notes.
  const logList = (log ?? []) as LogEntry[]; // The log.
  const kindList = (kinds ?? []) as Kind[]; // Every kind (Carla only).
  const titles = new Map(record.map((l) => [l.kind_id, l.title])); // Each kind's words, by id.
  const authorIds = [...new Set(noteList.map((n) => n.author_id).filter((x): x is string => !!x))]; // Who wrote the notes.
  const authors = new Map(((authorIds.length ? (await supabase.from("accounts").select("id, full_name").in("id", authorIds)).data : []) ?? []).map((a) => [a.id as string, a.full_name as string])); // Each writer's name, by id (where they can see it).
  const mine = who === viewer.id; // Whether it is their own record.
  const probation = record.some((l) => l.on_probation); // Whether any line is held at Step 1 by probation.
  const kindsForForms = record.map((l) => ({ id: l.kind_id, title: l.title })); // The kinds in this record, for the forms.
  const as = role === "admin" ? "admin" : "tutor"; // The dashboard in the address.
  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="decisions">{/* the dashboard frame, */}
      <div className="space-y-6">{/* the cards, with space between: */}
        {canNote && ( // Carla and Operations: choose whose record to open.
          <Card title="Open a record" description={isOwner ? "Choose a staff member to see their record, move steps at their check-in, and add notes." : "Choose a tutor to read their record and add notes. Only Carla moves steps."}>{/* the chooser: */}
            {people.length === 0 ? <Empty>No records to open yet.</Empty> : ( // None, or the list:
              <ul className="flex flex-wrap gap-2 text-sm">{/* the names as buttons: */}
                <li><Link className={`rounded-full border px-3 py-1 ${mine ? "border-teal-600 bg-teal-50" : "border-zinc-200"}`} href={`/decisions?as=${as}`}>My record</Link></li>{/* their own, */}
                {people.map((p) => <li key={p.account_id}><Link className={`rounded-full border px-3 py-1 ${p.account_id === who ? "border-teal-600 bg-teal-50" : "border-zinc-200"}`} href={`/decisions?as=${as}&person=${p.account_id}`}>{p.full_name}</Link></li>)}{/* and each person. */}
              </ul> // End of the list.
            )}{/* End of the choice. */}
          </Card> // End of the card.
        )}{/* End of the chooser. */}
        <Card title={mine ? "My decision steps" : `Decision steps: ${person?.full_name ?? ""}`} description="One line for each kind of problem. Your step says how much you need Carla before you act. Carla moves a step up once your choices are consistently the ones she would have made, at your accountability check-in. If something goes wrong, it may move back a step for a while. That is a normal part of learning.">{/* the record: */}
          {probation && <p className="mb-4 rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-900">During probation everything is at Step 1. Your own steps show once probation is passed.</p>}{/* the probation note, */}
          {record.length === 0 ? <Empty>No kinds of problem for this role yet.</Empty> : ( // None, or the lines:
            <ul className="divide-y divide-zinc-100">{record.map((l) => ( // Each line:
              <li key={l.kind_id} className="space-y-2 py-3 first:pt-0">{/* a row: */}
                <p className="font-medium">{l.title}</p>{/* the kind of problem, */}
                <p className="text-sm"><span className="font-semibold">{stepLabel(l.step)}</span>{l.on_probation ? " (probation)" : ""} · goal Step {l.goal_step}{l.goal_note ? ` ${l.goal_note}` : ""}{l.moved_on ? ` · moved ${plainDate(l.moved_on)}` : ` · started at Step ${l.start_step}`}</p>{/* the step, goal and date, */}
                {l.note && <p className="text-sm text-zinc-600">{l.note}</p>}{/* the note, */}
                {isOwner && !mine && ( // Carla, on someone else's record:
                  <details><summary className="cursor-pointer text-xs text-zinc-500 underline">Move this step</summary><div className="mt-3"><MoveStepForm person={who} kind={l.kind_id} step={l.step} /></div></details> // the move form, tucked away.
                )}{/* End of the move part. */}
              </li> // End of the row.
            ))}</ul> // End of the lines.
          )}{/* End of the choice. */}
          <details className="mt-4 text-sm"><summary className="cursor-pointer font-medium underline">What each step means</summary><ol className="mt-2 list-decimal space-y-1 pl-5">{[1, 2, 3, 4, 5].map((n) => <li key={n}><span className="font-semibold">{STEP_NAMES[n].name}.</span> {STEP_NAMES[n].meaning}</li>)}</ol><p className="mt-2 text-zinc-600">Child safety is not part of the steps: any concern goes to Carla the same day. If you are unsure, just ask.</p></details>{/* the step meanings. */}
        </Card>{/* End of the card. */}
        <Card title="Notes on this record" collapsible defaultOpen={noteList.length > 0}>{/* the notes: */}
          <div className="space-y-4">{/* a block: */}
            {canNote && !mine && <NoteForm person={who} kinds={kindsForForms} />}{/* the note form (Carla and Operations, on someone else), */}
            {noteList.length === 0 ? <Empty>No notes yet.</Empty> : <ul className="divide-y divide-zinc-100">{noteList.map((n) => <li key={n.id} className="py-2 text-sm"><p className="text-xs text-zinc-500">{authors.get(n.author_id ?? "") ?? "CLG"} · {plainDateTime(n.created_at)}{n.kind_id && titles.get(n.kind_id) ? ` · ${titles.get(n.kind_id)}` : ""}</p><p className="whitespace-pre-line">{n.body}</p></li>)}</ul>}{/* none, or each note. */}
          </div>{/* End of the block. */}
        </Card>{/* End of the card. */}
        <Card title={mine ? "My decisions log" : "Decisions log"} description={mine ? "At Step 4, record decisions here instead of messaging Carla. Carla can read it at any time." : undefined}>{/* the log: */}
          <div className="space-y-4">{/* a block: */}
            {mine && <details><summary className="cursor-pointer text-sm font-medium underline">Record a decision</summary><div className="mt-3"><LogForm kinds={kindsForForms} /></div></details>}{/* the log form (their own), */}
            {logList.length === 0 ? <Empty>No decisions recorded yet.</Empty> : <ul className="divide-y divide-zinc-100">{logList.map((e) => <li key={e.id} className="space-y-1 py-3 text-sm"><p className="text-xs text-zinc-500">{plainDateTime(e.created_at)}{e.kind_id && titles.get(e.kind_id) ? ` · ${titles.get(e.kind_id)}` : ""}{e.done ? "" : " · Not done yet"}</p><p><span className="font-semibold">Problem: </span>{e.problem}</p><p><span className="font-semibold">Options: </span>{e.options}</p><p><span className="font-semibold">Chosen, and why: </span>{e.choice}</p></li>)}</ul>}{/* none, or each entry. */}
          </div>{/* End of the block. */}
        </Card>{/* End of the card. */}
        {isOwner && ( // Carla: the kinds of problem.
          <Card title="Kinds of problem" description="The lines on everyone's record, from the starting points in How We Do Things. Changing the starting step only affects people whose step has not been moved yet." collapsible defaultOpen={false}>{/* the kinds: */}
            <div className="space-y-4">{/* a block: */}
              <ul className="divide-y divide-zinc-100">{kindList.map((k) => ( // Each kind:
                <li key={k.id} className="py-2 text-sm"><details><summary className="cursor-pointer">{k.audience === "admin" ? "Admin" : "Tutors"}: {k.title} (starts Step {k.start_step}, goal Step {k.goal_step}){k.active ? "" : " · Not in use"}</summary><div className="mt-3"><KindForm kind={k} /></div></details></li> // its line, opening its form,
              ))}</ul>{/* End of the kinds. */}
              <details><summary className="cursor-pointer text-sm font-medium underline">Add a kind of problem</summary><div className="mt-3"><KindForm /></div></details>{/* and adding a new one. */}
            </div>{/* End of the block. */}
          </Card> // End of the card.
        )}{/* End of the kinds part. */}
      </div>{/* End of the cards. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of DecisionsPage.
