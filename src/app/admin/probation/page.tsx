// Summary: the Staff probation page, for the owner only (Carla, 20 Nov 2026).
// Tutors finish probation at 3 months or 30 sessions, and admin staff at
// 3 months or 40 hours (one full-time work week), whichever comes first
// (Carla changed 30 hours to 40 hours on 22 Nov 2026). This page shows:
//   * probations due for review now, with a form to mark each passed,
//     extended (with a new review date) or ended;
//   * everyone still on probation, with their progress and due date;
//   * a form to set up a probation for someone the app did not set up by
//     itself (the daily run sets up new staff from the start date on their
//     pay details);
//   * finished probations.
// The owner gets an app notice when a probation becomes due. Only the owner
// can read probation records; the database enforces that.
// See docs/features/staff-probation.md.
//
import { decideProbation, setProbationStart, startProbation } from "@/app/actions/probation"; // The server actions for this page.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, Field, Select, Table, TextArea } from "@/components/ui"; // Shared page parts.
import { requireAdminLevel } from "@/lib/auth"; // Makes sure the person is an admin at the right level.
import { shortDate } from "@/lib/scheduling"; // Shows a date in a short, friendly way.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// One probation, as the database gives it.
type Probation = { // Its fields:
  id: string; // its id,
  account_id: string; // the staff member,
  full_name: string; // their name,
  kind: "tutor" | "admin"; // which role,
  started_on: string; // the start date,
  months: number; // how many months it lasts,
  target: number; // how many sessions or hours end it early,
  done: number; // sessions or hours so far,
  time_ends_on: string; // the day the months are up,
  reached_on: string | null; // the day the target was reached (if it has been),
  extended_to: string | null; // an extended review date (if any),
  due_on: string; // the day it is due for review,
  state: "on_track" | "due_soon" | "due" | "passed" | "ended"; // where it is up to,
  note: string | null; // the owner's private note,
  decided_at: string | null; // when it was marked passed or ended.
}; // End of the shape.

// One staff member, from the staff directory (for the set-up form).
type Staff = { account_id: string; full_name: string; is_tutor: boolean; is_admin: boolean; admin_level: string | null }; // Their id, name, roles and admin level.

// The words for each state.
const STATE_WORDS: Record<Probation["state"], string> = { // state -> words:
  on_track: "On probation", // still going,
  due_soon: "Due in the next 2 weeks", // coming up,
  due: "Due for review", // due now,
  passed: "Passed", // passed,
  ended: "Ended", // ended.
}; // End of the words.

// "12 of 30 sessions" or "12.5 of 40 hours".
function progress(p: Probation): string { // Takes the probation.
  const unit = p.kind === "tutor" ? "sessions" : "hours"; // Sessions for tutors, hours for admin staff.
  return `${Number(p.done)} of ${p.target} ${unit}`; // The count and the target.
} // End of progress.

// Why it is due (or when it will be), in words.
function dueWhy(p: Probation): string { // Takes the probation.
  if (p.extended_to) return `Extended to ${shortDate(p.extended_to)}`; // An extension.
  if (p.reached_on && p.reached_on <= p.time_ends_on) return `Reached ${p.target} ${p.kind === "tutor" ? "sessions" : "hours"} on ${shortDate(p.reached_on)}`; // The target came first.
  return `${p.months} months on ${shortDate(p.time_ends_on)}`; // The months come first.
} // End of dueWhy.

// Shows the page (owner only).
export default async function ProbationPage() { // The page itself.
  const viewer = await requireAdminLevel(["owner"]); // Must be the owner, with two-step sign-in.
  const supabase = await createClient(); // Connects to the database.
  const [listRes, staffRes] = await Promise.all([ // Reads two things at once:
    supabase.rpc("staff_probation_list"), // every probation,
    supabase.rpc("staff_directory"), // and the staff list (for the set-up form).
  ]); // End of the reads.
  const all = (listRes.data ?? []) as Probation[]; // The probations.
  const staff = ((staffRes.data ?? []) as Staff[]).filter((s) => s.is_tutor || (s.is_admin && s.admin_level !== "owner")); // Tutors and admin staff (not the owner).
  const due = all.filter((p) => p.state === "due"); // Due for review now.
  const open = all.filter((p) => p.state === "on_track" || p.state === "due_soon"); // Still on probation, not due yet.
  const finished = all.filter((p) => p.state === "passed" || p.state === "ended"); // Finished.

  // The review form for one probation.
  const reviewForm = (p: Probation) => ( // Takes the probation:
    <ActionForm action={decideProbation} submitLabel="Save review">{/* the form: */}
      <input type="hidden" name="id" value={p.id} />{/* (which probation) */}
      <Select label="Outcome" name="outcome" defaultValue="passed">{/* the outcome: */}
        <option value="passed">Passed</option>{/* passed, */}
        <option value="extended">Extend probation</option>{/* extended, */}
        <option value="ended">Ended (not continuing)</option>{/* or ended. */}
      </Select>{/* End of the outcome. */}
      <Field label="New review date (only if extending)" name="extend_to" type="date" />{/* the new date for an extension, */}
      <TextArea label="Private note (only the owner can see this)" name="note" defaultValue={p.note ?? ""} maxLength={1000} rows={2} />{/* and the note. */}
    </ActionForm> // End of the form.
  ); // End of reviewForm.

  // The start date correction form for one probation.
  const startForm = (p: Probation) => ( // Takes the probation:
    <details className="mt-2">{/* an open-and-close box: */}
      <summary className="cursor-pointer text-sm text-teal-800">Change the start date</summary>{/* its heading, */}
      <div className="mt-2">{/* the form: */}
        <ActionForm action={setProbationStart} submitLabel="Save start date">{/* saving the date: */}
          <input type="hidden" name="id" value={p.id} />{/* (which probation) */}
          <Field label="Start date" name="started_on" type="date" defaultValue={p.started_on} required />{/* the date box. */}
        </ActionForm>{/* End of the form. */}
      </div>{/* End of the form area. */}
    </details> // End of the box.
  ); // End of startForm.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="probation">{/* the dashboard frame, */}
      <div className="space-y-6">{/* the page's parts, with space between: */}
        <Card title="Staff probation" description="Tutors finish probation at 3 months or 30 completed sessions, and admin staff at 3 months or 40 approved hours (one full-time work week), whichever comes first. You get an app notice when someone is due for review.">{/* an explanation card: */}
          <p className="text-sm">The app sets up a probation by itself for new tutors and admin staff, from the start date on their pay details. Someone who is both a tutor and an admin has a probation for each role.</p>{/* how records are set up, */}
          <p className="mt-2 text-sm">Only you (the owner) can see this page.</p>{/* and who sees it. */}
        </Card>{/* End of the explanation. */}

        <Card title={`Due for review (${due.length})`} description="Talk with the staff member, then record the outcome.">{/* the due list: */}
          {due.length === 0 ? <Empty>Nobody is due for a probation review.</Empty> : ( // none, or:
            <ul className="space-y-3">{/* the list: */}
              {due.map((p) => ( // each one:
                <li key={p.id} className="rounded-xl border border-zinc-200 p-3">{/* a bordered box: */}
                  <p className="text-sm"><strong>{p.full_name}</strong><span className="text-zinc-500"> · {p.kind === "tutor" ? "Tutor" : "Admin"} · started {shortDate(p.started_on)}</span></p>{/* who, the role and the start date, */}
                  <p className="mt-1 text-sm">{dueWhy(p)} · {progress(p)}</p>{/* why it is due and the progress, */}
                  <div className="mt-2">{reviewForm(p)}</div>{/* the review form, */}
                  {startForm(p)}{/* and the start date correction. */}
                </li> // End of the box.
              ))}{/* End of the list items. */}
            </ul> // End of the list.
          )}{/* End of the choice. */}
        </Card>{/* End of the due list. */}

        <Card title={`On probation (${open.length})`} description="Everyone still on probation, soonest due first.">{/* the open list: */}
          {open.length === 0 ? <Empty>Nobody else is on probation.</Empty> : ( // none, or:
            <Table headings={["Name", "Role", "Started", "Progress", "Due", "Where it is up to"]}>{/* a table: */}
              {open.map((p) => ( // each one:
                <tr key={p.id}>{/* a row: */}
                  <td>{p.full_name}{startForm(p)}</td>{/* the name, with the start date correction, */}
                  <td>{p.kind === "tutor" ? "Tutor" : "Admin"}</td>{/* the role, */}
                  <td>{shortDate(p.started_on)}</td>{/* the start date, */}
                  <td>{progress(p)}</td>{/* the progress, */}
                  <td>{shortDate(p.due_on)}{p.extended_to ? " (extended)" : ""}</td>{/* the due date, */}
                  <td>{STATE_WORDS[p.state]}</td>{/* and where it is up to. */}
                </tr> // End of the row.
              ))}{/* End of the rows. */}
            </Table> // End of the table.
          )}{/* End of the choice. */}
        </Card>{/* End of the open list. */}

        <Card title="Set up a probation" description="For someone the app did not set up by itself, for example a staff member with no start date on their pay details." collapsible defaultOpen={false}>{/* the set-up form: */}
          <ActionForm action={startProbation} submitLabel="Set up probation">{/* the form: */}
            <Select label="Staff member" name="person" defaultValue="" required>{/* who: */}
              <option value="" disabled>Choose a staff member</option>{/* a prompt, */}
              {staff.map((s) => <option key={s.account_id} value={s.account_id}>{s.full_name}</option>)}{/* then each staff member. */}
            </Select>{/* End of who. */}
            <Select label="Role" name="kind" defaultValue="tutor">{/* which role: */}
              <option value="tutor">Tutor (3 months or 30 sessions)</option>{/* tutor, */}
              <option value="admin">Admin (3 months or 40 hours)</option>{/* or admin. */}
            </Select>{/* End of the role. */}
            <Field label="Start date" name="started_on" type="date" hint="Leave blank to use the start date on their pay details, or today if there is none." />{/* the start date, */}
            <TextArea label="Private note (optional)" name="note" maxLength={1000} rows={2} />{/* and a note. */}
          </ActionForm>{/* End of the form. */}
        </Card>{/* End of the set-up form. */}

        <Card title={`Finished (${finished.length})`} description="Probations marked passed or ended." collapsible defaultOpen={false}>{/* the finished list: */}
          {finished.length === 0 ? <Empty>No finished probations yet.</Empty> : ( // none, or:
            <Table headings={["Name", "Role", "Started", "Outcome", "Decided", "Note"]}>{/* a table: */}
              {finished.map((p) => ( // each one:
                <tr key={p.id}>{/* a row: */}
                  <td>{p.full_name}</td>{/* the name, */}
                  <td>{p.kind === "tutor" ? "Tutor" : "Admin"}</td>{/* the role, */}
                  <td>{shortDate(p.started_on)}</td>{/* the start date, */}
                  <td>{STATE_WORDS[p.state]}</td>{/* the outcome, */}
                  <td>{p.decided_at ? shortDate(p.decided_at) : ""}</td>{/* when it was decided, */}
                  <td className="whitespace-pre-wrap">{p.note ?? ""}</td>{/* and the note. */}
                </tr> // End of the row.
              ))}{/* End of the rows. */}
            </Table> // End of the table.
          )}{/* End of the choice. */}
        </Card>{/* End of the finished list. */}
      </div>{/* End of the page's parts. */}
    </DashboardFrame> // End of the frame.
  ); // End of what is shown.
} // End of ProbationPage.
