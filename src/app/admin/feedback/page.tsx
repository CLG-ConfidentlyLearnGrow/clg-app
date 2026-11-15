// Summary: the feedback overview for full admins (owner and operations),
// Carla 15 Nov 2026. Feedback is grouped three ways (the app, CLG's service,
// people at CLG). For each area it shows what's going well (praise), ideas,
// and worries over the last 90 days, the average rating, and whether it's
// getting better or worse than the 90 days before. Under each area are the
// latest comments, with a way to mark where each is up to and keep a private
// note. Feedback about a person only shows to the Child Safety Officer (or
// the deputy when it's about the officer); the database enforces that.
// The owner can add, rename or hide areas at the bottom.
//
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { setFeedbackArea, updateFeedback } from "@/app/actions/feedback"; // The server actions for updating feedback and changing areas.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Empty, Field, Page, Select, TextArea } from "@/components/ui"; // The card, "nothing yet" note, text box, page frame, drop-down and multi-line box.
import { requireAdmin } from "@/lib/auth"; // Lets in only full admins with two-step sign-in.
import { FEEDBACK_GROUPS, FEEDBACK_KINDS, FEEDBACK_STATUS, periodStart, splitByPeriod, sumFeedback, trendWords, type FeedbackSums } from "@/lib/feedback"; // The words and the sums.
import { plainDate } from "@/lib/privacy"; // Dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// How many days count as "this period".
const PERIOD_DAYS = 90; // About one school term.

// A feedback area, as the database gives it.
type Area = { id: string; grp: "app" | "service" | "people"; label: string; active: boolean }; // its short name, group, name and whether it can be picked.

// A piece of feedback, as the database gives it.
type Row = { // Its fields:
  id: string; // its id,
  area_id: string; // its area,
  about_name: string | null; // the person it's about (if any),
  given_by_name: string; // who gave it,
  given_by_roles: string; // their roles at the time,
  kind: string; // praise, idea or worry,
  rating: number | null; // the rating (if any),
  comment: string; // what they said,
  status: string; // where it's up to,
  admin_note: string | null; // the private note,
  created_at: string; // when it was given.
}; // End of the shape.

// Shows the counts for one area as a short line of figures.
function Figures({ sums }: { sums: FeedbackSums }) { // Takes the sums.
  return ( // Shows:
    <p className="flex flex-wrap gap-x-4 gap-y-1 text-sm">{/* a line of figures: */}
      <span>{FEEDBACK_KINDS.praise.icon} {sums.praise} going well</span>{/* praise, */}
      <span>{FEEDBACK_KINDS.idea.icon} {sums.idea} ideas</span>{/* ideas, */}
      <span>{FEEDBACK_KINDS.worry.icon} {sums.worry} worries</span>{/* worries, */}
      <span>{sums.avgRating === null ? "No ratings" : `Average rating ${sums.avgRating} out of 5`}</span>{/* and the average rating. */}
    </p> // End of the line.
  ); // End of what's shown.
} // End of Figures.

// Shows the overview.
export default async function FeedbackOverviewPage() { // The page itself.
  const viewer = await requireAdmin(); // Only full admins with two-step sign-in.
  const supabase = await createClient(); // Connects to the database.
  const since = periodStart(2 * PERIOD_DAYS); // The start of the period before this one.
  const [areas, feedback] = await Promise.all([ // Reads two things at once:
    supabase.from("feedback_areas").select("id, grp, label, active").order("sort").order("label"), // every area (including hidden ones, for old feedback),
    supabase.from("feedback").select("id, area_id, about_name, given_by_name, given_by_roles, kind, rating, comment, status, admin_note, created_at").gte("created_at", since).order("created_at", { ascending: false }), // and the feedback from both periods they can read.
  ]); // End of the reads.
  const areaRows = (areas.data ?? []) as Area[]; // The areas.
  const rows = (feedback.data ?? []) as Row[]; // The feedback.

  // Shows one piece of feedback, with the form to update it.
  const item = (f: Row) => ( // Takes the feedback:
    <li key={f.id} className="rounded-xl border border-zinc-200 p-3">{/* a bordered box: */}
      <p className="text-sm">{/* its heading line: */}
        <strong>{FEEDBACK_KINDS[f.kind]?.icon} {f.given_by_name}</strong>{/* the symbol and who gave it, */}
        <span className="text-zinc-500"> ({f.given_by_roles || "no role"}), {plainDate(f.created_at)}{f.rating ? `, rated ${f.rating}/5` : ""}</span>{/* their role, when, and the rating. */}
      </p>{/* End of the heading line. */}
      <p className="mt-1 whitespace-pre-wrap text-sm">{f.comment}</p>{/* What they said. */}
      <details className="mt-2">{/* an open-and-close box for updating it: */}
        <summary className="cursor-pointer text-sm text-teal-800">{FEEDBACK_STATUS[f.status] ?? f.status}{f.admin_note ? ": has a note" : ""} (update)</summary>{/* where it's up to, and whether there's a note. */}
        <div className="mt-2">{/* the form: */}
          <ActionForm action={updateFeedback} submitLabel="Save">{/* updating it: */}
            <input type="hidden" name="id" value={f.id} />{/* (which feedback) */}
            <Select label="Where is this up to?" name="status" defaultValue={f.status}>{/* the stage drop-down: */}
              {Object.entries(FEEDBACK_STATUS).map(([value, label]) => ( // for each stage:
                <option key={value} value={value}>{label}</option> // an option.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
            <TextArea label="Private note (the person who gave it can't see this)" name="note" defaultValue={f.admin_note ?? ""} maxLength={4000} rows={2} />{/* the note box. */}
          </ActionForm>{/* End of the form. */}
        </div>{/* End of the form area. */}
      </details>{/* End of the update box. */}
    </li> // End of the item.
  ); // End of item.

  // Shows one area: its figures, its trend, and its latest feedback.
  const areaCard = (title: string, list: Row[], key: string) => { // Takes a title, the area's feedback, and a key.
    const { current, previous } = splitByPeriod(list, PERIOD_DAYS); // This period and the one before.
    const now = sumFeedback(current); // This period's sums.
    const before = sumFeedback(previous); // The period before's sums.
    const open = list.filter((f) => f.status !== "done"); // Feedback not yet done.
    return ( // Shows:
      <Card key={key} title={title} description={trendWords(now, before)} collapsible defaultOpen={open.length > 0}>{/* a card titled with the area and its trend: */}
        <Figures sums={now} />{/* this period's figures, */}
        {before.total > 0 && <p className="mt-1 text-xs text-zinc-500">The 90 days before: {before.praise} going well, {before.idea} ideas, {before.worry} worries.</p>}{/* the period before, for comparison, */}
        {open.length === 0 ? ( // if nothing is open:
          <p className="mt-3 text-sm text-zinc-500">Nothing waiting.</p> // says so,
        ) : ( // otherwise:
          <ul className="mt-3 space-y-2">{open.slice(0, 10).map(item)}</ul> // the latest 10 open pieces of feedback.
        )}{/* End of the choice. */}
        {open.length > 10 && <p className="mt-2 text-xs text-zinc-500">And {open.length - 10} more.</p>}{/* How many more are waiting. */}
      </Card> // End of the card.
    ); // End of what's shown.
  }; // End of areaCard.

  const personAreaIds = new Set(areaRows.filter((a) => a.grp === "people").map((a) => a.id)); // The "person" area ids.
  const aboutPeople = rows.filter((f) => personAreaIds.has(f.area_id)); // Feedback about people (only what this person may read).
  const peopleNames = [...new Set(aboutPeople.map((f) => f.about_name ?? "Unknown"))].sort(); // Each person with feedback, in name order.

  return ( // Shows:
    <Page // a page:
      title="Feedback" // titled "Feedback",
      intro={`What people are saying about the app, CLG's service and the people at CLG, over the last ${PERIOD_DAYS} days, compared with the ${PERIOD_DAYS} days before.`} // with a short explanation.
    >{/* (end of the page's settings) */}
      {rows.length === 0 && <Empty>No feedback yet.</Empty>}{/* "No feedback yet" when there's none. */}
      {(["app", "service"] as const).map((g) => { // For "The app" and "CLG's service":
        const groupAreas = areaRows.filter((a) => a.grp === g); // the areas in this group,
        const groupRows = rows.filter((f) => groupAreas.some((a) => a.id === f.area_id)); // and their feedback.
        return ( // Shows:
          <section key={g} className="space-y-3">{/* a section: */}
            <h2 className="text-lg font-semibold">{FEEDBACK_GROUPS[g]}</h2>{/* the group's heading, */}
            <Figures sums={sumFeedback(splitByPeriod(groupRows, PERIOD_DAYS).current)} />{/* the whole group's figures, */}
            {groupAreas // then each area:
              .filter((a) => a.active || groupRows.some((f) => f.area_id === a.id)) // (hidden areas only if they have feedback)
              .map((a) => areaCard(a.label, groupRows.filter((f) => f.area_id === a.id), a.id))}{/* as a card. */}
          </section> // End of the section.
        ); // End of what's shown.
      })}{/* End of the groups. */}

      {aboutPeople.length > 0 && ( // If they can read any feedback about people:
        <section className="space-y-3">{/* a section: */}
          <h2 className="text-lg font-semibold">{FEEDBACK_GROUPS.people}</h2>{/* its heading, */}
          <p className="text-sm text-zinc-600">Only you can see this part. The people named never see feedback about them.</p>{/* who can see it, */}
          {peopleNames.map((name) => areaCard(name, aboutPeople.filter((f) => (f.about_name ?? "Unknown") === name), `person-${name}`))}{/* a card per person. */}
        </section> // End of the section.
      )}{/* End of the people section. */}

      {viewer.level === "owner" && ( // Only for the owner:
        <Card title="Feedback areas (owner only)" description="Add an area, or rename or hide one. Hidden areas keep their old feedback." collapsible defaultOpen={false}>{/* a card for the areas: */}
          <ActionForm action={setFeedbackArea} submitLabel="Add area">{/* adding an area: */}
            <Select label="Group" name="grp" defaultValue="app">{/* the group drop-down: */}
              <option value="app">{FEEDBACK_GROUPS.app}</option>{/* the app, */}
              <option value="service">{FEEDBACK_GROUPS.service}</option>{/* or CLG's service. */}
            </Select>{/* End of the drop-down. */}
            <Field label="Area name" name="label" required maxLength={80} />{/* the name box. */}
          </ActionForm>{/* End of the form. */}
          <ul className="mt-4 space-y-3">{/* the existing areas: */}
            {areaRows.filter((a) => a.grp !== "people").map((a) => ( // for each area (except the person one):
              <li key={a.id} className="rounded-xl border border-zinc-200 p-3">{/* a box: */}
                <ActionForm action={setFeedbackArea} submitLabel="Save">{/* renaming or hiding it: */}
                  <input type="hidden" name="id" value={a.id} />{/* (which area) */}
                  <input type="hidden" name="grp" value={a.grp} />{/* (its group) */}
                  <Field label={`${FEEDBACK_GROUPS[a.grp]}: name`} name="label" defaultValue={a.label} required maxLength={80} />{/* the name box, */}
                  <Select label="Can people choose it?" name="active" defaultValue={a.active ? "yes" : "no"}>{/* shown or hidden: */}
                    <option value="yes">Yes</option>{/* shown, */}
                    <option value="no">No, hide it</option>{/* or hidden. */}
                  </Select>{/* End of the drop-down. */}
                </ActionForm>{/* End of the form. */}
              </li> // End of the box.
            ))}{/* End of the loop. */}
          </ul>{/* End of the list. */}
        </Card> // End of the card.
      )}{/* End of the owner part. */}
      <p className="text-sm"><Link href="/feedback" className="text-teal-800 underline underline-offset-4">Give feedback yourself</Link></p>{/* A link to the form. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of FeedbackOverviewPage.
