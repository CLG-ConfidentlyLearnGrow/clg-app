// Summary: "Concerns sent to you", for the Child Safety Officer and the
// deputy. Each person sees only the concerns sent to them or shared with
// them (the database enforces this, and needs two-step sign-in). A concern
// never reaches a CLG worker it names, unless it names both contacts or was
// shared on purpose. For each concern: who it's about, the details, the
// follow-up notes, a box to add a note, where it's up to, and ways to pass
// it on or share it with the other contact. Notes can't be edited or deleted.
// For a tutor the concern names, two quiet steps: stop new students, and end
// the match with the child in the concern. The tutor is never told why.
//
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { addConcernNote, endMatch, liftHold, passOnConcern, setConcernStatus, shareConcern, stopNewStudents } from "@/app/actions/child-safety"; // The server actions for notes, stages, passing on, sharing and the quiet steps.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { BackButton, Card, Empty, Page, Select, TextArea } from "@/components/ui"; // The back button, card, "nothing yet" note, page frame, drop-down and multi-line box.
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
  recipient_id: string | null; // the person it was sent to,
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

// A CLG worker a concern is about, as the database gives it.
type Named = { concern_id: string; account_id: string | null; full_name: string }; // the concern, the worker's account and their name.

// The quiet steps for one tutor a concern names, as the database gives them.
type Steps = { tutor_id: string; full_name: string; no_new_students_id: string | null; end_match_id: string | null; matched_now: boolean; upcoming_bookings: number }; // the tutor, their name, each step in place (if any), whether matched with the child now, and bookings left.

// An "urgent: needs a new tutor" flag on a concern, as the database gives it.
type Rematch = { tutor_id: string; upcoming_sessions: number; paid_sessions: number; first_session: string | null; sorted_at: string | null; sorted_note: string | null }; // the tutor, the counts, first date, and whether it's sorted.

// An extra reader of a concern, as the database gives it.
type Reader = { concern_id: string; account_id: string; reason: string }; // the concern, the reader and why ("names_both" or "shared").

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
  const [concerns, notes, contacts, named, readers] = await Promise.all([ // Reads five things at once:
    supabase // the concerns sent to them:
      .from("safety_concerns") // (from the concerns table)
      .select("id, raised_by_name, raised_by_roles, raised_by_contact, child_name, child_state, student_id, sent_to, recipient_id, immediate_danger, called_000, reported_to_line, line_reference, happened_on, what_happened, status, created_at, closed_at") // with their details,
      .order("created_at", { ascending: false }), // newest first (ones they only raised are left out below);
    supabase.from("safety_concern_notes").select("id, concern_id, author_name, note, created_at").order("created_at"), // their notes, oldest first (the database only gives notes on their concerns);
    supabase.rpc("child_safety_contacts_list"), // who the contacts are (for passing on and sharing),
    supabase.from("safety_concern_people").select("concern_id, account_id, full_name"), // who each concern is about (the database only gives rows for concerns they can read),
    supabase.from("safety_concern_readers").select("concern_id, account_id, reason"), // and the extra readers of the concerns they handle.
  ]); // End of the reads.
  const namedRows = (named.data ?? []) as Named[]; // Who each concern is about.
  const readerRows = (readers.data ?? []) as Reader[]; // The extra readers.
  const sharedWithMe = new Map(readerRows.filter((r) => r.account_id === viewer.id).map((r) => [r.concern_id, r.reason])); // The concerns they read as an extra reader, and why.
  const rows = ((concerns.data ?? []) as Concern[]).filter((c) => c.recipient_id === viewer.id || sharedWithMe.has(c.id)); // Only concerns they handle (not ones they only raised).
  const noteRows = (notes.data ?? []) as Note[]; // The notes.
  const others = ((contacts.data ?? []) as { role: string; account_id: string; full_name: string }[]).filter((c) => c.account_id !== viewer.id); // The other contact (to pass to).
  const stepRows = await Promise.all( // Reads the quiet steps for each concern that names someone (at the same time):
    rows.filter((c) => namedRows.some((n) => n.concern_id === c.id)).map(async (c) => { // for each such concern:
      const { data } = await supabase.rpc("safety_concern_quiet_steps", { p_concern: c.id }); // asks the database,
      return [c.id, (data ?? []) as Steps[]] as const; // and keeps the answer with the concern's id.
    }), // End of the loop.
  ); // End of the reads.
  const stepsFor = new Map(stepRows); // The quiet steps, by concern.
  const rematchRows = await Promise.all( // Reads any "urgent: needs a new tutor" flags for those concerns (at the same time):
    stepRows.map(async ([id]) => { // for each concern that names someone:
      const { data } = await supabase.rpc("safety_concern_rematch", { p_concern: id }); // asks the database,
      return [id, (data ?? []) as Rematch[]] as const; // and keeps the answer with the concern's id.
    }), // End of the loop.
  ); // End of the reads.
  const rematchFor = new Map(rematchRows); // The urgent flags, by concern.
  const open = rows.filter((c) => c.status !== "closed"); // Concerns still open.
  const closed = rows.filter((c) => c.status === "closed"); // Closed concerns.

  // Shows one concern as a card.
  const concernCard = (c: Concern) => { // Takes a concern:
    const line = lineFor(c.child_state); // the reporting line for the child's state,
    const mine = noteRows.filter((n) => n.concern_id === c.id); // its notes,
    const other = others[0]; // the other contact (if any),
    const about = namedRows.filter((n) => n.concern_id === c.id); // the CLG workers it's about,
    const otherIsNamed = !!other && about.some((n) => n.account_id === other.account_id); // whether the other contact is one of them,
    const otherCanRead = !!other && (c.recipient_id === other.account_id || readerRows.some((r) => r.concern_id === c.id && r.account_id === other.account_id)); // whether the other contact can already read it,
    const isRecipient = c.recipient_id === viewer.id; // whether it was sent to them (only they can pass it on),
    const why = sharedWithMe.get(c.id); // why they can read it, if they're an extra reader.
    return ( // Shows:
      <Card // a card:
        key={c.id} // (one per concern)
        title={`${c.immediate_danger ? "URGENT: " : ""}${c.child_name} (${c.child_state})`} // titled with the child, marked urgent if so,
        description={`Raised ${plainDateTime(c.created_at)} by ${c.raised_by_name}${c.raised_by_roles ? ` (${c.raised_by_roles})` : ""}. ${STATUS_LABELS[c.status] ?? c.status}.`} // who raised it, when, and where it's up to,
        collapsible // opens and closes,
        defaultOpen={c.status !== "closed"} // open unless closed.
      >{/* (end of the card's settings) */}
        {why && ( // If they read it as an extra reader:
          <p className="mb-3 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-950">{/* a note saying why: */}
            {why === "names_both" ? "This concern names both child safety contacts, so it was sent to both of you." : "This concern was shared with you by the person handling it."}{/* both named, or shared. */}
          </p> // End of the note.
        )}{/* End of the reader note. */}
        <dl className="grid gap-x-4 gap-y-2 text-sm sm:grid-cols-[12rem_1fr]">{/* the details as a list of pairs: */}
          <dt className="font-medium text-zinc-600">About a CLG worker</dt>{/* who it's about: */}
          <dd>{about.length === 0 ? "No one named" : about.map((n) => n.full_name).join(", ")}{about.length > 0 ? ". They cannot see this concern." : ""}</dd>{/* their names, or "No one named". */}
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

        {(stepsFor.get(c.id) ?? []).map((t) => ( // For each tutor the concern names, the quiet steps:
          <div key={t.tutor_id} className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm">{/* an amber box: */}
            <p className="font-semibold">Quiet steps for {t.full_name}</p>{/* its heading, */}
            <p className="mt-1 text-amber-950">Nothing happens unless you press a button. {t.full_name} will not be told why, and admins doing matching only see &quot;Cannot be matched&quot;.</p>{/* what these do, */}
            <div className="mt-3 grid gap-4 sm:grid-cols-2">{/* the two steps, side by side on wide screens: */}
              <div>{/* step 1: */}
                {t.no_new_students_id ? ( // If they're already stopped from new students:
                  <ActionForm action={liftHold} submitLabel="Lift">{/* a form to lift it: */}
                    <p className="font-medium">Stopped from new students.</p>{/* says so, */}
                    <input type="hidden" name="hold" value={t.no_new_students_id} />{/* (which step) */}
                    <TextArea label="Why are you lifting it?" name="reason" required minLength={2} maxLength={1000} rows={2} />{/* the reason box. */}
                  </ActionForm> // End of the form.
                ) : ( // Otherwise:
                  <ActionForm action={stopNewStudents} submitLabel="Stop new students">{/* a form to take the step: */}
                    <p className="text-zinc-700">They keep the students they have now, but will not be matched with anyone new.</p>{/* what it does, */}
                    <input type="hidden" name="id" value={c.id} />{/* (which concern) */}
                    <input type="hidden" name="tutor" value={t.tutor_id} />{/* (which tutor) */}
                    <TextArea label="Why?" name="reason" required minLength={2} maxLength={1000} rows={2} />{/* the reason box. */}
                  </ActionForm> // End of the form.
                )}{/* End of step 1. */}
              </div>{/* End of step 1. */}
              <div>{/* step 2: */}
                {t.end_match_id ? ( // If the match was already ended from a concern:
                  <ActionForm action={liftHold} submitLabel="Allow matching again">{/* a form to lift the block: */}
                    <p className="font-medium">Match with {c.child_name} ended. They cannot be matched again while this is in place.</p>{/* says so, */}
                    {(rematchFor.get(c.id) ?? []).filter((r) => r.tutor_id === t.tutor_id).map((r) => ( // any urgent re-match flag for this tutor:
                      <p key={r.tutor_id} className="text-zinc-700">{/* a line: */}
                        {r.sorted_at ? `New tutor sorted: ${r.sorted_note ?? "done"}.` : `Urgent on the Matching page: ${r.paid_sessions} paid session(s) of ${r.upcoming_sessions} booked need a new tutor.`}{/* sorted, or still urgent with the counts. */}
                      </p> // End of the line.
                    ))}{/* End of the flags. */}
                    <input type="hidden" name="hold" value={t.end_match_id} />{/* (which step) */}
                    <TextArea label="Why are you lifting it? (The match will not restart by itself.)" name="reason" required minLength={2} maxLength={1000} rows={2} />{/* the reason box. */}
                  </ActionForm> // End of the form.
                ) : c.student_id ? ( // Otherwise, if the child is a CLG student:
                  <ActionForm action={endMatch} submitLabel={`End match with ${c.child_name}`}>{/* a form to take the step: */}
                    <p className="text-zinc-700">{/* what it does: */}
                      {t.matched_now ? `Ends ${t.full_name}'s match with ${c.child_name} today, so they can no longer open ${c.child_name}'s records.` : `${t.full_name} is not matched with ${c.child_name} now. This stops them being matched in future.`}
                      {t.upcoming_bookings > 0 ? ` They have ${t.upcoming_bookings} upcoming booking(s) together. ${c.child_name} will go to the top of the Matching page as "Urgent: needs a new tutor", with paid sessions counted and no reason shown.` : ""}{/* and what happens to booked sessions. */}
                    </p>{/* End of the explanation. */}
                    <input type="hidden" name="id" value={c.id} />{/* (which concern) */}
                    <input type="hidden" name="tutor" value={t.tutor_id} />{/* (which tutor) */}
                    <TextArea label="Why?" name="reason" required minLength={2} maxLength={1000} rows={2} />{/* the reason box. */}
                  </ActionForm> // End of the form.
                ) : ( // A child who isn't a CLG student:
                  <p className="text-zinc-700">The child is not a CLG student, so there is no match to end.</p> // says so.
                )}{/* End of step 2. */}
              </div>{/* End of step 2. */}
            </div>{/* End of the two steps. */}
          </div> // End of the box.
        ))}{/* End of the quiet steps. */}

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
            <TextArea label="Add a note" name="note" required minLength={2} maxLength={4000} rows={3} hint="What you did, e.g. 'Phoned CARL, reference 123'. Notes cannot be changed later." />{/* the note box. */}
          </ActionForm>{/* End of the form. */}
          {/* The key changes with the saved stage, so the drop-down shows the new
              stage after saving instead of jumping back to the old one. */}
          <ActionForm key={c.status} action={setConcernStatus} submitLabel="Save">{/* changing where it's up to: */}
            <input type="hidden" name="id" value={c.id} />{/* (which concern) */}
            <Select label="Where is this up to?" name="status" defaultValue={c.status}>{/* the stage drop-down: */}
              {Object.entries(STATUS_LABELS).map(([value, label]) => ( // for each stage:
                <option key={value} value={value}>{label}</option> // an option.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
          </ActionForm>{/* End of the form. */}
        </div>{/* End of the forms. */}

        {other && isRecipient && !otherIsNamed && ( // If there's another contact to pass to (and it isn't about them):
          <details className="mt-4 rounded-xl border border-zinc-200 p-4">{/* an open-and-close box: */}
            <summary className="cursor-pointer text-sm font-medium text-teal-800">{/* its title: */}
              Pass this to {other.full_name} ({CONTACT_ROLE_LABELS[other.role] ?? other.role}){/* who to pass to. */}
            </summary>{/* End of the title. */}
            <p className="mt-2 text-sm text-zinc-600">{/* a warning: */}
              For example, if it turns out to be about you, or you are away. After this you will not be able to open it.{/* when and what happens, */}
            </p>{/* End of the warning. */}
            <div className="mt-3">{/* the form: */}
              <ActionForm action={passOnConcern} submitLabel="Pass it on">{/* passing on: */}
                <input type="hidden" name="id" value={c.id} />{/* (which concern) */}
                <TextArea label="Why are you passing it on?" name="reason" required minLength={2} maxLength={1000} rows={2} />{/* the reason box. */}
              </ActionForm>{/* End of the form. */}
            </div>{/* End of the form area. */}
          </details> // End of the box.
        )}{/* End of passing on. */}

        {other && !otherCanRead && ( // If there's another contact who can't read it yet:
          <details className="mt-4 rounded-xl border border-zinc-200 p-4">{/* an open-and-close box: */}
            <summary className="cursor-pointer text-sm font-medium text-teal-800">{/* its title: */}
              Share this with {other.full_name} ({CONTACT_ROLE_LABELS[other.role] ?? other.role}){/* who to share with. */}
            </summary>{/* End of the title. */}
            <p className="mt-2 text-sm text-zinc-600">{/* a warning: */}
              {otherIsNamed ? `This concern is about ${other.full_name}. Only share it if you have decided they should see it.` : "They will be able to read it and its notes, and so will you."}{" "}
              Sharing cannot be undone, and your reason is kept as a note.{/* what sharing means, */}
            </p>{/* End of the warning. */}
            <div className="mt-3">{/* the form: */}
              <ActionForm action={shareConcern} submitLabel="Share it">{/* sharing: */}
                <input type="hidden" name="id" value={c.id} />{/* (which concern) */}
                <TextArea label="Why are you sharing it?" name="reason" required minLength={2} maxLength={1000} rows={2} />{/* the reason box. */}
              </ActionForm>{/* End of the form. */}
            </div>{/* End of the form area. */}
          </details> // End of the box.
        )}{/* End of sharing. */}
      </Card> // End of the card.
    ); // End of what's shown.
  }; // End of concernCard.

  return ( // Shows:
    <Page // a page:
      title="Concerns sent to you" // titled "Concerns sent to you",
      intro="Only you (and anyone a concern was shared with) can read these. Keep them confidential: do not copy details into emails, Teams or other parts of the app." // with a confidentiality reminder.
    >{/* (end of the page's settings) */}
      <p><BackButton href="/safety">Back to Child safety</BackButton></p>{/* A button back to the Child safety page. */}
      {open.length === 0 ? <Empty>No open concerns.</Empty> : open.map(concernCard)}{/* The open concerns, or "No open concerns". */}
      {closed.length > 0 && ( // If any are closed:
        <>{/* a group: */}
          <h2 className="pt-4 text-lg font-semibold">Closed</h2>{/* a heading, */}
          {closed.map(concernCard)}{/* and the closed concerns. */}
        </> // End of the group.
      )}{/* End of the closed part. */}
      <p><BackButton href="/safety">Back to Child safety</BackButton></p>{/* The same back button at the bottom, so it's there after scrolling down. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of ConcernsPage.
