// Summary: "Flagged words", for the Child Safety Officer, the deputy and the
// owner. The app checks text people write against a list of words and
// phrases that can point to a child safety risk; a match makes a private
// flag here. A person reads each flag in context and records a decision
// (no concern, following up, or raised as a concern). Nothing happens to
// anyone automatically. Below the flags is the list of words, which the
// officer, deputy and owner can change. The database decides who sees what:
// the officer and deputy see flags (never on their own writing), and the
// owner sees only the word list unless they hold one of those jobs.
//
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { addWatchWord, removeWatchWord, reviewWordFlag, setWatchWordActive } from "@/app/actions/watch-words"; // The server actions for decisions and the word list.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { BusyButton, Card, Empty, Field, Page, Select, TextArea } from "@/components/ui"; // The small button, card, "nothing yet" note, text box, page frame, drop-down and multi-line box.
import { getAdminLevel, requireViewer } from "@/lib/auth"; // Makes sure someone is signed in, and reads their admin level.
import { plainDateTime } from "@/lib/privacy"; // Dates with times, in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { CATEGORY_LABELS, FLAG_STATUS_LABELS, sourceLabel } from "@/lib/watch-words"; // The plain names for kinds of risk, decisions and places.

// A flag, as the database gives it.
type Flag = { // Its fields:
  id: string; // its id,
  source_table: string; // the table the text was written in,
  source_field: string; // the box,
  author_name: string; // who wrote it,
  author_roles: string; // their roles at the time,
  student_name: string | null; // the student it's about (if known),
  words: string[]; // the words that matched,
  categories: string[]; // their kinds of risk,
  urgent: boolean; // whether any word is urgent,
  text_copy: string; // a copy of the text,
  status: string; // the decision so far,
  review_note: string | null; // the reviewer's note,
  reviewed_by_name: string | null; // who reviewed it,
  reviewed_at: string | null; // when,
  created_at: string; // when it was flagged.
}; // End of the shape.

// A word on the list, as the database gives it.
type Word = { id: string; phrase: string; category: string; urgent: boolean; staff_only: boolean; active: boolean; note: string | null }; // its id, words, kind, urgency, staff-only, on/off and note.

// The style for a tick box, so it matches the app's other fields.
const tick = "h-4 w-4 shrink-0 accent-teal-700"; // small, in CLG's teal.

// The style for the small buttons beside each word.
const smallButton = "rounded-full border border-zinc-300 px-3 py-1 text-xs font-medium text-zinc-700 hover:bg-zinc-50"; // a small outlined pill.

// Shows the Flagged words page.
export default async function FlagsPage() { // The page itself.
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (viewer.aal !== "aal2") { // Without two-step sign-in the database shows nothing, so explain why:
    return ( // Shows:
      <Page title="Flagged words">{/* a page */}
        <Card>{/* with a card: */}
          <p className="text-sm">{/* the explanation: */}
            Flagged words are confidential, so you need two-step sign-in to read them.{" "}{/* why, */}
            <Link href="/mfa" className="font-medium text-teal-800 underline underline-offset-4">Set up or use two-step sign-in</Link>.{/* and the link to do it. */}
          </p>{/* End of the explanation. */}
        </Card>{/* End of the card. */}
      </Page> // End of the page.
    ); // End of what's shown.
  } // End of the check.
  const supabase = await createClient(); // Connects to the database.
  const [level, contacts] = await Promise.all([getAdminLevel(), supabase.rpc("child_safety_contacts_list")]); // Their admin level, and who the officer and deputy are.
  const isContact = ((contacts.data ?? []) as { account_id: string }[]).some((c) => c.account_id === viewer.id); // True if they're the officer or deputy.
  const isOwner = level === "owner"; // True if they're the owner.
  if (!isContact && !isOwner) { // Anyone else has nothing to see here:
    return ( // Shows:
      <Page title="Flagged words">{/* a page */}
        <Card>{/* with a card: */}
          <p className="text-sm">Only the Child Safety Officer, the deputy and the owner can open this page.</p>{/* who can, */}
          <p className="mt-2 text-sm"><Link href="/safety" className="text-teal-800 underline underline-offset-4">Back to Child safety</Link></p>{/* and a link back. */}
        </Card>{/* End of the card. */}
      </Page> // End of the page.
    ); // End of what's shown.
  } // End of the check.
  const [flags, words] = await Promise.all([ // Reads two things at once:
    supabase // the flags they may see:
      .from("safety_word_flags") // (from the flags table)
      .select("id, source_table, source_field, author_name, author_roles, student_name, words, categories, urgent, text_copy, status, review_note, reviewed_by_name, reviewed_at, created_at") // with their details,
      .order("created_at", { ascending: false }) // newest first,
      .limit(300), // the latest 300;
    supabase.from("safety_watch_words").select("id, phrase, category, urgent, staff_only, active, note").order("phrase"), // and the word list, A to Z.
  ]); // End of the reads.
  const flagRows = (flags.data ?? []) as Flag[]; // The flags.
  const wordRows = (words.data ?? []) as Word[]; // The words.
  const toReview = flagRows.filter((f) => f.status === "new" || f.status === "following_up"); // Flags still needing attention.
  const reviewed = flagRows.filter((f) => f.status === "no_concern" || f.status === "raised_concern"); // Flags already decided.

  // Shows one flag as a card.
  const flagCard = (f: Flag) => ( // Takes a flag and shows:
    <Card // a card:
      key={f.id} // (one per flag)
      title={`${f.urgent ? "URGENT: " : ""}${f.words.map((w) => `"${w}"`).join(", ")}`} // titled with the words that matched, marked urgent if so,
      description={`${sourceLabel(f.source_table, f.source_field)}, written by ${f.author_name}${f.author_roles ? ` (${f.author_roles})` : ""}${f.student_name ? `, about ${f.student_name}` : ""}. ${plainDateTime(f.created_at)}. ${FLAG_STATUS_LABELS[f.status] ?? f.status}.`} // where, who, about whom, when, and the decision so far,
      collapsible // opens and closes,
      defaultOpen={f.status === "new"} // open while not reviewed yet.
    >{/* (end of the card's settings) */}
      <p className="text-xs text-zinc-600">{/* the kinds of risk: */}
        May point to: {f.categories.map((c) => CATEGORY_LABELS[c] ?? c).join(", ")}{/* in words. */}
      </p>{/* End of the kinds. */}
      <p className="mt-3 whitespace-pre-wrap rounded-xl bg-zinc-50 p-4 text-sm">{f.text_copy}</p>{/* The text as it was written, keeping its line breaks. */}
      {f.reviewed_at && ( // If someone has recorded a decision:
        <p className="mt-3 text-sm">{/* the last decision: */}
          <span className="text-xs text-zinc-500">{plainDateTime(f.reviewed_at)}, {f.reviewed_by_name}:</span>{" "}{/* when and who, */}
          {FLAG_STATUS_LABELS[f.status] ?? f.status}{f.review_note ? `. ${f.review_note}` : ""}{/* and what they decided and why. */}
        </p> // End of the decision.
      )}{/* End of that part. */}
      <div className="mt-4">{/* the decision form: */}
        <ActionForm action={reviewWordFlag} submitLabel="Save decision">{/* recording a decision: */}
          <input type="hidden" name="id" value={f.id} />{/* (which flag) */}
          <Select label="What did you decide?" name="status" defaultValue={f.status === "new" ? "no_concern" : f.status}>{/* the decision drop-down: */}
            {Object.entries(FLAG_STATUS_LABELS).filter(([value]) => value !== "new").map(([value, label]) => ( // for each decision (not "not reviewed"):
              <option key={value} value={value}>{label}</option> // an option.
            ))}{/* End of the loop. */}
          </Select>{/* End of the drop-down. */}
          <TextArea label="Note" name="note" maxLength={2000} rows={2} defaultValue={f.review_note ?? ""} hint="Why, in a sentence. Needed for 'No concern' and 'Raised as a concern'." />{/* the note box. */}
        </ActionForm>{/* End of the form. */}
      </div>{/* End of the form area. */}
      <p className="mt-3 text-sm">{/* a link to raise a concern: */}
        Worried? <Link href="/safety" className="font-medium text-red-800 underline underline-offset-4">Raise a child safety concern</Link> (and call 000 if a child is in danger now), then record it here.{/* where to go, and the order. */}
      </p>{/* End of the link. */}
    </Card> // End of the card.
  ); // End of flagCard.

  return ( // Shows:
    <Page // a page:
      title="Flagged words" // titled "Flagged words",
      intro="The app checks writing for words that can point to a child safety risk. A match is only a prompt to look: read it in context and decide. Nobody is told about a flag, and nothing happens to anyone automatically." // with what this is.
    >{/* (end of the page's settings) */}
      {isContact ? ( // The officer or deputy sees the flags:
        <>{/* a group: */}
          <h2 className="text-lg font-semibold">To review</h2>{/* a heading, */}
          {toReview.length === 0 ? <Empty>Nothing to review.</Empty> : toReview.map(flagCard)}{/* the flags to review, or "Nothing to review". */}
          {reviewed.length > 0 && ( // If any have been decided:
            <>{/* a group: */}
              <h2 className="pt-4 text-lg font-semibold">Reviewed</h2>{/* a heading, */}
              {reviewed.map(flagCard)}{/* and those flags. */}
            </> // End of the group.
          )}{/* End of the reviewed part. */}
        </> // End of the group.
      ) : ( // The owner who isn't the officer or deputy:
        <p className="text-sm text-zinc-600">Flags go to the Child Safety Officer and the deputy. As owner you can change the word list below.</p> // explains why there are no flags.
      )}{/* End of the flags part. */}

      <Card // the word list:
        title={`Words and phrases to watch for (${wordRows.filter((w) => w.active).length} on)`} // titled with how many are switched on,
        description="Only the Child Safety Officer, the deputy and the owner can see this list, so it can't be worked around. Whole words only: 'kill' won't match 'skill'. Put * at the end of a word for any ending: 'bully*' matches bullied and bullying." // who sees it, and how matching works,
        collapsible // opens and closes,
        defaultOpen={!isContact} // open for the owner, folded for the reviewers (who mostly want the flags).
      >{/* (end of the card's settings) */}
        <ActionForm action={addWatchWord} submitLabel="Add to the list">{/* adding a word: */}
          <div className="grid gap-4 sm:grid-cols-2">{/* the boxes, side by side on wide screens: */}
            <Field label="Word or phrase" name="phrase" required minLength={2} maxLength={100} hint="e.g. meet me after class" />{/* the word box, */}
            <Select label="What kind of risk could it point to?" name="category" defaultValue="other">{/* the kind drop-down: */}
              {Object.entries(CATEGORY_LABELS).map(([value, label]) => ( // for each kind:
                <option key={value} value={value}>{label}</option> // an option.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
          </div>{/* End of the boxes. */}
          <label className="flex items-center gap-2 text-sm">{/* the urgent tick: */}
            <input type="checkbox" name="urgent" className={tick} />{/* the box, */}
            Urgent: also email the reviewer straight away (even at night){/* and what it does. */}
          </label>{/* End of the tick. */}
          <label className="flex items-center gap-2 text-sm">{/* the staff-only tick: */}
            <input type="checkbox" name="staff_only" className={tick} />{/* the box, */}
            Only flag it when a tutor or admin writes it (e.g. &quot;text me&quot; is normal from a parent){/* and what it does. */}
          </label>{/* End of the tick. */}
          <Field label="Note (optional)" name="note" maxLength={300} hint="Why it's on the list, or what to look for." />{/* the note box. */}
        </ActionForm>{/* End of the form. */}

        {wordRows.length === 0 ? ( // If the list is empty:
          <div className="mt-4"><Empty>The list is empty, so nothing is being checked.</Empty></div> // says so.
        ) : ( // Otherwise:
          Object.entries(CATEGORY_LABELS).map(([category, label]) => { // for each kind of risk:
            const inCategory = wordRows.filter((w) => w.category === category); // its words,
            if (inCategory.length === 0) return null; // (none: shows nothing)
            return ( // shows:
              <div key={category} className="mt-6">{/* a group: */}
                <h3 className="text-sm font-semibold">{label}</h3>{/* the kind's name, */}
                <ul className="mt-2 divide-y divide-zinc-100 text-sm">{/* and its words: */}
                  {inCategory.map((w) => ( // for each word:
                    <li key={w.id} className="flex flex-wrap items-center gap-2 py-2">{/* a line: */}
                      <span className={w.active ? "font-medium" : "text-zinc-400 line-through"}>{w.phrase}</span>{/* the word (crossed out when off), */}
                      {w.urgent && <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs text-red-800">Urgent</span>}{/* an "Urgent" tag, */}
                      {w.staff_only && <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-xs text-zinc-700">Staff writing only</span>}{/* a "Staff writing only" tag, */}
                      {w.note && <span className="text-xs text-zinc-500">{w.note}</span>}{/* its note, */}
                      <span className="ml-auto flex gap-2">{/* and its buttons: */}
                        <form action={setWatchWordActive}>{/* turning it on or off: */}
                          <input type="hidden" name="id" value={w.id} />{/* (which word) */}
                          <input type="hidden" name="active" value={w.active ? "false" : "true"} />{/* (the opposite of now) */}
                          <BusyButton type="submit" className={smallButton}>{w.active ? "Turn off" : "Turn on"}</BusyButton>{/* the button. */}
                        </form>{/* End of the form. */}
                        <form action={removeWatchWord}>{/* removing it: */}
                          <input type="hidden" name="id" value={w.id} />{/* (which word) */}
                          <BusyButton type="submit" className={smallButton}>Remove</BusyButton>{/* the button. */}
                        </form>{/* End of the form. */}
                      </span>{/* End of the buttons. */}
                    </li> // End of the line.
                  ))}{/* End of the loop. */}
                </ul>{/* End of the words. */}
              </div> // End of the group.
            ); // End of what's shown.
          }) // End of the loop.
        )}{/* End of the list. */}
      </Card>{/* End of the word list. */}
      <p className="text-sm"><Link href="/safety" className="text-teal-800 underline underline-offset-4">Back to Child safety</Link></p>{/* A link back. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of FlagsPage.
