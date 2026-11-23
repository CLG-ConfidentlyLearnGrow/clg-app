// Summary: the Meetings page (Carla, 22 Nov 2026). Tutors and admin staff
// book a meeting with Carla: they say what it is About, the Context and
// their Goal, how urgent it is, and suggest 2 or 3 times. Requests wait in
// one list, like a help desk, until Carla answers. Carla (CLG's owner) sees
// every request, urgent ones first, and confirms a time, offers another,
// answers without a meeting, or marks a meeting as held.
// See docs/features/meetings-with-carla.md.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty } from "@/components/ui"; // Shared page parts: card and "nothing yet" line.
import { getAdminLevel, needsTwoStep, requireViewer } from "@/lib/auth"; // The admin level, the two-step check, and signing in.
import { plainDateTime } from "@/lib/privacy"; // Dates and times in words, Adelaide time.
import { currentTime } from "@/lib/scheduling"; // The current time, read once per page request.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { staffRole } from "@/lib/training"; // Works out which dashboard the page belongs to.
import { AcceptTimeForm, AnswerMeetingForm, CancelMeetingForm, ConfirmMeetingForm, HeldMeetingForm, MeetingRequestForm } from "./forms"; // The page's forms.

// One request as the page reads it.
type Request = { id: string; requester_id: string; about: string; context: string; goal: string; urgency: "urgent" | "this_week" | "no_rush"; length_minutes: number; how: "online" | "phone" | "in_person"; suggested_times: string[]; status: "waiting" | "new_time" | "confirmed" | "answered" | "cancelled" | "held"; meeting_at: string | null; owner_note: string | null; cancel_note: string | null; created_at: string }; // Its fields.

// Words for each choice.
const URGENCY: Record<Request["urgency"], string> = { urgent: "Urgent", this_week: "This week", no_rush: "No rush" }; // urgency -> words.
const HOW: Record<Request["how"], string> = { online: "online", phone: "by phone", in_person: "in person" }; // how -> words.
const STATUS: Record<Request["status"], string> = { waiting: "Waiting for Carla", new_time: "Carla offered a different time", confirmed: "Confirmed", answered: "Answered without a meeting", cancelled: "Cancelled", held: "Held" }; // status -> words.

// A moment as the "YYYY-MM-DDTHH:MM" Adelaide clock time a date and time box uses.
function adelaideInput(iso: string): string { // Takes the moment.
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: "Australia/Adelaide", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date(iso)).map((x) => [x.type, x.value])); // Its parts in Adelaide.
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`; // Joins them up.
} // End of adelaideInput.

// One request's details: About, Context, Goal, and the times.
function Details({ r, name }: { r: Request; name?: string }) { // Takes the request and, for Carla, who sent it.
  return ( // Shows:
    <div className="space-y-1 text-sm">{/* a block: */}
      <p className="font-medium text-base">{r.about}{r.urgency === "urgent" && <span className="ml-2 rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-800">Urgent</span>}</p>{/* the title, with an urgent label, */}
      <p className="text-xs text-zinc-500">{name ? `${name} · ` : ""}{URGENCY[r.urgency]} · {r.length_minutes} minutes {HOW[r.how]} · sent {plainDateTime(r.created_at)}</p>{/* who, urgency, length, how and when sent, */}
      <p className="whitespace-pre-line text-zinc-700"><span className="font-semibold">Context: </span>{r.context}</p>{/* the context, */}
      <p className="whitespace-pre-line text-zinc-700"><span className="font-semibold">Goal: </span>{r.goal}</p>{/* the goal, */}
      <p className="text-zinc-700"><span className="font-semibold">Suggested times: </span>{r.suggested_times.map((t) => plainDateTime(t)).join("; ")}</p>{/* their times, */}
      <p className="font-semibold">{STATUS[r.status]}{r.meeting_at && (r.status === "confirmed" || r.status === "new_time" || r.status === "held") ? `: ${plainDateTime(r.meeting_at)}` : ""}</p>{/* where it is up to, with the time, */}
      {r.owner_note && <p className="rounded-xl bg-zinc-50 px-3 py-2 whitespace-pre-line text-zinc-700">Carla: {r.owner_note}</p>}{/* Carla's note, */}
      {r.cancel_note && <p className="text-zinc-500">Reason for cancelling: {r.cancel_note}</p>}{/* and any reason for cancelling. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of Details.

// Shows the page (tutors and admin staff).
export default async function MeetingsPage({ searchParams }: PageProps<"/meetings">) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard"); // Not a tutor or admin: to their dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login not set up: sends them to set it up.
  const { as } = await searchParams; // Which dashboard it was opened from.
  const role = staffRole(as, viewer.roles); // The dashboard to show it in.
  const isOwner = viewer.roles.includes("admin") && (await getAdminLevel()) === "owner"; // Whether they are Carla (CLG's owner), who answers requests.
  const supabase = await createClient(); // Connects to the database.
  const fields = "id, requester_id, about, context, goal, urgency, length_minutes, how, suggested_times, status, meeting_at, owner_note, cancel_note, created_at"; // The fields to read.
  const nowMs = currentTime(); // The current time, read once.
  const since = new Date(nowMs - 60 * 24 * 3600 * 1000).toISOString(); // 60 days ago, for closed requests.
  const { data } = isOwner // Reads:
    ? await supabase.from("meeting_requests").select(fields).or(`status.in.(waiting,new_time,confirmed),created_at.gte.${since}`).order("created_at", { ascending: true }).limit(300) // for Carla, every open request and the last 60 days,
    : await supabase.from("meeting_requests").select(fields).eq("requester_id", viewer.id).order("created_at", { ascending: false }).limit(50); // for anyone else, their own last 50.
  const all = (data ?? []) as Request[]; // The requests.
  const now = adelaideInput(new Date(nowMs).toISOString()); // Now, as a date and time box value (the earliest time allowed).
  const names = new Map(((isOwner && all.length ? (await supabase.from("accounts").select("id, full_name").in("id", [...new Set(all.map((r) => r.requester_id))])).data : []) ?? []).map((a) => [a.id as string, a.full_name as string])); // Each sender's name, by id (Carla only).
  const rank = { urgent: 0, this_week: 1, no_rush: 2 } as const; // Urgent first, then this week, then no rush.
  const waiting = all.filter((r) => r.status === "waiting").sort((a, b) => rank[a.urgency] - rank[b.urgency] || a.created_at.localeCompare(b.created_at)); // Waiting for Carla, urgent and oldest first.
  const booked = all.filter((r) => r.status === "new_time" || r.status === "confirmed").sort((a, b) => (a.meeting_at ?? "").localeCompare(b.meeting_at ?? "")); // Offered or confirmed, soonest first.
  const closed = all.filter((r) => r.status === "answered" || r.status === "cancelled" || r.status === "held").reverse(); // Closed, newest first.
  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="meetings">{/* the dashboard frame, */}
      <div className="space-y-6">{/* the cards, with space between: */}
        {isOwner ? ( // Carla:
          <>{/* her cards: */}
            <Card title="Meeting requests waiting" description="Urgent ones first. Choose one of their times to confirm it, offer a different time, or answer without a meeting when a short answer is enough. Please reply within 1 business day.">{/* the waiting list: */}
              {waiting.length === 0 ? <Empty>No requests waiting.</Empty> : ( // None, or the list:
                <ul className="divide-y divide-zinc-100">{waiting.map((r) => ( // Each waiting request:
                  <li key={r.id} className="space-y-4 py-4 first:pt-0">{/* a row: */}
                    <Details r={r} name={names.get(r.requester_id) ?? "A staff member"} />{/* its details, */}
                    <ConfirmMeetingForm id={r.id} options={r.suggested_times.map((t) => ({ value: adelaideInput(t), label: plainDateTime(t) }))} min={now} />{/* confirm or offer a time, */}
                    <details><summary className="cursor-pointer text-sm underline">Answer without a meeting, or cancel</summary><div className="mt-3 space-y-4"><AnswerMeetingForm id={r.id} /><CancelMeetingForm id={r.id} /></div></details>{/* and the other choices, tucked away. */}
                  </li> // End of the row.
                ))}</ul> // End of the list.
              )}{/* End of the choice. */}
            </Card>{/* End of the card. */}
            <Card title="Coming up" description="Confirmed meetings, and different times you offered that are waiting for an answer.">{/* the booked list: */}
              {booked.length === 0 ? <Empty>No meetings coming up.</Empty> : ( // None, or the list:
                <ul className="divide-y divide-zinc-100">{booked.map((r) => ( // Each booked request:
                  <li key={r.id} className="space-y-3 py-4 first:pt-0">{/* a row: */}
                    <Details r={r} name={names.get(r.requester_id) ?? "A staff member"} />{/* its details, */}
                    {r.status === "confirmed" && <HeldMeetingForm id={r.id} />}{/* "mark as held" once confirmed, */}
                    <details><summary className="cursor-pointer text-sm underline">Change the time or cancel</summary><div className="mt-3 space-y-4"><ConfirmMeetingForm id={r.id} options={r.suggested_times.map((t) => ({ value: adelaideInput(t), label: plainDateTime(t) }))} min={now} /><CancelMeetingForm id={r.id} /></div></details>{/* and changing or cancelling, tucked away. */}
                  </li> // End of the row.
                ))}</ul> // End of the list.
              )}{/* End of the choice. */}
            </Card>{/* End of the card. */}
            <Card title="Closed in the last 60 days" collapsible defaultOpen={false}>{/* the closed list: */}
              {closed.length === 0 ? <Empty>Nothing closed yet.</Empty> : <ul className="divide-y divide-zinc-100">{closed.map((r) => <li key={r.id} className="py-3"><Details r={r} name={names.get(r.requester_id) ?? "A staff member"} /></li>)}</ul>}{/* none, or each one. */}
            </Card>{/* End of the card. */}
          </>
        ) : ( // Everyone else:
          <>{/* their cards: */}
            <Card title="Book a meeting with Carla" description="Say what it is about, the context and your goal, so Carla can prepare. Carla replies within 1 business day, and straight away when it is urgent. A quick question may be better in Help chat.">{/* the request card: */}
              <MeetingRequestForm min={now} />{/* the form. */}
            </Card>{/* End of the card. */}
            <Card title="Your meeting requests">{/* their requests: */}
              {all.length === 0 ? <Empty>You have not asked for a meeting yet.</Empty> : ( // None, or the list:
                <ul className="divide-y divide-zinc-100">{all.map((r) => ( // Each request:
                  <li key={r.id} className="space-y-3 py-4 first:pt-0">{/* a row: */}
                    <Details r={r} />{/* its details, */}
                    {r.status === "new_time" && <AcceptTimeForm id={r.id} />}{/* accepting a different time, */}
                    {(r.status === "waiting" || r.status === "new_time" || r.status === "confirmed") && <details><summary className="cursor-pointer text-sm underline">Cancel this request</summary><div className="mt-3"><CancelMeetingForm id={r.id} /></div></details>}{/* and cancelling, while open. */}
                  </li> // End of the row.
                ))}</ul> // End of the list.
              )}{/* End of the choice. */}
            </Card>{/* End of the card. */}
          </>
        )}{/* End of the choice. */}
      </div>{/* End of the cards. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of MeetingsPage.
