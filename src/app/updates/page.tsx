// Summary: the End-of-day updates page for admin staff (Carla, 22 Nov
// 2026). Each day they do admin work, admin staff send a short update in dot
// points: what they did, what went well, and what did not go well. They see
// their own updates and a reminder for any day with office hours but no
// update. CLG's owner also sees everyone's updates and marks them as read.
// See docs/features/end-of-day-updates.md.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty } from "@/components/ui"; // Shared page parts: card and "nothing yet" line.
import { getAdminLevel, needsTwoStep, requireViewer } from "@/lib/auth"; // Reads the admin level, checks two-step login, and makes sure someone is signed in.
import { plainDate } from "@/lib/billing/money"; // Dates in words.
import { adelaideToday } from "@/lib/billing/run"; // Today's date in Adelaide.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { DayUpdateForm, MarkReadForm } from "./forms"; // The update form and the owner's "mark as read" button.

// One update as the page reads it.
type DayUpdate = { id: string; account_id: string; work_date: string; did: string; went_well: string | null; not_well: string | null; owner_read_at: string | null }; // Its fields.

// A date a number of days before another (both "YYYY-MM-DD").
function daysBefore(day: string, n: number): string { // Takes the day and how many days back.
  const d = new Date(`${day}T12:00:00Z`); // The day at midday (so time zones never change the date).
  d.setUTCDate(d.getUTCDate() - n); // Goes back that many days.
  return d.toISOString().slice(0, 10); // Hands back "YYYY-MM-DD".
} // End of daysBefore.

// Shows one list of dot points (one per line), or nothing if empty.
function Points({ label, text }: { label: string; text: string | null }) { // Takes the heading and the text.
  const lines = (text ?? "").split("\n").map((l) => l.replace(/^\s*[-•*]\s*/, "").trim()).filter(Boolean); // Each line, without any dot the person typed.
  if (lines.length === 0) return null; // Nothing written: shows nothing.
  return ( // Shows:
    <div>{/* a block: */}
      <p className="text-xs font-semibold tracking-wide text-zinc-500 uppercase">{label}</p>{/* the heading, small and grey, */}
      <ul className="mt-1 list-disc space-y-0.5 pl-5 text-sm">{lines.map((l, i) => <li key={i}>{l}</li>)}</ul>{/* and the dot points. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of Points.

// One update, with its three lists.
function UpdateView({ u, name }: { u: DayUpdate; name?: string }) { // Takes the update and, for the owner, who sent it.
  return ( // Shows:
    <li className="space-y-2 py-3 first:pt-0">{/* a row: */}
      <p className="font-medium">{name ? `${name} · ` : ""}{plainDate(u.work_date)}{u.owner_read_at ? "" : name ? " · New" : ""}</p>{/* who (for the owner), the day, and "New" if unread, */}
      <Points label="What I did" text={u.did} />{/* what they did, */}
      <Points label="What went well" text={u.went_well} />{/* what went well, */}
      <Points label="What did not go well" text={u.not_well} />{/* and what did not. */}
    </li> // End of the row.
  ); // End of what's shown.
} // End of UpdateView.

// Shows the page (admin staff).
export default async function DayUpdatesPage({ searchParams }: PageProps<"/updates">) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("admin")) redirect("/dashboard"); // Not admin staff: goes to the dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login not set up: sends them to set it up.
  const isOwner = (await getAdminLevel()) === "owner"; // Whether they are CLG's owner (who reads everyone's updates).
  const params = await searchParams; // Reads the address settings.
  const today = adelaideToday(); // Today in Adelaide.
  const oldest = daysBefore(today, 7); // The oldest day an update can be sent for.
  const chosen = typeof params.day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(params.day) && params.day >= oldest && params.day <= today ? params.day : today; // The day being written (from a reminder link, or today).
  const supabase = await createClient(); // Connects to the database.
  const [{ data: mine }, { data: missing }, { data: all }] = await Promise.all([ // Reads three things at once:
    supabase.from("admin_day_updates").select("id, account_id, work_date, did, went_well, not_well, owner_read_at").eq("account_id", viewer.id).order("work_date", { ascending: false }).limit(14), // their own last 14 updates,
    supabase.rpc("my_missing_day_updates"), // the days with office hours but no update,
    isOwner // and, for the owner,
      ? supabase.from("admin_day_updates").select("id, account_id, work_date, did, went_well, not_well, owner_read_at").neq("account_id", viewer.id).gte("work_date", daysBefore(today, 30)).order("work_date", { ascending: false }).limit(200) // everyone else's updates from the last 30 days,
      : Promise.resolve({ data: [] }), // (nothing for anyone else).
  ]); // End of the reads.
  const own = (mine ?? []) as DayUpdate[]; // Their own updates.
  const gaps = ((missing ?? []) as string[]).filter(Boolean); // The days still missing an update.
  const others = (all ?? []) as DayUpdate[]; // Everyone else's updates (owner only).
  const names = new Map(((others.length ? (await supabase.from("accounts").select("id, full_name").in("id", [...new Set(others.map((u) => u.account_id))])).data : []) ?? []).map((a) => [a.id as string, a.full_name as string])); // Each sender's name, by id.
  const unread = others.filter((u) => !u.owner_read_at); // The owner's unread updates.
  const earlier = own.find((u) => u.work_date === chosen); // An update already sent for the chosen day, if any.
  const role = "admin" as const; // This page sits in the admin dashboard.
  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="updates">{/* the dashboard frame, */}
      <div className="space-y-6">{/* the cards, with space between: */}
        <Card title="Send your end-of-day update" description="Each day you do admin work for CLG, send a short update in dot points: what you did, what went well, and what did not go well. Carla reads them. You can correct an update for up to 7 days.">{/* the update card: */}
          {gaps.length > 0 && ( // Days with office hours but no update:
            <p className="mb-4 rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-900">{/* an amber note: */}
              You logged office hours but have not sent an update for {gaps.map((g, i) => <span key={g}>{i > 0 ? ", " : ""}<a className="underline" href={`/updates?day=${g}`}>{plainDate(g)}</a></span>)}.{/* each missing day, as a link that opens it. */}
            </p> // End of the note.
          )}{/* End of the reminder. */}
          <DayUpdateForm key={chosen} day={chosen} min={oldest} max={today} did={earlier?.did} wentWell={earlier?.went_well} notWell={earlier?.not_well} />{/* the form (fresh for each day). */}
        </Card>{/* End of the update card. */}
        {isOwner && ( // The owner:
          <Card title="Updates from admin staff" description="The last 30 days, newest first. New ones are counted on the menu until you mark them as read.">{/* everyone's updates: */}
            {others.length === 0 ? <Empty>No updates from admin staff yet.</Empty> : ( // None, or the list:
              <div className="space-y-4">{/* a block: */}
                {unread.length > 0 && <MarkReadForm ids={unread.map((u) => u.id)} />}{/* the "mark as read" button, when any are new, */}
                <ul className="divide-y divide-zinc-100">{others.map((u) => <UpdateView key={u.id} u={u} name={names.get(u.account_id) ?? "A staff member"} />)}</ul>{/* and each update. */}
              </div> // End of the block.
            )}{/* End of the choice. */}
          </Card> // End of the card.
        )}{/* End of the owner part. */}
        <Card title="Your recent updates" collapsible defaultOpen={false}>{/* their own updates: */}
          {own.length === 0 ? <Empty>You have not sent any updates yet.</Empty> : <ul className="divide-y divide-zinc-100">{own.map((u) => <UpdateView key={u.id} u={u} />)}</ul>}{/* none, or each one. */}
        </Card>{/* End of the card. */}
      </div>{/* End of the cards. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of DayUpdatesPage.
