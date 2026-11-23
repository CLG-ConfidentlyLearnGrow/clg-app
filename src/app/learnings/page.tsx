// Summary: the Learnings page for tutors and admin staff (Carla, 22 Nov
// 2026). Anyone on staff can keep personal learnings: short notes on what
// they learned from their work. They can suggest one for the team. Carla or
// Emma (the owner and Operations admins) adapt a suggestion into a team
// learning, or decline it with a kind note. Every tutor and admin reads the
// team learnings. See docs/features/learnings.md.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty } from "@/components/ui"; // Shared page parts: card and "nothing yet" line.
import { FULL_ADMIN, getAdminLevel, needsTwoStep, requireViewer } from "@/lib/auth"; // The approver levels, the admin level, the two-step check, and signing in.
import { plainDate } from "@/lib/billing/money"; // Dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { staffRole } from "@/lib/training"; // Works out which dashboard the page belongs to.
import { DeclineLearningForm, LearningButton, LearningForm } from "./forms"; // The page's forms.

// One learning as the page reads it.
type Learning = { id: string; kind: "personal" | "team"; author_id: string | null; title: string; body: string; review_status: "none" | "suggested" | "adopted" | "declined"; review_note: string | null; created_at: string; updated_at: string }; // Its fields.

// The words for where a personal learning is up to.
const STATUS_WORDS: Record<Learning["review_status"], string> = { // status -> words:
  none: "", // not suggested: nothing shown,
  suggested: "Suggested for the team", // waiting for Carla or Emma,
  adopted: "Now a team learning", // adapted into a team learning,
  declined: "Not added this time", // declined (with any note shown below).
}; // End of the words.

// Shows a learning's words, keeping the person's line breaks.
function Words({ l }: { l: Learning }) { // Takes the learning.
  return ( // Shows:
    <div>{/* a block: */}
      <p className="font-medium">{l.title}</p>{/* the title, */}
      <p className="mt-1 text-sm whitespace-pre-line text-zinc-700">{l.body}</p>{/* and the learning. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of Words.

// Shows the page (tutors and admin staff).
export default async function LearningsPage({ searchParams }: PageProps<"/learnings">) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard"); // Not a tutor or admin: to their dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login not set up: sends them to set it up.
  const { as } = await searchParams; // Which dashboard it was opened from.
  const role = staffRole(as, viewer.roles); // The dashboard to show it in.
  const level = viewer.roles.includes("admin") ? await getAdminLevel() : null; // Their admin level, if any.
  const approver = level !== null && FULL_ADMIN.includes(level); // Whether they adapt suggestions (the owner and Operations admins).
  const supabase = await createClient(); // Connects to the database.
  const fields = "id, kind, author_id, title, body, review_status, review_note, created_at, updated_at"; // The fields to read.
  const [{ data: team }, { data: mine }, { data: waiting }] = await Promise.all([ // Reads three things at once:
    supabase.from("learnings").select(fields).eq("kind", "team").order("created_at", { ascending: false }).limit(200), // the team learnings,
    supabase.from("learnings").select(fields).eq("kind", "personal").eq("author_id", viewer.id).order("updated_at", { ascending: false }).limit(200), // their own personal learnings,
    approver // and, for approvers,
      ? supabase.from("learnings").select(fields).eq("kind", "personal").eq("review_status", "suggested").order("updated_at", { ascending: true }) // suggestions waiting (oldest first),
      : Promise.resolve({ data: [] }), // (nothing for anyone else).
  ]); // End of the reads.
  const teamList = (team ?? []) as Learning[]; // The team learnings.
  const own = (mine ?? []) as Learning[]; // Their own learnings.
  const suggestions = (waiting ?? []) as Learning[]; // Suggestions waiting (approvers only).
  const ids = [...new Set(suggestions.map((l) => l.author_id).filter((x): x is string => !!x))]; // Who wrote the suggestions.
  const names = new Map(((ids.length ? (await supabase.from("accounts").select("id, full_name").in("id", ids)).data : []) ?? []).map((a) => [a.id as string, a.full_name as string])); // Each writer's name, by id.
  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="learnings">{/* the dashboard frame, */}
      <div className="space-y-6">{/* the cards, with space between: */}
        {approver && ( // Approvers:
          <Card title="Suggested for the team" description="Learnings staff have suggested. Change the words so they work for everyone, then add them to the team learnings, or decline with a kind note. The person is told either way.">{/* the suggestions: */}
            {suggestions.length === 0 ? <Empty>No suggestions waiting.</Empty> : ( // None, or the list:
              <ul className="divide-y divide-zinc-100">{/* the list: */}
                {suggestions.map((l) => ( // Each suggestion:
                  <li key={l.id} className="space-y-3 py-4 first:pt-0">{/* a row: */}
                    <p className="text-xs text-zinc-500">From {names.get(l.author_id ?? "") ?? "a staff member"} · {plainDate(l.updated_at.slice(0, 10))}</p>{/* who and when, */}
                    <LearningForm mode="adopt" id={l.id} title={l.title} body={l.body} submitLabel="Add to team learnings" />{/* the adapt form (starts with their words), */}
                    <DeclineLearningForm id={l.id} />{/* and the decline form. */}
                  </li> // End of the row.
                ))}{/* End of each suggestion. */}
              </ul> // End of the list.
            )}{/* End of the choice. */}
          </Card> // End of the card.
        )}{/* End of the approver part. */}
        <Card title="Team learnings" description="What CLG has learned together. Every tutor and admin can read these.">{/* the team learnings: */}
          {teamList.length === 0 ? <Empty>No team learnings yet.</Empty> : ( // None, or the list:
            <ul className="divide-y divide-zinc-100">{/* the list: */}
              {teamList.map((l) => ( // Each team learning:
                <li key={l.id} className="space-y-2 py-3 first:pt-0">{/* a row: */}
                  {approver ? ( // Approvers can change or remove it:
                    <details>{/* an open-and-close box: */}
                      <summary className="cursor-pointer list-none"><Words l={l} /><span className="text-xs text-zinc-500 underline">Change or remove</span></summary>{/* the learning, and the link to open it, */}
                      <div className="mt-3 space-y-3">{/* the forms: */}
                        <LearningForm mode="team" id={l.id} title={l.title} body={l.body} submitLabel="Save changes" />{/* change it, */}
                        <LearningButton action="removeTeam" id={l.id} label="Remove from team learnings" />{/* or remove it. */}
                      </div>{/* End of the forms. */}
                    </details> // End of the box.
                  ) : <Words l={l} />}{/* Everyone else just reads it. */}
                </li> // End of the row.
              ))}{/* End of each team learning. */}
            </ul> // End of the list.
          )}{/* End of the choice. */}
          {approver && ( // Approvers can also add one directly:
            <details className="mt-4">{/* an open-and-close box: */}
              <summary className="cursor-pointer text-sm font-medium underline">Add a team learning</summary>{/* the link to open it, */}
              <div className="mt-3"><LearningForm mode="adopt" submitLabel="Add to team learnings" /></div>{/* and the form. */}
            </details> // End of the box.
          )}{/* End of the add part. */}
        </Card>{/* End of the card. */}
        <Card title="My learnings" description="Your own notes on what you have learned from your work. Only you can see them, unless you suggest one for the team. Please do not write students' or families' names.">{/* their own learnings: */}
          <div className="space-y-6">{/* a block: */}
            <LearningForm mode="mine" submitLabel="Save learning" />{/* the form for a new one, */}
            {own.length === 0 ? <Empty>You have not written any learnings yet.</Empty> : ( // None, or the list:
              <ul className="divide-y divide-zinc-100">{/* the list: */}
                {own.map((l) => ( // Each of their learnings:
                  <li key={l.id} className="space-y-2 py-3">{/* a row: */}
                    <Words l={l} />{/* the learning, */}
                    {STATUS_WORDS[l.review_status] && <p className="text-xs font-semibold text-zinc-500">{STATUS_WORDS[l.review_status]}</p>}{/* where it is up to, */}
                    {l.review_status === "declined" && l.review_note && <p className="rounded-xl bg-zinc-50 px-3 py-2 text-sm text-zinc-700">Note: {l.review_note}</p>}{/* the note, if declined, */}
                    {l.review_status !== "adopted" && l.review_status !== "suggested" && ( // Not locked: they can work on it:
                      <details>{/* an open-and-close box: */}
                        <summary className="cursor-pointer text-xs text-zinc-500 underline">Change, remove or suggest for the team</summary>{/* the link to open it, */}
                        <div className="mt-3 space-y-3">{/* the forms: */}
                          <LearningForm mode="mine" id={l.id} title={l.title} body={l.body} submitLabel="Save changes" />{/* change it, */}
                          <LearningButton action="suggest" id={l.id} label="Suggest for the team" />{/* suggest it, */}
                          <LearningButton action="remove" id={l.id} label="Remove" />{/* or remove it. */}
                        </div>{/* End of the forms. */}
                      </details> // End of the box.
                    )}{/* End of the choices. */}
                  </li> // End of the row.
                ))}{/* End of each learning. */}
              </ul> // End of the list.
            )}{/* End of the choice. */}
          </div>{/* End of the block. */}
        </Card>{/* End of the card. */}
      </div>{/* End of the cards. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of LearningsPage.
