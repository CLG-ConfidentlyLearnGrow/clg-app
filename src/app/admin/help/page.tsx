// Summary: the help desk (Carla, 16 Nov 2026). Every help chat this admin
// answers, in three lists: waiting for CLG (the longest waiting at the top,
// so nobody is left waiting), waiting for the family or person, and recently
// closed. Owner, operations and support admins answer general chats; owner,
// operations and finance admins answer billing and staff pay chats. The
// database decides which chats each admin sees. A button starts a new chat
// with a family or a person.
//
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, Table } from "@/components/ui"; // Shared page parts: card, empty note and table.
import { ANY_ADMIN, requireAdminLevel } from "@/lib/auth"; // The admin check, and the list of every admin level.
import { HELP_TOPICS, MISSING_ITEMS, type HelpChatRow } from "@/lib/help-chat"; // The topic and missing detail words, and the shape of one chat.
import { plainDateTime } from "@/lib/privacy"; // Dates and times in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The look of the "Start a chat" button.
const MAIN_BUTTON = "inline-flex min-h-11 items-center rounded-full bg-teal-700 px-5 text-sm font-semibold text-white transition hover:bg-teal-800"; // a solid, rounded bronze button.

// Shows the help desk.
export default async function HelpDeskPage() { // The page itself.
  const viewer = await requireAdminLevel(ANY_ADMIN); // Any admin with two-step sign-in (the database limits what each level sees).
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("help_chat_list", { p_desk: true }); // Reads every chat they answer.
  const chats = (data ?? []) as HelpChatRow[]; // The chats.
  const waitingOnClg = chats.filter((c) => c.status === "waiting_on_clg").sort((a, b) => a.last_message_at.localeCompare(b.last_message_at)); // Waiting for CLG, longest waiting first.
  const waitingOnThem = chats.filter((c) => c.status === "waiting_on_you"); // Waiting for the family or person, latest first.
  const closed = chats.filter((c) => c.status === "closed").slice(0, 30); // The 30 most recently active closed chats.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="help">{/* the admin dashboard frame, with Help chats open: */}
      <div className="space-y-6">{/* the page's parts, with space between: */}
        <p className="text-sm text-zinc-600">{/* a short explanation: */}
          Questions from families, students, tutors and staff. Reply in each chat; they get an email (never with the message itself) and see your reply in the app. Messages are checked for child safety like other writing.{/* what this page is, */}
        </p>{/* End of the explanation. */}
        <div><Link href="/admin/help/new" className={MAIN_BUTTON}>Start a chat with a family or person</Link></div>{/* the button to start a chat. */}
        <Card title={`Waiting for CLG (${waitingOnClg.length})`} description="Longest waiting at the top.">{/* the first list: */}
          <ChatTable chats={waitingOnClg} />{/* the chats waiting for CLG. */}
        </Card>{/* End of the card. */}
        <Card title={`Waiting for them (${waitingOnThem.length})`} description="CLG has replied or asked something, and is waiting for an answer." collapsible defaultOpen={waitingOnThem.length > 0}>{/* the second list: */}
          <ChatTable chats={waitingOnThem} />{/* the chats waiting for the family or person. */}
        </Card>{/* End of the card. */}
        <Card title="Recently closed" collapsible defaultOpen={false}>{/* the third list, closed to start: */}
          <ChatTable chats={closed} />{/* the closed chats. */}
        </Card>{/* End of the card. */}
      </div>{/* End of the page's parts. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of HelpDeskPage.

// A table of chats, each title linking to the chat.
function ChatTable({ chats }: { chats: HelpChatRow[] }) { // Takes the chats.
  if (chats.length === 0) return <Empty>None.</Empty>; // None: says so.
  return ( // Shows:
    <Table headings={["Chat", "Who", "About", "Last message", "Looked after by"]}>{/* a table with these headings: */}
      {chats.map((c) => ( // for each chat:
        <tr key={c.id} className="border-t border-zinc-100 align-top">{/* a row: */}
          <td className="py-2 pr-3">{/* the chat: */}
            {c.unread && <span className="mr-2 rounded-full bg-teal-700 px-2 py-0.5 text-xs font-semibold text-white">New</span>}{/* a "New" mark if unread, */}
            <Link href={`/help/${c.id}`} className="font-medium text-teal-800 underline underline-offset-4">{c.subject}</Link>{/* its title, linking to it, */}
            <span className="block text-xs text-zinc-500">{HELP_TOPICS[c.topic] ?? c.topic}{c.missing_item ? `: ${MISSING_ITEMS[c.missing_item] ?? c.missing_item}` : ""}</span>{/* and its topic (with the missing detail). */}
          </td>{/* End of the chat cell. */}
          <td className="py-2 pr-3">{c.started_by_clg ? `CLG (${c.started_by_name})` : c.started_by_name}</td>{/* who started it, */}
          <td className="py-2 pr-3">{c.student_name ?? "None"}</td>{/* the student (if any), */}
          <td className="py-2 pr-3 whitespace-nowrap">{plainDateTime(c.last_message_at)}</td>{/* when the latest message was written, */}
          <td className="py-2">{c.assigned_name ?? "Nobody yet"}</td>{/* and who looks after it. */}
        </tr> // End of the row.
      ))}{/* End of the loop. */}
    </Table> // End of the table.
  ); // End of what's shown.
} // End of ChatTable.
