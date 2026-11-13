// Summary: "Concerns sent to you", for the Child Safety Officer and the
// deputy. Each person sees only the concerns sent to them (the database
// enforces this, and needs two-step sign-in). For each concern: the details,
// the follow-up notes, a box to add a note, where it's up to, and a way to
// pass it to the other contact. Notes can't be edited or deleted.
//
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { addConcernNote, passOnConcern, setConcernStatus } from "@/app/actions/child-safety"; // The server actions for notes, stages and passing on.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Empty, Page, Select, TextArea } from "@/components/ui"; // The card, "nothing yet" note, page frame, drop-down and multi-line box.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { CONTACT_ROLE_LABELS, REPORTED_LABELS, STATUS_LABELS, lineFor, telHref } from "@/lib/child-safety"; // Labels, the state's reporting line and the phone link maker.
import { plainDate, plainDateTime } from "@/lib/privacy"; // Dates (and dates with times) in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// A concern, as the database gives it.
type Concern = { // Its fields:
  id: string; // its id,
  raised_by_name: string; // who raised it,
  raised_by_roles: string; // their roles at the time,
  raised_by_contact: string | null; // their email and phone at the time,
  child_name: string; // the child,
  child_state: string; // the child's state,
  student_id: string | null; // the CLG student record (if any),
  sent_to: string; // officer or deputy,
  immediate_danger: boolean; // whether a child was in immediate danger,
  called_000: boolean; // whether they called 000,
  reported_to_line: string; // whether they'd reported to the line,
  line_reference: string | null; // the line's reference number,
  happened_on: string | null; // when it happened,
  what_happened: string; // what happened,
  status: string; // where it's up to,
  created_at: string; // when it was raised,
  closed_at: string | null; // when it was closed.
}; // End of the shape.

// A follow-up note, as the database gives it.
type Note = { id: string; concern_id: string; author_name: string; note: string; created_at: string }; // its id, concern, author, words and time.

// Shows the concerns sent to this person.
export default async function ConcernsPage() { // The page itself.
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (viewer.aal !== "aal2") { // Without two-step sign-in the database shows nothing, so explain why:
    return ( // Shows:
      <Page title="Concerns sent to you">{/* a page */}
        <Card>{/* with a card: */}
          <p className="text-sm">{/* the explanation: */}
            Child safety concerns are confidential, so you need two-step sign-in to read them.{" "}{/* why, */}
            <Link href="/mfa" className="font-medium text-teal-800 underline underline-offset-4">Set up or use two-step sign-in</Link>.{/* and the link to do it. */}
          </p>{/* End of the explanation. */}
        </Card>{/* End of the card. */}
      </Page> // End of the page.
    ); // End of what's shown.
  } // End of the check.
  const supabase = await createClient(); // Connects to the database.
  const [concerns, notes, contacts] = await Promise.all([ // Reads three things at once:
    supabase // the concerns sent to them:
      .from("safety_concerns") // (from the concerns table)
      .select("id, raised_by_name, raised_by_roles, raised_by_contact, child_name, child_state, student_id, sent_to, immediate_danger, called_000, reported_to_line, line_reference, happened_on, what_happened, status, created_at, closed_at") // with their details,
      .eq("recipient_id", viewer.id) // sent to this person (not ones they raised),
      .order("created_at", { ascending: false }), // newest first;
    supabase.from("safety_concern_notes").select("id, concern_id, author_name, note, created_at").order("created_at"), // their notes, oldest first (the database only gives notes on their concerns);
    supabase.rpc("child_safety_contacts_list"), // and who the contacts are (for passing on).
  ]); // End of the reads.
  const rows = (concerns.data ?? []) as Concern[]; // The concerns.
  const noteRows = (notes.data ?? []) as Note[]; // The notes.
  const others = ((contacts.data ?? []) as { role: string; account_id: string; full_name: string }[]).filter((c) => c.account_id !== viewer.id); // The other contact (to pass to).
  const open = rows.filter((c) => c.status !== "closed"); // Concerns still open.
  const closed = rows.filter((c) => c.status === "closed"); // Closed concerns.

  // Shows one concern as a card.
  const concernCard = (c: Concern) => { // Takes a concern:
    const line = lineFor(c.child_state); // the reporting line for the child's state,
    const mine = noteRows.filter((n) => n.concern_id === c.id); // its notes,
    const other = others[0]; // the other contact (if any).
    return ( // Shows:
      <Card // a card:
        key={c.id} // (one per concern)
        title={`${c.immediate_danger ? "URGENT: " : ""}${c.child_name} (${c.child_state})`} // titled with the child, marked urgent if so,
        description={`Raised ${plainDateTime(c.created_at)} by ${c.raised_by_name}${c.raised_by_roles ? ` (${c.raised_by_roles})` : ""}. ${STATUS_LABELS[c.status] ?? c.status}.`} // who raised it, when, and where it's up to,
        collapsible // opens and closes,
        defaultOpen={c.status !== "closed"} // open unless closed.
      >{/* (end of the card's settings) */}
        <dl className="grid gap-x-4 gap-y-2 text-sm sm:grid-cols-[12rem_1fr]">{/* the details as a list of pairs: */}
          <dt className="font-medium text-zinc-600">Immediate danger</dt>{/* danger: */}
          <dd>{c.immediate_danger ? `Yes. ${c.called_000 ? "They said they called 000." : "They did NOT say they called 000."}` : "No"}</dd>{/* yes or no, and 000. */}
          <dt className="font-medium text-zinc-600">Reported to the line</dt>{/* reporting line: */}
          <dd>{REPORTED_LABELS[c.reported_to_line] ?? c.reported_to_line}{c.line_reference ? `, reference ${c.line_reference}` : ""}</dd>{/* their answer and reference. */}
          <dt className="font-medium text-zinc-600">When it happened</dt>{/* when: */}
          <dd>{c.happened_on ? plainDate(c.happened_on) : "Not given"}</dd>{/* the date, or "Not given". */}
          <dt className="font-medium text-zinc-600">CLG student</dt>{/* student record: */}
          <dd>{c.student_id ? "Yes" : "No (or the record has since been deleted)"}</dd>{/* yes or no. */}
          <dt className="font-medium text-zinc-600">Contact for the person</dt>{/* contact: */}
          <dd>{c.raised_by_contact ?? "Not available"}</dd>{/* their email and phone. */}
          <dt className="font-medium text-zinc-600">Reporting line</dt>{/* the line for the child's state: */}
          <dd>{/* its details: */}
            {line.service}:{" "}{/* the service, */}
            <a href={telHref(line.phones[0].number)} className="font-semibold underline-offset-4 hover:underline">{line.phones[0].number}</a>{/* and its main number (dials on a phone). */}
          </dd>{/* End of the line. */}
        </dl>{/* End of the details. */}
        <p className="mt-4 whitespace-pre-wrap rounded-xl bg-zinc-50 p-4 text-sm">{c.what_happened}</p>{/* What happened, keeping their line breaks. */}

        <h3 className="mt-6 text-sm font-semibold">Follow-up notes</h3>{/* The notes heading. */}
        {mine.length === 0 ? ( // If no notes:
          <p className="mt-1 text-sm text-zinc-500">None yet.</p> // says so.
        ) : ( // Otherwise:
          <ul className="mt-2 space-y-2 text-sm">{/* the notes: */}
            {mine.map((n) => ( // for each note:
              <li key={n.id} className="border-l-2 border-zinc-200 pl-3">{/* a line with a bar on the left: */}
                <span className="text-xs text-zinc-500">{plainDateTime(n.created_at)}, {n.author_name}</span>{/* when and who, */}
                <span className="block whitespace-pre-wrap">{n.note}</span>{/* and the note. */}
              </li> // End of the note.
            ))}{/* End of the loop. */}
          </ul> // End of the notes.
        )}{/* End of the choice. */}

        <div className="mt-4 grid gap-6 sm:grid-cols-2">{/* The forms, side by side on wide screens: */}
          <ActionForm action={addConcernNote} submitLabel="Add note">{/* adding a note: */}
            <input type="hidden" name="id" value={c.id} />{/* (which concern) */}
            <TextArea label="Add a note" name="note" required minLength={2} maxLength={4000} rows={3} hint="What you did, e.g. 'Phoned CARL, reference 123'. Notes can't be changed later." />{/* the note box. */}
          </ActionForm>{/* End of the form. */}
          <ActionForm action={setConcernStatus} submitLabel="Save">{/* changing where it's up to: */}
            <input type="hidden" name="id" value={c.id} />{/* (which concern) */}
            <Select label="Where is this up to?" name="status" defaultValue={c.status}>{/* the stage drop-down: */}
              {Object.entries(STATUS_LABELS).map(([value, label]) => ( // for each stage:
                <option key={value} value={value}>{label}</option> // an option.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
          </ActionForm>{/* End of the form. */}
        </div>{/* End of the forms. */}

        {other && ( // If there's another contact to pass to:
          <details className="mt-4 rounded-xl border border-zinc-200 p-4">{/* an open-and-close box: */}
            <summary className="cursor-pointer text-sm font-medium text-teal-800">{/* its title: */}
              Pass this to {other.full_name} ({CONTACT_ROLE_LABELS[other.role] ?? other.role}){/* who to pass to. */}
            </summary>{/* End of the title. */}
            <p className="mt-2 text-sm text-zinc-600">{/* a warning: */}
              For example, if it turns out to be about you, or you&apos;re away. After this you won&apos;t be able to open it.{/* when and what happens, */}
            </p>{/* End of the warning. */}
            <div className="mt-3">{/* the form: */}
              <ActionForm action={passOnConcern} submitLabel="Pass it on">{/* passing on: */}
                <input type="hidden" name="id" value={c.id} />{/* (which concern) */}
                <TextArea label="Why are you passing it on?" name="reason" required minLength={2} maxLength={1000} rows={2} />{/* the reason box. */}
              </ActionForm>{/* End of the form. */}
            </div>{/* End of the form area. */}
          </details> // End of the box.
        )}{/* End of passing on. */}
      </Card> // End of the card.
    ); // End of what's shown.
  }; // End of concernCard.

  return ( // Shows:
    <Page // a page:
      title="Concerns sent to you" // titled "Concerns sent to you",
      intro="Only you can read these. Keep them confidential: don't copy details into emails, Teams or other parts of the app." // with a confidentiality reminder.
    >{/* (end of the page's settings) */}
      {open.length === 0 ? <Empty>No open concerns.</Empty> : open.map(concernCard)}{/* The open concerns, or "No open concerns". */}
      {closed.length > 0 && ( // If any are closed:
        <>{/* a group: */}
          <h2 className="pt-4 text-lg font-semibold">Closed</h2>{/* a heading, */}
          {closed.map(concernCard)}{/* and the closed concerns. */}
        </> // End of the group.
      )}{/* End of the closed part. */}
      <p className="text-sm"><Link href="/safety" className="text-teal-800 underline underline-offset-4">Back to Child safety</Link></p>{/* A link back. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of ConcernsPage.
