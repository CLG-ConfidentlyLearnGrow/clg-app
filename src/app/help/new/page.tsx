// Summary: the "Ask CLG a question" form (Carla, 16 Nov 2026). Anyone signed
// in picks what the question is about, optionally which child (or student)
// it is about, gives it a short title and writes the first message. The
// matching page's "Ask the family" notice links here as
// /help/new?student=<id>&item=<missing detail>, which fills in the topic,
// the child and the title, so the family only has to write their question.
// Only children the person is connected to are offered; the database checks
// that again when the chat is saved.
//
import { startHelpChat } from "@/app/actions/help-chat"; // The server action that starts the chat.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { BackButton, Card, Field, Page, Select, TextArea } from "@/components/ui"; // The back button, card, text box, page frame, drop-down and multi-line box.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { HELP_TOPICS, MISSING_ITEMS, isMissingItem, topicsFor } from "@/lib/help-chat"; // The topic and missing detail words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// A student the person may ask about, as the database gives it.
type Student = { id: string; full_name: string; connection: "self" | "child" | "student" }; // the student, their name, and how the person is connected.

// Reads one setting from the address (the first one if it appears twice).
function one(value: string | string[] | undefined): string | undefined { // Takes the address setting.
  return Array.isArray(value) ? value[0] : value; // The first value, or the only one.
} // End of one.

// Shows the form.
export default async function NewHelpChatPage({ searchParams }: PageProps<"/help/new">) { // Reads the address's settings.
  const viewer = await requireViewer(); // Makes sure someone is signed in.
  const sp = await searchParams; // The address's settings.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("help_my_students"); // The students they may ask about.
  const students = (data ?? []) as Student[]; // The students.
  const isStaff = viewer.roles.includes("tutor") || viewer.roles.includes("admin"); // Whether they are a tutor or admin (for the staff pay topic).
  const askedStudent = one(sp.student); // The student from the address, if any.
  const student = students.find((s) => s.id === askedStudent); // That student, only if they may ask about them.
  const item = one(sp.item); // The missing detail from the address, if any.
  const knownItem = student && isMissingItem(item) ? item : undefined; // Used only when it is known and the student is theirs.
  const askedTopic = one(sp.topic); // A topic from the address, if any.
  const topic = knownItem ? "missing_info" : askedTopic && askedTopic in HELP_TOPICS ? askedTopic : ""; // The topic to start on.
  const subject = knownItem ? `Question about: ${MISSING_ITEMS[knownItem]}` : ""; // The title to start with.

  return ( // Shows:
    <Page title="Ask CLG a question" intro="Tell us what you need help with. CLG will reply in the app and send you an email when there is a reply.">{/* the page and its explanation: */}
      <BackButton href="/help">Back to your chats</BackButton>{/* the way back, */}
      <Card>{/* a card with the form: */}
        <ActionForm action={startHelpChat} submitLabel="Send to CLG">{/* the form: */}
          {knownItem && <input type="hidden" name="item" value={knownItem} />}{/* the missing detail, passed on unseen when it came from the matching notice, */}
          <Select label="What is it about?" name="topic" required defaultValue={topic}>{/* the topic drop-down: */}
            <option value="" disabled>Choose one</option>{/* a blank first option that cannot be picked, */}
            {topicsFor(isStaff).map((t) => ( // for each topic they can pick:
              <option key={t} value={t}>{HELP_TOPICS[t]}</option> // an option.
            ))}{/* End of the loop. */}
          </Select>{/* End of the drop-down. */}

          {students.length > 0 && ( // If there are students they could ask about:
            <Select label="Who is it about? (optional)" name="student" defaultValue={student?.id ?? ""}>{/* the student drop-down: */}
              <option value="">Not about one child or student</option>{/* not about anyone in particular, */}
              {students.map((s) => ( // for each student:
                <option key={s.id} value={s.id}>{s.connection === "self" ? `Me (${s.full_name})` : s.full_name}</option> // an option ("Me" for themselves).
              ))}{/* End of the loop. */}
            </Select> // End of the drop-down.
          )}{/* End of the student part. */}

          <Field label="Short title" name="subject" required minLength={3} maxLength={120} defaultValue={subject} hint="For example: Changing session time, or Question about: School." />{/* the title box, */}
          <TextArea label="Your message" name="body" required maxLength={4000} rows={5} hint={knownItem ? `Ask anything about the ${MISSING_ITEMS[knownItem].toLowerCase()} CLG needs, for example where to add it in the app or why CLG needs it.` : "Write as much as you like. Please do not include medical details here; CLG will ask privately if needed."} />{/* the message box, with help that fits. */}
        </ActionForm>{/* End of the form. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of NewHelpChatPage.
