// Summary: a help desk admin starts a chat (Carla, 16 Nov 2026), for example
// to ask a family for a missing detail. Two ways to choose who it is with:
//   * about a student: pick the student, then tick which of their parents
//     (all ticked to start), the student themselves (if they have their own
//     login) and their tutors should be in the chat. The admin decides, so a
//     separated parent is never added without someone choosing to;
//   * with a tutor or staff member, not about a student.
// The address can carry ?student=<id>&item=<missing detail> so a link from
// the matching page lands with the student and title filled in. The
// database checks every person is allowed in the chat.
//
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { startHelpChatWith } from "@/app/actions/help-chat"; // The server action that starts the chat.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { BackButton, Card, Empty, Field, Select, TextArea } from "@/components/ui"; // The back button, card, empty note, text box, drop-down and multi-line box.
import { ANY_ADMIN, FINANCE, FRONT_DESK, requireAdminLevel } from "@/lib/auth"; // The admin check and the level groups.
import { HELP_TOPICS, MISSING_ITEMS, isMissingItem } from "@/lib/help-chat"; // The topic and missing detail words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Someone who could be in the chat.
type Person = { id: string; name: string; why: string; ticked: boolean }; // their account, name, how they are connected, and whether they start ticked.

// The style for a tick box, so it matches the app's other fields.
const tick = "h-4 w-4 shrink-0 accent-teal-700"; // small, in CLG's bronze.

// Reads one setting from the address (the first one if it appears twice).
function one(value: string | string[] | undefined): string | undefined { // Takes the address setting.
  return Array.isArray(value) ? value[0] : value; // The first value, or the only one.
} // End of one.

// Shows the form.
export default async function StartHelpChatPage({ searchParams }: PageProps<"/admin/help/new">) { // Reads the address's settings.
  const viewer = await requireAdminLevel(ANY_ADMIN); // Any admin with two-step sign-in (the database checks the topic).
  const sp = await searchParams; // The address's settings.
  const supabase = await createClient(); // Connects to the database.
  const studentId = one(sp.student); // The student chosen, if any.
  const item = one(sp.item); // The missing detail, if any.
  const knownItem = studentId && isMissingItem(item) ? item : undefined; // Used only with a student and a known detail.
  const isDesk = FRONT_DESK.includes(viewer.level); // Whether they answer general chats.
  const topics = Object.keys(HELP_TOPICS).filter((t) => (t === "billing" || t === "pay" ? FINANCE.includes(viewer.level) : isDesk)); // The topics this admin can start a chat about.

  const { data: studentRows } = await supabase.from("students").select("id, full_name").order("full_name"); // Every student they can see (for the drop-down).
  const students = (studentRows ?? []) as { id: string; full_name: string }[]; // The students.
  const student = students.find((s) => s.id === studentId); // The chosen student, if they can see them.

  let people: Person[] = []; // The people who could be in the chat.
  if (student) { // About a student: their parents, the student, and their tutors.
    const [links, self, tutors] = await Promise.all([ // Reads three things at once:
      supabase.from("parent_student_links").select("parent_id").eq("student_id", student.id), // the student's parents,
      supabase.from("students").select("account_id").eq("id", student.id).maybeSingle(), // the student's own login (if any),
      supabase.from("tutor_assignments").select("tutor_id, ends_on").eq("student_id", student.id), // and their tutors.
    ]); // End of the reads.
    const today = new Date().toISOString().slice(0, 10); // Today's date, for current tutors.
    const parentIds = ((links.data ?? []) as { parent_id: string }[]).map((l) => l.parent_id); // The parents' ids.
    const selfId = (self.data as { account_id: string | null } | null)?.account_id ?? null; // The student's own login, if any.
    const tutorIds = [...new Set(((tutors.data ?? []) as { tutor_id: string; ends_on: string | null }[]).filter((t) => !t.ends_on || t.ends_on >= today).map((t) => t.tutor_id))]; // The current tutors' ids, once each.
    const ids = [...parentIds, ...(selfId ? [selfId] : []), ...tutorIds]; // Everyone together.
    const { data: names } = ids.length ? await supabase.from("accounts").select("id, full_name").in("id", ids) : { data: [] }; // Their names.
    const nameOf = (id: string) => ((names ?? []) as { id: string; full_name: string }[]).find((n) => n.id === id)?.full_name ?? "Unknown"; // Finds one name.
    people = [ // The list, in this order:
      ...parentIds.map((id) => ({ id, name: nameOf(id), why: "Parent", ticked: true })), // parents (ticked),
      ...(selfId ? [{ id: selfId, name: nameOf(selfId), why: "The student (own login)", ticked: false }] : []), // the student (not ticked),
      ...tutorIds.map((id) => ({ id, name: nameOf(id), why: "Tutor", ticked: false })), // and tutors (not ticked).
    ]; // End of the list.
  } // End of the student case.
  const { data: staffRows } = student ? { data: [] } : await supabase.rpc("staff_list"); // Without a student: tutors and staff (owner and operations admins only).
  const staff = ((staffRows ?? []) as { account_id: string; full_name: string; is_tutor: boolean; admin_level: string | null }[]).filter((s) => s.account_id !== viewer.id); // Everyone but themselves.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="help">{/* the admin dashboard frame, with Help chats open: */}
      <div className="space-y-6">{/* the page's parts, with space between: */}
        <BackButton href="/admin/help">Back to the help desk</BackButton>{/* the way back, */}
        <Card title="1. Who is it with?">{/* the first step: */}
          <form method="get" className="space-y-3">{/* a small form that reloads this page with the student chosen: */}
            {knownItem && <input type="hidden" name="item" value={knownItem} />}{/* keeps the missing detail, */}
            <Select label="About a student (their family, the student, or their tutors)" name="student" defaultValue={student?.id ?? ""}>{/* the student drop-down: */}
              <option value="">Not about a student</option>{/* not about anyone, */}
              {students.map((s) => ( // for each student:
                <option key={s.id} value={s.id}>{s.full_name}</option> // an option.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
            <button type="submit" className="rounded-full border border-teal-700 px-4 py-2 text-sm font-medium text-teal-800 hover:bg-teal-50">Choose</button>{/* the button that reloads the page. */}
          </form>{/* End of the small form. */}
        </Card>{/* End of the first step. */}

        <Card title="2. Write the message">{/* the second step: */}
          <ActionForm action={startHelpChatWith} submitLabel="Start the chat">{/* the form: */}
            {student && <input type="hidden" name="student" value={student.id} />}{/* the student, sent unseen, */}
            {knownItem && <input type="hidden" name="item" value={knownItem} />}{/* and the missing detail. */}
            <fieldset className="space-y-2">{/* who is in the chat: */}
              <legend className="text-sm font-medium text-zinc-800">{student ? `People connected to ${student.full_name}` : "A tutor or staff member"}</legend>{/* the question, */}
              {student && people.length === 0 && <Empty>Nobody with a login is connected to this student yet.</Empty>}{/* a note when nobody can be added, */}
              {student && people.map((p) => ( // for each person connected to the student:
                <label key={p.id} className="flex items-center gap-2 text-sm">{/* a tick box: */}
                  <input type="checkbox" name="people" value={p.id} defaultChecked={p.ticked} className={tick} />{/* the box (parents start ticked), */}
                  <span>{p.name} <span className="text-zinc-500">({p.why})</span></span>{/* their name and how they are connected. */}
                </label> // End of the tick box.
              ))}{/* End of the loop. */}
              {!student && (staff.length === 0 ? <Empty>Only owner and operations admins can pick a tutor or staff member here. To ask a family, choose a student above.</Empty> : ( // without a student: a note, or the staff drop-down:
                <Select label="Person" name="people" defaultValue="">{/* the person drop-down: */}
                  <option value="" disabled>Choose someone</option>{/* a blank first option, */}
                  {staff.map((s) => ( // for each tutor or staff member:
                    <option key={s.account_id} value={s.account_id}>{s.full_name} ({s.admin_level ? "CLG staff" : "Tutor"})</option> // an option with their name and job.
                  ))}{/* End of the loop. */}
                </Select> // End of the drop-down.
              ))}{/* End of the staff part. */}
              {student && <p className="text-xs text-zinc-500">Only tick the people who should see this chat. Billing details should only go to the person who pays.</p>}{/* a privacy reminder. */}
            </fieldset>{/* End of who is in the chat. */}
            <Select label="What is it about?" name="topic" required defaultValue={knownItem ? "missing_info" : ""}>{/* the topic drop-down: */}
              <option value="" disabled>Choose one</option>{/* a blank first option, */}
              {topics.map((t) => ( // for each topic they can start:
                <option key={t} value={t}>{HELP_TOPICS[t]}</option> // an option.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
            <Field label="Short title" name="subject" required minLength={3} maxLength={120} defaultValue={knownItem ? `CLG needs: ${MISSING_ITEMS[knownItem]}` : ""} />{/* the title box, */}
            <TextArea label="Message" name="body" required maxLength={4000} rows={5} defaultValue={knownItem && student ? `Hello! To find the right tutor for ${student.full_name}, CLG needs the ${MISSING_ITEMS[knownItem].toLowerCase()}. You can add it from your dashboard in the app, or reply here if you have any questions.` : ""} hint="They get an email saying there is a new message (the email never includes the message itself)." />{/* the message box. */}
          </ActionForm>{/* End of the form. */}
        </Card>{/* End of the second step. */}
        <p className="text-xs text-zinc-500">Looking for an existing chat? <Link href="/admin/help" className="underline underline-offset-4">Go back to the help desk</Link>.</p>{/* a pointer back. */}
      </div>{/* End of the page's parts. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of StartHelpChatPage.
