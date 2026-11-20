// Summary: the parent and student Overviews. A parent sees what needs them
// (session times to approve, details to finish, billing to set up if they
// pay), each of their own children with tutors and next session, and the
// family's next sessions. A student sees their next session, steps due
// this week, their own tutors and coming sessions. Both are told when
// sessions are on hold. Billing details show only for the person or
// people who pay (Carla, 16 Nov 2026), and a student never sees a
// sibling's details.
//
import { Card, Empty, TextLink } from "@/components/ui"; // Shared page parts: a card, an empty-state line and a text link.
import type { Role } from "@/lib/auth"; // The role type (for type checking only).
import { getDashboardMenu, sessionsHref } from "@/lib/dashboard-menu"; // The side menu (shared with the page frame), and the Sessions page address.
import { getToDoCounts } from "@/lib/to-do-counts"; // The to-do numbers.
import { getOffersToAnswer } from "@/components/session-answers-card"; // How many session times wait for this person's answer.
import { attentionLines, comingUp, plural, weekOfSessions } from "@/lib/home-overview"; // Overview helpers.
import { addDays, currentTime, localToday, sessionWhen, shortDate } from "@/lib/scheduling"; // Date helpers: add days, the time now, today, and times and dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { StepRow, type Step } from "@/app/students/[id]/progress/roadmap"; // One roadmap step row (with its tick box), and the step type.
import { AttentionCard, ComingUpCard, Tiles, type Tile } from "./overview-parts"; // The Overview building blocks.

type Client = Awaited<ReturnType<typeof createClient>>; // A database connection (for type checking).
type TutorRow = { student_id: string; subject: string; tutor: { account: { full_name: string } | null } | null }; // One tutor match: the student, the subject and the tutor's name.

// The progress notice kinds that families see as "new from your tutor".
const FAMILY_NOTICES = ["session_update", "review_ready", "review_offer", "step_due"]; // session notes, term reviews, review offers and steps due.

// How many updates from tutors this person has not opened yet (only their
// own notices: each one is addressed to one account).
async function newUpdates(supabase: Client, viewerId: string): Promise<number> { // Takes the connection and the person's id.
  const { count } = await supabase.from("progress_notices").select("id", { count: "exact", head: true }).eq("account_id", viewerId).in("kind", FAMILY_NOTICES).is("read_at", null); // Counts them without reading them.
  return count ?? 0; // The number (none if it could not be counted).
} // End of newUpdates.

// The tutors matched with some students, with their names.
async function tutorsOf(supabase: Client, studentIds: string[]): Promise<TutorRow[]> { // Takes the connection and the students.
  if (studentIds.length === 0) return []; // No students: no tutors.
  const { data } = await supabase.from("tutor_assignments").select("student_id, subject, tutor:tutor_profiles(account:accounts(full_name))").in("student_id", studentIds); // Reads the matches and the tutors' names.
  return (data ?? []) as unknown as TutorRow[]; // The matches (none if the read failed).
} // End of tutorsOf.

// "Mathematics with Jack Smith, English with Amy Lee": a student's tutors in words.
function tutorWords(rows: TutorRow[]): string { // Takes one student's matches.
  return rows.map((r) => `${r.subject} with ${r.tutor?.account?.full_name ?? "your tutor"}`).join(", "); // Each subject and tutor, joined with commas.
} // End of tutorWords.

// The "Sessions on hold" card, when an invoice is overdue. Every parent and
// student is told, even those who do not pay (they have no Billing tab).
function OnHoldCard({ who }: { who: "parent" | "student" }) { // Takes whose dashboard it is (for the wording).
  return ( // Shows:
    <div className="rounded-2xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950 shadow-sm" role="status">{/* an amber box screen readers announce: */}
      <p className="font-medium">Sessions on hold</p>{/* the heading, */}
      <p className="mt-1">{/* and why, and who can fix it: */}
        {who === "parent" ? "Your family's sessions are on hold because an invoice is overdue. They start again as soon as it is paid. The person who pays can do this in Billing, or contact CLG." : "Your sessions are on hold because an invoice is overdue. Please check with whoever pays for your sessions. If that is you, pay it in Billing."}{/* (the parent wording, or the student wording) */}
      </p>{/* End of the words. */}
    </div> // End of the box.
  ); // End of what is shown.
} // End of OnHoldCard.

// The Billing card, only for someone who pays for a family: invoices to pay
// (with the soonest due date) and anything still to set up. It reads only
// the families this person pays for, even if they are also an admin.
async function BillingCard({ supabase, viewerId, setUp }: { supabase: Client; viewerId: string; setUp: number }) { // Takes the connection, the person's id, and how many billing things are still to set up.
  const [choices, shares] = await Promise.all([ // Reads, at once:
    supabase.rpc("billing_my_plan_choices"), // the families this person pays for,
    supabase.from("billing_payers").select("family_id").eq("account_id", viewerId), // and any family where they pay a split share.
  ]); // End of the reads.
  const families = [...new Set([...((choices.data ?? []) as { family_id: string }[]).map((c) => c.family_id), ...(shares.data ?? []).map((r) => r.family_id)])]; // Their own families, each once.
  const { data } = families.length // Reads their invoices still to pay (if they pay for any family):
    ? await supabase.from("billing_invoices").select("id, due_on").in("family_id", families).eq("status", "open").order("due_on") // open invoices for their own families, soonest due first,
    : { data: [] }; // otherwise none.
  const open = (data ?? []) as { id: string; due_on: string }[]; // The invoices to pay.
  return ( // Shows:
    <Card title="Billing">{/* a card: */}
      <ul className="space-y-1.5 text-sm">{/* a short list: */}
        <li>{open.length ? `${plural(open.length, "invoice")} to pay, next due ${shortDate(open[0].due_on)}.` : "No invoices to pay right now."}</li>{/* invoices to pay, or none, */}
        {setUp > 0 && <li className="font-medium text-amber-900">{plural(setUp, "thing")} to set up (a plan, the payment terms or automatic payment).</li>}{/* anything still to set up. */}
      </ul>{/* End of the list. */}
      <p className="mt-4 text-sm"><TextLink href="/billing">Open Billing</TextLink></p>{/* A link to Billing. */}
    </Card> // End of the card.
  ); // End of what is shown.
} // End of BillingCard.

// Shows the parent Overview.
export async function ParentOverview({ viewerId, roles }: { viewerId: string; roles: Role[] }) { // Takes the parent's id and all of their roles.
  const supabase = await createClient(); // Connects to the database.
  const [menu, todo, offers, sessions, linksRes, onHold, updates] = await Promise.all([ // Reads, at once:
    getDashboardMenu("parent", roles), // their parent side menu (already built for the page frame),
    getToDoCounts(roles), // the to-do numbers,
    getOffersToAnswer(), // session times waiting for their answer,
    weekOfSessions(), // the coming week's sessions,
    supabase.from("parent_student_links").select("student_id, verified_at").eq("parent_id", viewerId), // their own children (and which CLG has checked),
    supabase.rpc("my_support_on_hold"), // whether the family's sessions are on hold,
    newUpdates(supabase, viewerId), // and how many updates from tutors are new.
  ]); // End of the reads.
  const links = (linksRes.data ?? []) as { student_id: string; verified_at: string | null }[]; // Their links to their children.
  const ids = links.map((l) => l.student_id); // Their children's ids.
  const [kidsRes, tutors] = await Promise.all([ // Reads, at once:
    ids.length ? supabase.from("students").select("id, full_name, year_level").in("id", ids).order("full_name") : Promise.resolve({ data: [] }), // their children's names and year levels,
    tutorsOf(supabase, ids), // and their children's tutors.
  ]); // End of the reads.
  const kids = (kidsRes.data ?? []) as { id: string; full_name: string; year_level: string | null }[]; // Their children.
  const checked = new Set(links.filter((l) => l.verified_at).map((l) => l.student_id)); // The children CLG has checked.
  const next = comingUp(sessions.filter((s) => ids.includes(s.student_id)), currentTime()); // Their own children's sessions still to come in the next 7 days.
  const pays = menu.some((m) => m.id === "billing"); // Whether they pay (only payers have a Billing tab).

  const tiles: Tile[] = [ // The quick-look tiles:
    { label: "Next session", value: next[0] ? sessionWhen(next[0].starts_at) : "None booked", note: next[0] ? `${next[0].student_name}, ${next[0].subject}` : undefined, href: "/dashboard/calendar?as=parent" }, // the next session,
    { label: "Next 7 days", value: plural(next.length, "session"), href: "/dashboard/calendar?as=parent" }, // sessions in the coming week,
    { label: "Times to approve", value: String(offers.as_family), note: offers.as_family ? "Answer before the time runs out" : undefined, href: sessionsHref("parent", "bookings"), warn: offers.as_family > 0 }, // session times waiting for their yes,
    { label: "New from tutors", value: String(updates), href: "/dashboard/parent?section=children" }, // and new updates from tutors.
  ]; // End of the tiles.

  return ( // Shows:
    <>{/* (a group) */}
      {onHold.data === true && <OnHoldCard who="parent" />}{/* sessions on hold (if they are), */}
      <Tiles tiles={tiles} role="parent" />{/* the quick-look tiles, */}
      <AttentionCard lines={attentionLines("parent", menu, todo)} />{/* what needs them now, */}
      <Card title="Your children">{/* their children: */}
        {kids.length === 0 ? ( // None yet:
          <Empty>No children added yet. <TextLink href="/dashboard/parent?section=add">Add your child</TextLink> to get started.</Empty> // a line with a link to add one.
        ) : ( // Otherwise:
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {kids.map((k) => { // for each child:
              const theirs = tutors.filter((t) => t.student_id === k.id); // their tutors,
              const soonest = next.find((s) => s.student_id === k.id); // and their next session.
              return ( // Shows:
                <li key={k.id} className="py-3 first:pt-0 last:pb-0">{/* a row: */}
                  <p className="flex flex-wrap items-baseline justify-between gap-2">{/* the top line: */}
                    <span><span className="font-medium">{k.full_name}</span>{k.year_level && <span className="text-zinc-600"> · {k.year_level}</span>}</span>{/* the name and year level, */}
                    {checked.has(k.id) ? <TextLink href={`/students/${k.id}/progress?view=family`}>Progress</TextLink> : <span className="rounded-full bg-zinc-100 px-3 py-0.5 text-xs text-zinc-600">CLG is checking the details</span>}{/* a Progress link, or a note that CLG is checking. */}
                  </p>{/* End of the top line. */}
                  <p className="mt-1 text-zinc-600">{theirs.length ? tutorWords(theirs) : "No tutor yet."}</p>{/* their tutors, or none yet, */}
                  <p className="mt-0.5 text-zinc-600">{soonest ? `Next session: ${sessionWhen(soonest.starts_at)}` : "No session in the coming week."}</p>{/* and their next session. */}
                </li> // End of the row.
              ); // End of this child.
            })}{/* End of the children. */}
          </ul> // End of the list.
        )}{/* End of this part. */}
        <p className="mt-4 text-sm"><TextLink href="/dashboard/parent?section=children">See or change your children&apos;s details</TextLink></p>{/* A link to the full children page. */}
      </Card>{/* End of the children card. */}
      <ComingUpCard sessions={next} show="both" sessionsHref={sessionsHref("parent")} empty="No sessions in the coming week." />{/* the family's next sessions, */}
      {pays && <BillingCard supabase={supabase} viewerId={viewerId} setUp={todo.get("family", "billing") ?? 0} />}{/* and Billing, only for a parent who pays. */}
    </> // End of the group.
  ); // End of what is shown.
} // End of ParentOverview.

// Shows the student Overview. Only the student's own record is used, so a
// sibling's details never show, even when the same parent is linked to both.
export async function StudentOverview({ viewerId, roles }: { viewerId: string; roles: Role[] }) { // Takes the student's id and all of their roles.
  const supabase = await createClient(); // Connects to the database.
  const [menu, todo, sessions, ownRes, onHold, updates] = await Promise.all([ // Reads, at once:
    getDashboardMenu("student", roles), // their student side menu (already built for the page frame),
    getToDoCounts(roles), // the to-do numbers,
    weekOfSessions(), // the coming week's sessions,
    supabase.from("students").select("id").eq("account_id", viewerId).maybeSingle(), // their own student record,
    supabase.rpc("my_support_on_hold"), // whether their sessions are on hold,
    newUpdates(supabase, viewerId), // and how many updates from tutors are new.
  ]); // End of the reads.
  const me = ownRes.data as { id: string } | null; // Their student record (if any).
  const today = localToday(); // Today's date in Adelaide.
  const [stepsRes, tutors] = await Promise.all([ // Reads, at once:
    me // their steps due in the next week (or overdue), if they have a student record:
      ? supabase.from("roadmap_steps").select("id, target_id, title, due_on, source, done_at, created_by").eq("student_id", me.id).is("done_at", null).lte("due_on", addDays(today, 7)).order("due_on").limit(5) // up to 5, soonest first,
      : Promise.resolve({ data: [] }), // otherwise none,
    tutorsOf(supabase, me ? [me.id] : []), // and their own tutors.
  ]); // End of the reads.
  const steps = (stepsRes.data ?? []) as Step[]; // Their steps this week.
  const next = comingUp(sessions.filter((s) => s.student_id === me?.id), currentTime()); // Their own sessions still to come in the next 7 days.
  const pays = menu.some((m) => m.id === "billing"); // Whether they pay for themselves (only then is Billing in their menu).

  const tiles: Tile[] = [ // The quick-look tiles:
    { label: "Next session", value: next[0] ? sessionWhen(next[0].starts_at) : "None booked", note: next[0] ? next[0].subject : undefined, href: "/dashboard/calendar?as=student" }, // the next session,
    { label: "Next 7 days", value: plural(next.length, "session"), href: "/dashboard/calendar?as=student" }, // sessions in the coming week,
    { label: "Steps this week", value: String(steps.length), note: steps.length ? "Tick them off below" : undefined, href: "/dashboard/student" }, // steps due this week,
    { label: "New from tutors", value: String(updates), href: me ? `/students/${me.id}/progress?view=family` : "/dashboard/student" }, // and new updates from tutors.
  ]; // End of the tiles.

  return ( // Shows:
    <>{/* (a group) */}
      {onHold.data === true && <OnHoldCard who="student" />}{/* sessions on hold (if they are), */}
      <Tiles tiles={tiles} role="student" />{/* the quick-look tiles, */}
      <AttentionCard lines={attentionLines("student", menu, todo)} />{/* what needs them now, */}
      {me && steps.length > 0 && ( // If they have steps this week:
        <Card title="Your steps this week" description="Small steps between sessions help you remember more. Tick each one off when it is done.">{/* a card, saying why: */}
          <ul className="space-y-1.5">{/* a list: */}
            {steps.map((s) => <StepRow key={s.id} step={s} studentId={me.id} today={today} canPlan canRemove={false} />)}{/* each step (they can tick it, not remove it). */}
          </ul>{/* End of the list. */}
        </Card> // End of the card.
      )}{/* End of the steps card. */}
      <ComingUpCard sessions={next} show="tutor" sessionsHref={sessionsHref("student")} empty="No sessions in the coming week." />{/* their next sessions, */}
      <Card title="Your tutors">{/* their tutors: */}
        <p className="text-sm text-zinc-700">{tutors.length ? tutorWords(tutors) : "No tutor yet."}</p>{/* their tutors, or none yet, */}
        {me && <p className="mt-4 text-sm"><TextLink href={`/students/${me.id}/progress?view=family`}>Open your progress page</TextLink></p>}{/* and a link to their progress page. */}
      </Card>{/* End of the tutors card. */}
      {pays && <BillingCard supabase={supabase} viewerId={viewerId} setUp={todo.get("family", "billing") ?? 0} />}{/* and Billing, only for a student who pays for themselves. */}
    </> // End of the group.
  ); // End of what is shown.
} // End of StudentOverview.
