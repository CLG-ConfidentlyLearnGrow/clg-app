// Summary: where full admins (owner and operations) write the "What's new"
// pop-ups (Carla, 15 Nov 2026). An update is a short title plus a list of
// changes. Each change is marked New, Updated or Removed and ticked for the
// dashboards it applies to, so parents only hear about parent changes, tutors
// about tutor changes, and so on. Drafts can be changed freely; publishing
// shows the update now or from a chosen day. Published updates can't be
// edited (people may have read them): take one back to a draft to fix it,
// and it shows again to everyone when republished.
//
import { // Brings in these server actions for "What's new":
  deleteWhatsNewItem, // removes a change,
  deleteWhatsNewNote, // deletes a draft,
  publishWhatsNewNote, // publishes a draft,
  saveWhatsNewItem, // adds or edits a change,
  saveWhatsNewNote, // starts or renames a draft,
  unpublishWhatsNewNote, // takes an update back to a draft.
} from "@/app/actions/whats-new"; // The server actions for "What's new".
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, Field, PageTitle, Select, TextArea } from "@/components/ui"; // The building blocks.
import { requireAdmin, type Role } from "@/lib/auth"; // Lets in only full admins with two-step sign-in, and the role type.
import { plainDate, plainDateTime } from "@/lib/privacy"; // Dates in words.
import { ROLE_THEME } from "@/lib/role-theme"; // Each dashboard's colours and name.
import { ROLE_ORDER } from "@/lib/roles"; // The usual order of dashboards.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { WHATS_NEW_KINDS } from "@/lib/whats-new"; // The kind labels.

// An update, as the database gives it.
type Note = { id: string; title: string; status: "draft" | "published"; show_from: string | null; created_at: string }; // its id, title, status, start time and when it was started.

// A change, as the database gives it.
type Item = { id: string; note_id: string; kind: string; roles: Role[]; body: string; sort: number }; // its id, update, kind, dashboards, words and place.

// The tick boxes for choosing dashboards, with the given ones already ticked.
function RoleTicks({ checked }: { checked: Role[] }) { // Takes the dashboards to tick.
  return ( // Shows:
    <fieldset className="space-y-1">{/* a group of tick boxes: */}
      <legend className="text-sm font-medium text-zinc-800">Which dashboards is this change for?</legend>{/* its question, */}
      <div className="flex flex-wrap gap-x-4 gap-y-1">{/* the boxes in a row: */}
        {ROLE_ORDER.map((r) => ( // for each dashboard:
          <label key={r} className="inline-flex items-center gap-1.5 text-sm">{/* a labelled box: */}
            <input type="checkbox" name="roles" value={r} defaultChecked={checked.includes(r)} />{/* the tick box, */}
            {ROLE_THEME[r].title}{/* and the dashboard's name. */}
          </label> // End of the box.
        ))}{/* End of the loop. */}
      </div>{/* End of the row. */}
    </fieldset> // End of the group.
  ); // End of what's shown.
} // End of RoleTicks.

// The drop-down for New, Updated or Removed.
function KindSelect({ value }: { value: string }) { // Takes the kind already chosen.
  return ( // Shows:
    <Select label="Kind of change" name="kind" defaultValue={value}>{/* a drop-down: */}
      {Object.entries(WHATS_NEW_KINDS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}{/* one option per kind. */}
    </Select> // End of the drop-down.
  ); // End of what's shown.
} // End of KindSelect.

// One change: its words and dashboards, and (in a draft) forms to edit or remove it.
function ItemRow({ item, editable }: { item: Item; editable: boolean }) { // Takes the change and whether it can be changed.
  return ( // Shows:
    <li className="rounded-xl border border-zinc-200 p-3">{/* a bordered box: */}
      <p className="flex items-start gap-2 text-sm">{/* the change: */}
        <span className={`mt-0.5 shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold ${WHATS_NEW_KINDS[item.kind]?.className ?? ""}`}>{WHATS_NEW_KINDS[item.kind]?.label ?? item.kind}</span>{/* New, Updated or Removed, */}
        <span className="whitespace-pre-wrap">{item.body}</span>{/* and what changed. */}
      </p>{/* End of the change. */}
      <p className="mt-1 text-xs text-zinc-500">Shown on: {ROLE_ORDER.filter((r) => item.roles.includes(r)).map((r) => ROLE_THEME[r].title).join(", ")}</p>{/* which dashboards see it. */}
      {editable && ( // In a draft:
        <details className="mt-2">{/* an open-and-close box: */}
          <summary className="cursor-pointer text-sm text-teal-800">Edit or remove</summary>{/* its heading, */}
          <div className="mt-2 space-y-4">{/* the forms: */}
            <ActionForm action={saveWhatsNewItem} submitLabel="Save change">{/* editing it: */}
              <input type="hidden" name="note" value={item.note_id} />{/* (which update) */}
              <input type="hidden" name="id" value={item.id} />{/* (which change) */}
              <KindSelect value={item.kind} />{/* the kind, */}
              <TextArea label="What changed?" name="body" defaultValue={item.body} required maxLength={500} rows={2} />{/* the words, */}
              <RoleTicks checked={item.roles} />{/* and the dashboards. */}
            </ActionForm>{/* End of the edit form. */}
            <ActionForm action={deleteWhatsNewItem} submitLabel="Remove this change">{/* removing it: */}
              <input type="hidden" name="id" value={item.id} />{/* (which change) */}
            </ActionForm>{/* End of the remove form. */}
          </div>{/* End of the forms. */}
        </details> // End of the box.
      )}{/* End of the draft part. */}
    </li> // End of the box.
  ); // End of what's shown.
} // End of ItemRow.

// Shows the page.
export default async function AdminWhatsNewPage() { // The page itself.
  const viewer = await requireAdmin(); // Only full admins with two-step sign-in.
  const supabase = await createClient(); // Connects to the database.
  const [notes, items] = await Promise.all([ // Reads two things at once:
    supabase.from("whats_new_notes").select("id, title, status, show_from, created_at").order("created_at", { ascending: false }).limit(50), // the latest 50 updates,
    supabase.from("whats_new_items").select("id, note_id, kind, roles, body, sort").order("sort").order("created_at"), // and their changes, in order.
  ]); // End of the reads.
  const noteRows = (notes.data ?? []) as Note[]; // The updates.
  const itemRows = (items.data ?? []) as Item[]; // The changes.
  const drafts = noteRows.filter((n) => n.status === "draft"); // Drafts.
  const published = noteRows.filter((n) => n.status === "published"); // Published updates.
  const now = new Date().toISOString(); // The time now, to tell waiting updates from showing ones.

  // Shows which dashboards will see an update, and how many changes each gets.
  const reach = (list: Item[]) => ROLE_ORDER // For each dashboard,
    .map((r) => [r, list.filter((i) => i.roles.includes(r)).length] as const) // counts its changes,
    .filter(([, n]) => n > 0) // keeps the ones with any,
    .map(([r, n]) => `${ROLE_THEME[r].title} (${n})`) // in words,
    .join(", "); // joined with commas.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="whats-new">{/* the dashboard frame: */}
      <PageTitle title="What's new" intro="Write the pop-up people see after an app update. Each person only sees the changes ticked for their own dashboards, once." role="admin" />{/* the heading, */}
      <div className="space-y-6">{/* the parts, spaced: */}
        <Card title="Start a new update" description="Give it a short title, like “Booking is quicker”. You'll add the changes next.">{/* starting a draft: */}
          <ActionForm action={saveWhatsNewNote} submitLabel="Start draft">{/* the form: */}
            <Field label="Title" name="title" required maxLength={120} />{/* the title box. */}
          </ActionForm>{/* End of the form. */}
        </Card>{/* End of the card. */}

        <h2 className="text-lg font-semibold">Drafts</h2>{/* The drafts heading. */}
        {drafts.length === 0 && <Empty>No drafts.</Empty>}{/* "No drafts" when there are none. */}
        {drafts.map((n) => { // For each draft:
          const list = itemRows.filter((i) => i.note_id === n.id); // its changes,
          return ( // shows:
            <Card key={n.id} title={n.title} description={list.length ? `Will show on: ${reach(list)}` : "No changes yet"} collapsible>{/* a card: */}
              {list.length > 0 && <ul className="space-y-2">{list.map((i) => <ItemRow key={i.id} item={i} editable />)}</ul>}{/* its changes, each editable, */}
              <div className="mt-5 space-y-5">{/* the forms: */}
                <details open={list.length === 0}>{/* adding a change (open when there are none): */}
                  <summary className="cursor-pointer text-sm font-medium text-teal-800">Add a change</summary>{/* its heading, */}
                  <div className="mt-3">{/* the form: */}
                    <ActionForm action={saveWhatsNewItem} submitLabel="Add change">{/* adding it: */}
                      <input type="hidden" name="note" value={n.id} />{/* (which update) */}
                      <KindSelect value="added" />{/* the kind, */}
                      <TextArea label="What changed?" name="body" required maxLength={500} rows={2} hint="One or two plain sentences. Say what people can do now, not how it was built." />{/* the words, */}
                      <RoleTicks checked={[]} />{/* and the dashboards. */}
                    </ActionForm>{/* End of the form. */}
                  </div>{/* End of the form area. */}
                </details>{/* End of adding a change. */}
                <details>{/* renaming: */}
                  <summary className="cursor-pointer text-sm font-medium text-teal-800">Rename</summary>{/* its heading, */}
                  <div className="mt-3">{/* the form: */}
                    <ActionForm action={saveWhatsNewNote} submitLabel="Save title">{/* the rename form: */}
                      <input type="hidden" name="id" value={n.id} />{/* (which update) */}
                      <Field label="Title" name="title" defaultValue={n.title} required maxLength={120} />{/* the title box. */}
                    </ActionForm>{/* End of the form. */}
                  </div>{/* End of the form area. */}
                </details>{/* End of renaming. */}
                {list.length > 0 && ( // Once it has changes:
                  <div className="rounded-xl border border-zinc-200 bg-zinc-50 p-4">{/* a shaded box for publishing: */}
                    <ActionForm action={publishWhatsNewNote} submitLabel="Publish">{/* the publish form: */}
                      <input type="hidden" name="id" value={n.id} />{/* (which update) */}
                      <Field label="Start showing on (optional)" name="showOn" type="date" hint="Leave empty to show it now. A later day starts at midnight, Adelaide time. Once published, it can't be edited unless you take it back to a draft." />{/* the start day. */}
                    </ActionForm>{/* End of the form. */}
                  </div> // End of the box.
                )}{/* End of publishing. */}
                <ActionForm action={deleteWhatsNewNote} submitLabel="Delete draft">{/* deleting the draft: */}
                  <input type="hidden" name="id" value={n.id} />{/* (which update) */}
                </ActionForm>{/* End of the form. */}
              </div>{/* End of the forms. */}
            </Card> // End of the card.
          ); // End of what's shown.
        })}{/* End of the drafts. */}

        <h2 className="text-lg font-semibold">Published</h2>{/* The published heading. */}
        {published.length === 0 && <Empty>Nothing published yet.</Empty>}{/* "Nothing published" when there's none. */}
        {published.map((n) => { // For each published update:
          const list = itemRows.filter((i) => i.note_id === n.id); // its changes,
          const waiting = (n.show_from ?? "") > now; // whether its start day is still to come,
          return ( // shows:
            <Card key={n.id} title={n.title} description={`${waiting ? "Starts showing" : "Showing since"} ${n.show_from ? (waiting ? plainDateTime(n.show_from) : plainDate(n.show_from)) : ""}. On: ${reach(list)}`} collapsible defaultOpen={false}>{/* a closed card with when and where it shows: */}
              <ul className="space-y-2">{list.map((i) => <ItemRow key={i.id} item={i} editable={false} />)}</ul>{/* its changes (not editable), */}
              <div className="mt-5">{/* and: */}
                <ActionForm action={unpublishWhatsNewNote} submitLabel="Take back to a draft">{/* taking it back: */}
                  <input type="hidden" name="id" value={n.id} />{/* (which update) */}
                  <p className="text-sm text-zinc-600">This hides it straight away. After fixing it, publish again and everyone on those dashboards sees it fresh.</p>{/* what that does. */}
                </ActionForm>{/* End of the form. */}
              </div>{/* End of the form area. */}
            </Card> // End of the card.
          ); // End of what's shown.
        })}{/* End of the published updates. */}
      </div>{/* End of the parts. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of AdminWhatsNewPage.
