// Summary: the "Help chat" page, open to everyone signed in (Carla, 16 Nov
// 2026). It lists the person's chats with CLG, newest activity first, with a
// "New" mark where CLG has replied and they have not read it yet, and a button
// to ask CLG a new question. Help desk admins also get a link to every chat
// they answer. Only the person's own chats show; the database enforces that.
//
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { Card, Empty, Page, TextLink } from "@/components/ui"; // The card, "nothing yet" note, page frame and text link.
import { ANY_ADMIN, getAdminLevel, requireViewer } from "@/lib/auth"; // Makes sure someone is signed in, reads their admin level, and the list of admin levels.
import { HELP_STATUS_FOR_MEMBER, HELP_TOPICS, type HelpChatRow } from "@/lib/help-chat"; // The words for stages and topics, and the shape of one chat in a list.
import { plainDateTime } from "@/lib/privacy"; // Dates and times in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The look of the main "Ask CLG a question" button.
const MAIN_BUTTON = "inline-flex min-h-11 items-center rounded-full bg-teal-700 px-5 text-sm font-semibold text-white transition hover:bg-teal-800"; // a solid, rounded bronze button.

// Shows the Help chat page.
export default async function HelpPage() { // The page itself.
  await requireViewer(); // Makes sure someone is signed in.
  const supabase = await createClient(); // Connects to the database.
  const level = await getAdminLevel(); // Their admin level, if any (for the help desk link).
  const { data } = await supabase.rpc("help_chat_list", { p_desk: false }); // Reads the chats they are in.
  const chats = (data ?? []) as HelpChatRow[]; // The chats.
  const open = chats.filter((c) => c.status !== "closed"); // The ones still open.
  const closed = chats.filter((c) => c.status === "closed"); // The closed ones.

  return ( // Shows:
    <Page // a page:
      title="Help chat" // titled "Help chat",
      intro="Ask CLG a question and talk it through here. CLG will reply as soon as it can. You will get an email when CLG replies, and the chat stays here so you can look back at it." // with a short explanation.
    >{/* (end of the page's settings) */}
      {level && ANY_ADMIN.includes(level) && ( // For admins:
        <p className="rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm">{/* a small box: */}
          <Link href="/admin/help" className="font-medium text-teal-800 underline underline-offset-4">Open the help desk (every chat CLG answers)</Link>{/* a link to the help desk. */}
        </p> // End of the box.
      )}{/* End of that part. */}

      <p className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900">{/* a red note: */}
        Worried about a child&apos;s safety? Do not use the help chat.{" "}{/* safety worries go elsewhere, */}
        <Link href="/safety" className="font-semibold underline underline-offset-4">Go to Child safety</Link>. If a child is in danger right now, call 000.{/* with the link, and 000 for emergencies. */}
      </p>{/* End of the note. */}

      <div>{/* The main button: */}
        <Link href="/help/new" className={MAIN_BUTTON}>Ask CLG a question</Link>{/* opens the new chat form. */}
      </div>{/* End of the button. */}

      <Card title="Your open chats">{/* A card of open chats: */}
        {open.length === 0 ? <Empty>No open chats.</Empty> : <ChatList chats={open} />}{/* the list, or a note when there are none. */}
      </Card>{/* End of the card. */}

      <Card title="Closed chats" description="Write in a closed chat any time to reopen it." collapsible defaultOpen={false}>{/* A card of closed chats, closed to start: */}
        {closed.length === 0 ? <Empty>None yet.</Empty> : <ChatList chats={closed} />}{/* the list, or a note when there are none. */}
      </Card>{/* End of the card. */}
      <p className="text-xs text-zinc-500">{/* small print: */}
        Only you and CLG&apos;s admins can read your chats. Messages are kept with your name and checked for child safety, like other writing in the app. If something in the app is broken, use <TextLink href="/report-problem">Report app issue</TextLink> instead.{/* who can read chats, and where app faults go. */}
      </p>{/* End of the small print. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of HelpPage.

// The list of chats, each linking to the chat.
function ChatList({ chats }: { chats: HelpChatRow[] }) { // Takes the chats.
  return ( // Shows:
    <ul className="divide-y divide-zinc-100">{/* a list with thin lines between: */}
      {chats.map((c) => ( // for each chat:
        <li key={c.id}>{/* a row: */}
          <Link href={`/help/${c.id}`} className="block py-3 hover:bg-zinc-50">{/* the whole row links to the chat: */}
            <span className="flex flex-wrap items-center gap-2">{/* the top line: */}
              {c.unread && <span className="rounded-full bg-teal-700 px-2 py-0.5 text-xs font-semibold text-white">New</span>}{/* a "New" mark if there is something unread, */}
              <strong className="text-zinc-900">{c.subject}</strong>{/* the title, */}
            </span>{/* end of the top line. */}
            <span className="mt-1 block text-sm text-zinc-600">{/* the second line: */}
              {HELP_TOPICS[c.topic] ?? c.topic}{c.student_name ? `, about ${c.student_name}` : ""}{/* the topic and the student, */}
              {" · "}{HELP_STATUS_FOR_MEMBER[c.status] ?? c.status}{/* where it is up to, */}
              {" · "}{plainDateTime(c.last_message_at)}{/* and when the latest message was written. */}
            </span>{/* end of the second line. */}
          </Link>{/* End of the link. */}
        </li> // End of the row.
      ))}{/* End of the loop. */}
    </ul> // End of the list.
  ); // End of what's shown.
} // End of ChatList.
