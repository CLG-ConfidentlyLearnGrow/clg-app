// Summary: one help chat (Carla, 16 Nov 2026). Shows every message in order,
// marks CLG's messages, and has a box to reply. Opening the page marks the
// chat as read. The person asking can close their chat when their question
// is answered (writing again reopens it). Help desk admins also see who is
// in the chat and can mark where it is up to and choose who looks after it.
// Only the people in the chat and the help desk can open it; the database
// enforces that, and anyone else sees "chat not found".
//
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { notFound } from "next/navigation"; // Shows the "not found" page.
import { replyHelpChat, updateHelpChat } from "@/app/actions/help-chat"; // The server actions for replying and updating.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { BackButton, Card, Page, Select, TextArea } from "@/components/ui"; // The back button, card, page frame, drop-down and multi-line box.
import { FINANCE, FRONT_DESK, getAdminLevel, requireViewer } from "@/lib/auth"; // The admin level groups, the level reader, and the sign-in check.
import { HELP_STATUS_FOR_CLG, HELP_STATUS_FOR_MEMBER, HELP_TOPICS, MISSING_ITEMS } from "@/lib/help-chat"; // The words for stages, topics and missing details.
import { plainDateTime } from "@/lib/privacy"; // Dates and times in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The chat, as the database gives it.
type Chat = { id: string; subject: string; topic: string; status: string; student_id: string | null; missing_item: string | null; started_by_name: string; started_by_clg: boolean; assigned_to: string | null; created_at: string }; // its details.

// One message, as the database gives it.
type Message = { id: string; author_id: string | null; author_name: string; from_clg: boolean; body: string; created_at: string }; // who wrote it, what and when.

// Shows the chat.
export default async function HelpChatPage({ params }: PageProps<"/help/[id]">) { // Reads the chat id from the address.
  const viewer = await requireViewer(); // Makes sure someone is signed in.
  const { id } = await params; // The chat's id.
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound(); // Not an id at all: not found.
  const supabase = await createClient(); // Connects to the database.
  const { data: chat } = await supabase.from("help_chats").select("id, subject, topic, status, student_id, missing_item, started_by_name, started_by_clg, assigned_to, created_at").eq("id", id).maybeSingle<Chat>(); // Reads the chat (only if they may see it).
  if (!chat) notFound(); // Not theirs (or no such chat): not found.
  await supabase.rpc("help_mark_read", { p_chat: id }); // Marks it as read now they have opened it.

  const level = await getAdminLevel(); // Their admin level, if any.
  const deskLevels = chat.topic === "billing" || chat.topic === "pay" ? FINANCE : FRONT_DESK; // The admin levels that answer this kind of chat.
  const { data: myRow } = await supabase.from("help_chat_members").select("account_id").eq("chat_id", id).eq("account_id", viewer.id).maybeSingle(); // Whether they are in the chat themselves.
  const isMember = !!myRow; // True when they are in the chat.
  const isClg = !isMember && level !== null && deskLevels.includes(level); // True when they answer it for CLG.

  const [messages, student, members, admins] = await Promise.all([ // Reads four things at once:
    supabase.from("help_messages").select("id, author_id, author_name, from_clg, body, created_at").eq("chat_id", id).order("created_at"), // the messages, oldest first,
    chat.student_id ? supabase.from("students").select("full_name").eq("id", chat.student_id).maybeSingle() : Promise.resolve({ data: null }), // the student's name (if any, and if they may see it),
    isClg ? supabase.from("help_chat_members").select("account_id").eq("chat_id", id) : Promise.resolve({ data: [] }), // who is in the chat (help desk only),
    isClg ? supabase.rpc("help_desk_admins", { p_topic: chat.topic }) : Promise.resolve({ data: [] }), // and the admins who can look after it (help desk only).
  ]); // End of the reads.
  const rows = (messages.data ?? []) as Message[]; // The messages.
  const studentName = (student.data as { full_name: string } | null)?.full_name; // The student's name, if known.
  const memberIds = ((members.data ?? []) as { account_id: string }[]).map((m) => m.account_id); // The members' ids.
  const { data: memberNames } = isClg && memberIds.length ? await supabase.from("accounts").select("id, full_name").in("id", memberIds) : { data: [] }; // Their names (help desk only).
  const adminRows = (admins.data ?? []) as { account_id: string; full_name: string }[]; // The admins who can look after it.
  const statusWords = isClg ? HELP_STATUS_FOR_CLG : HELP_STATUS_FOR_MEMBER; // The stage words that suit the reader.

  return ( // Shows:
    <Page title={chat.subject} intro={`${HELP_TOPICS[chat.topic] ?? chat.topic}${studentName ? `, about ${studentName}` : ""}. ${statusWords[chat.status] ?? chat.status}.`}>{/* the page, titled with the chat's title, with the topic, student and stage: */}
      <BackButton href={isClg ? "/admin/help" : "/help"}>{isClg ? "Back to the help desk" : "Back to your chats"}</BackButton>{/* the way back, */}

      {chat.missing_item && MISSING_ITEMS[chat.missing_item] && !isClg && ( // For the family, in a chat about a missing detail:
        <p className="rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm text-teal-900">{/* a helpful box: */}
          CLG needs the <strong>{MISSING_ITEMS[chat.missing_item].toLowerCase()}</strong>{studentName ? ` for ${studentName}` : ""}. You can add it from your{" "}{/* what is needed, */}
          <Link href="/dashboard" className="font-semibold underline underline-offset-4">dashboard</Link>, or ask here if you are not sure how.{/* and where to add it. */}
        </p> // End of the box.
      )}{/* End of the missing detail box. */}

      <Card>{/* A card with the messages: */}
        <ol className="space-y-4">{/* the messages, in order: */}
          {rows.map((m) => { // for each message:
            const mine = m.author_id === viewer.id; // whether they wrote it,
            return ( // shows:
              <li key={m.id} className={`rounded-xl px-4 py-3 ${m.from_clg ? "bg-teal-50" : "bg-zinc-50"} ${mine ? "ml-6" : "mr-6"}`}>{/* a bubble, CLG's in bronze, their own set to the right: */}
                <p className="text-xs text-zinc-600">{/* who and when: */}
                  <strong className="text-zinc-800">{mine ? "You" : m.author_name}</strong>{m.from_clg ? " (CLG)" : ""} · {plainDateTime(m.created_at)}{/* "You" or their name, "(CLG)" for CLG, and the time, */}
                </p>{/* End of who and when. */}
                <p className="mt-1 whitespace-pre-wrap text-sm text-zinc-900">{m.body}</p>{/* what they wrote, keeping line breaks. */}
              </li> // End of the bubble.
            ); // End of what's shown.
          })}{/* End of the loop. */}
        </ol>{/* End of the messages. */}
      </Card>{/* End of the card. */}

      <Card title={chat.status === "closed" ? "Write to reopen this chat" : "Reply"}>{/* A card with the reply box: */}
        <ActionForm action={replyHelpChat} submitLabel="Send">{/* the form: */}
          <input type="hidden" name="chat" value={chat.id} />{/* which chat, sent unseen, */}
          <TextArea label="Your message" name="body" required maxLength={4000} rows={4} hint={isClg ? "This is sent as CLG. Billing details should only go to the person who pays." : "CLG will get an email to say you have replied."} />{/* the message box. */}
        </ActionForm>{/* End of the form. */}
      </Card>{/* End of the card. */}

      {!isClg && chat.status !== "closed" && ( // For the person asking, while the chat is open:
        <Card title="Question answered?">{/* a card to close it: */}
          <ActionForm action={updateHelpChat} submitLabel="Close this chat">{/* the form: */}
            <input type="hidden" name="chat" value={chat.id} />{/* which chat, */}
            <input type="hidden" name="status" value="closed" />{/* closing it. */}
            <p className="text-sm text-zinc-600">You can write again any time to reopen it.</p>{/* a reassurance. */}
          </ActionForm>{/* End of the form. */}
        </Card> // End of the card.
      )}{/* End of the close part. */}

      {isClg && ( // For the help desk:
        <Card title="For CLG" description={`Started by ${chat.started_by_name}${chat.started_by_clg ? " (CLG)" : ""} on ${plainDateTime(chat.created_at)}.`}>{/* a card with CLG's tools: */}
          <p className="mb-4 text-sm text-zinc-700">{/* who is in the chat: */}
            <strong>In this chat:</strong> {((memberNames ?? []) as { id: string; full_name: string }[]).map((p) => p.full_name).join(", ") || "Nobody (they may have left CLG)"}{/* their names, or a note if none. */}
          </p>{/* End of the names. */}
          <ActionForm action={updateHelpChat} submitLabel="Save">{/* the form: */}
            <input type="hidden" name="chat" value={chat.id} />{/* which chat, */}
            <Select label="Where is it up to?" name="status" defaultValue={chat.status}>{/* the stage drop-down: */}
              {Object.entries(HELP_STATUS_FOR_CLG).map(([value, words]) => ( // for each stage:
                <option key={value} value={value}>{words}</option> // an option.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
            <Select label="Looked after by" name="assign" defaultValue={chat.assigned_to ?? ""}>{/* the admin drop-down: */}
              <option value="">Nobody yet</option>{/* nobody, */}
              {adminRows.map((a) => ( // for each admin who can look after it:
                <option key={a.account_id} value={a.account_id}>{a.full_name}</option> // an option.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
          </ActionForm>{/* End of the form. */}
        </Card> // End of the card.
      )}{/* End of the help desk part. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of HelpChatPage.
