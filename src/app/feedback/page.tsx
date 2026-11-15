// Summary: the "Feedback" page, open to everyone signed in (Carla, 15 Nov
// 2026). One short form: what it's about (the app, CLG's service, or a person
// at CLG), praise / an idea / a worry, an optional rating, and a comment.
// Feedback about a person goes privately to the Child Safety Officer (or the
// deputy if it's about the officer) and is never shown to that person. Below
// the form: the feedback this person has given and where it's up to.
//
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { giveFeedback } from "@/app/actions/feedback"; // The server action that saves feedback.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Empty, Page, Select, TextArea } from "@/components/ui"; // The card, "nothing yet" note, page frame, drop-down and multi-line box.
import { getAdminLevel, requireViewer } from "@/lib/auth"; // Makes sure someone is signed in, and reads their admin level.
import { FEEDBACK_GROUPS, FEEDBACK_KINDS, FEEDBACK_STATUS } from "@/lib/feedback"; // The group names, kinds and stages in words.
import { plainDate } from "@/lib/privacy"; // Dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// A feedback area, as the database gives it.
type Area = { id: string; grp: "app" | "service" | "people"; label: string }; // its short name, group and name.

// A piece of feedback this person gave, as the database gives it.
type Mine = { id: string; area_label: string; about_name: string | null; kind: string; rating: number | null; comment: string; status: string; created_at: string }; // what they can see of it.

// A person they can give feedback about, as the database gives it.
type Person = { account_id: string; full_name: string; job: string }; // the account, name and "Tutor" or "CLG staff".

// The style for a radio button, so it matches the app's other fields.
const tick = "h-4 w-4 shrink-0 accent-teal-700"; // small, in CLG's teal.

// Shows the Feedback page.
export default async function FeedbackPage() { // The page itself.
  const viewer = await requireViewer(); // Makes sure someone is signed in.
  const supabase = await createClient(); // Connects to the database.
  const level = await getAdminLevel(); // Their admin level, if any (for the overview link).
  const [areas, mine, people] = await Promise.all([ // Reads three things at once:
    supabase.from("feedback_areas").select("id, grp, label").eq("active", true).order("sort").order("label"), // the areas that can be picked,
    supabase.rpc("my_feedback"), // the feedback they've given,
    supabase.rpc("safety_concern_people_choices"), // and the people they can give feedback about.
  ]); // End of the reads.
  const areaRows = (areas.data ?? []) as Area[]; // The areas.
  const myRows = (mine.data ?? []) as Mine[]; // Their feedback.
  const personRows = (people.data ?? []) as Person[]; // The people.
  const canSeeOverview = level === "owner" || level === "operations"; // Full admins see the overview (the officer or deputy see feedback about people there too).
  const personArea = areaRows.find((a) => a.grp === "people"); // The "A person at CLG" area, if it's open.

  return ( // Shows:
    <Page // a page:
      title="Feedback" // titled "Feedback",
      intro="Tell us what's going well and what we could do better: about the app, about CLG, or about someone at CLG. It only takes a minute." // with a short explanation.
    >{/* (end of the page's settings) */}
      {canSeeOverview && ( // For full admins:
        <p className="rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm">{/* a small box: */}
          <Link href="/admin/feedback" className="font-medium text-teal-800 underline underline-offset-4">See all feedback, grouped by area</Link>{/* a link to the overview. */}
        </p> // End of the box.
      )}{/* End of that part. */}

      <p className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900">{/* a red note: */}
        Worried about a child&apos;s safety? Don&apos;t use this form.{" "}{/* safety worries go elsewhere, */}
        <Link href="/safety" className="font-semibold underline underline-offset-4">Go to Child safety</Link>.{/* with the link. */}
      </p>{/* End of the note. */}

      <Card title="Give feedback">{/* A card with the form: */}
        <ActionForm action={giveFeedback} submitLabel="Send feedback">{/* the form: */}
          <Select label="What is it about?" name="area" required defaultValue="">{/* the area drop-down, grouped: */}
            <option value="" disabled>Choose one</option>{/* a blank first option that can't be picked, */}
            {(["app", "service"] as const).map((g) => ( // for "The app" and "CLG's service":
              <optgroup key={g} label={FEEDBACK_GROUPS[g]}>{/* a group heading: */}
                {areaRows.filter((a) => a.grp === g).map((a) => ( // for each area in it:
                  <option key={a.id} value={a.id}>{a.label}</option> // an option.
                ))}{/* End of the loop. */}
              </optgroup> // End of the group.
            ))}{/* End of the groups. */}
            {personArea && personRows.length > 0 && ( // If they can give feedback about a person:
              <optgroup label={FEEDBACK_GROUPS.people}>{/* a group heading: */}
                <option value={personArea.id}>{personArea.label} (choose them below)</option>{/* the person option. */}
              </optgroup> // End of the group.
            )}{/* End of the person group. */}
          </Select>{/* End of the drop-down. */}

          {personArea && personRows.length > 0 && ( // If they can give feedback about a person:
            <div className="space-y-2 rounded-xl bg-zinc-50 p-4">{/* a shaded box: */}
              <p className="text-xs text-zinc-600">{/* when to fill it in and who sees it: */}
                Only if you chose &quot;{personArea.label}&quot;. This goes privately to CLG&apos;s Child Safety Officer. The person
                won&apos;t see it or be told who sent it, but CLG may contact you about it.{/* the privacy promise, */}
              </p>{/* End of the note. */}
              <Select label="Who is it about?" name="about" defaultValue="">{/* the person drop-down: */}
                <option value="">Choose someone</option>{/* a blank first option, */}
                {personRows.map((p) => ( // for each person:
                  <option key={p.account_id} value={p.account_id}>{p.full_name} ({p.job})</option> // an option with their name and job.
                ))}{/* End of the loop. */}
              </Select>{/* End of the drop-down. */}
            </div> // End of the box.
          )}{/* End of the person part. */}

          <fieldset className="space-y-2">{/* the kind question: */}
            <legend className="text-sm font-medium text-zinc-800">What kind of feedback is it?</legend>{/* its question, */}
            {Object.entries(FEEDBACK_KINDS).map(([value, k]) => ( // for each kind:
              <label key={value} className="flex items-center gap-2 text-sm">{/* an option: */}
                <input type="radio" name="kind" value={value} required className={tick} />{/* its radio button, */}
                <span>{k.icon} {k.label}</span>{/* its symbol and words. */}
              </label> // End of the option.
            ))}{/* End of the loop. */}
          </fieldset>{/* End of the kind question. */}

          <Select label="How would you rate it? (optional)" name="rating" defaultValue="">{/* the rating drop-down: */}
            <option value="">No rating</option>{/* no rating first, */}
            <option value="5">5: excellent</option>{/* five, */}
            <option value="4">4: good</option>{/* four, */}
            <option value="3">3: okay</option>{/* three, */}
            <option value="2">2: not great</option>{/* two, */}
            <option value="1">1: poor</option>{/* and one. */}
          </Select>{/* End of the drop-down. */}

          <TextArea label="Your feedback" name="comment" required minLength={3} maxLength={4000} rows={4} hint="What happened, what you liked, or what would make it better." />{/* the comment box. */}
        </ActionForm>{/* End of the form. */}
      </Card>{/* End of the card. */}

      <Card title="Your feedback" description="Only you and the people at CLG who handle it can see these." collapsible defaultOpen={myRows.length > 0}>{/* A card of their feedback: */}
        {myRows.length === 0 ? ( // If none:
          <Empty>None yet.</Empty> // says so.
        ) : ( // Otherwise:
          <ul className="space-y-3 text-sm">{/* the list: */}
            {myRows.map((f) => ( // for each piece of feedback:
              <li key={f.id} className="border-b border-zinc-100 pb-3 last:border-0">{/* a line: */}
                <p>{/* its heading line: */}
                  <strong>{FEEDBACK_KINDS[f.kind]?.icon} {f.about_name ?? f.area_label}</strong>{/* the symbol and what or who it was about, */}
                  <span className="text-zinc-500">, {plainDate(f.created_at)}: {FEEDBACK_STATUS[f.status] ?? f.status}</span>{/* when, and where it's up to. */}
                </p>{/* End of the heading line. */}
                <p className="mt-1 whitespace-pre-wrap text-zinc-700">{f.comment}</p>{/* What they said. */}
              </li> // End of the line.
            ))}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}
      <p className="text-xs text-zinc-500">Signed in as {viewer.fullName}. Feedback is kept with your name so CLG can follow up.</p>{/* A note that feedback isn't anonymous. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of FeedbackPage.
