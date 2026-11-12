// Summary: the admin privacy page: privacy requests from people, and the breach register.
//
import { recordIncident, updateIncident, updatePrivacyRequest } from "@/app/actions/privacy"; // The server actions for breaches and privacy requests.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, Field, Select, TextArea, TextLink } from "@/components/ui"; // The card, "nothing yet" note, input box, drop-down, text box and link style.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is an admin.
import { REGIONS, REQUEST_STATUS_LABELS, plainDate, plainDateTime, requestKindLabel } from "@/lib/privacy"; // Regions and regulators, request statuses, dates in words, and request names.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Privacy requests and the breach register (owner and operations admins).
// See docs/features/privacy-laws-baseline.md for the rules behind the dates.

const SECTIONS = [ // The page's sections:
  { id: "requests", label: "Privacy requests" }, // privacy requests,
  { id: "breaches", label: "Breach register" }, // breach register.
] as const; // End of the list (fixed).

// A privacy request as the database gives it.
type Request = {
  id: string; // its id,
  kind: string; // the kind,
  details: string; // the details,
  status: string; // where it's up to,
  received_at: string; // when received,
  due_on: string; // when due,
  acknowledged_at: string | null; // when acknowledged (if it was),
  extended_to: string | null; // a later due date (if extended),
  outcome: string | null; // the answer (if given),
  closed_at: string | null; // when closed (if it was),
  account: { full_name: string } | null; // who asked,
  student: { full_name: string } | null; // and the child it's about (if any).
}; // End of the shape.

// A suspected breach in the register.
type Incident = {
  id: string; // its id,
  title: string; // a short title,
  found_at: string; // when CLG found out,
  what_happened: string; // what happened,
  data_involved: string | null; // what information was involved,
  people_affected: number | null; // about how many people,
  children_affected: boolean; // whether children's information is involved,
  regions: string[]; // where the people live,
  contained_at: string | null; // when it was contained,
  serious_harm_likely: boolean | null; // whether serious harm is likely (or not decided yet),
  decision_reason: string | null; // the reason for that decision,
  regulators_told_at: string | null; // when regulators were told,
  regulators_told: string | null; // which regulators,
  people_told_at: string | null; // when the people were told,
  closed_at: string | null; // and when it was closed.
}; // End of the shape.
type Deadline = { id: string; decide_by: string; assess_by: string; next_step: string; decision_overdue: boolean }; // A breach's deadlines: decide by, assess by, the next step, and whether the decision is overdue.

// Shows the admin privacy page.
export default async function AdminPrivacyPage({ searchParams }: PageProps<"/admin/privacy">) {
  const viewer = await requireAdmin(); // Makes sure the person is an admin, and gets who they are.
  const params = await searchParams; // Reads the address settings.
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "requests"; // The section asked for (requests by default).
  const supabase = await createClient(); // Connects to the database.

  const [requests, incidents, deadlines] = await Promise.all([ // Reads three things at once:
    supabase // the requests:
      .from("privacy_requests") // (from the privacy requests table)
      .select( // (with these fields:)
        "id, kind, details, status, received_at, due_on, acknowledged_at, extended_to, outcome, closed_at, account:accounts(full_name), student:students(full_name)", // details and names,
      ) // (end of the fields)
      .order("received_at", { ascending: false }) // newest first,
      .limit(200), // at most 200;
    supabase.from("privacy_incidents").select("*").order("found_at", { ascending: false }).limit(200), // the breaches, newest first, at most 200;
    supabase.from("privacy_incident_deadlines").select("*"), // and each breach's deadlines.
  ]); // End of the reads.
  const requestRows = (requests.data ?? []) as unknown as Request[]; // The requests.
  const open = requestRows.filter((r) => !r.closed_at); // Open requests.
  const closed = requestRows.filter((r) => r.closed_at); // Closed requests.
  const incidentRows = (incidents.data ?? []) as Incident[]; // The breaches.
  const deadlineOf = new Map(((deadlines.data ?? []) as Deadline[]).map((d) => [d.id, d])); // Each breach's deadlines, by id.
  const openIncidents = incidentRows.filter((i) => !i.closed_at); // Open breaches.
  const today = new Date().toISOString().slice(0, 10); // Today's date.

  return ( // Shows:
    <>{/* (a group:) */}
      {/* The dashboard tabs and admin menu, with this page's own sections shown under its tab: */}
      <DashboardFrame // the dashboard frame:
        role="admin" // the admin dashboard,
        roles={viewer.roles} // the person's roles (for the tabs and numbers),
        current="records" // this page's tab open,
        sub={section} // on the open section,
        items={SECTIONS.map((s) => ({ ...s, href: `/admin/privacy?section=${s.id}`, count: s.id === "requests" ? open.length || undefined : openIncidents.length || undefined }))} // with this page's sections (and their numbers) under the tab.
      >{/* (end of the frame's settings) */}
        <p className="text-sm">{/* A line: */}
          <TextLink href="/admin?section=records">Back to privacy and records</TextLink>{/* with a link back. */}
        </p>{/* End of the line. */}

        {section === "requests" && ( // The requests section:
          <>{/* (a group:) */}
            <Card // a card:
              title="Open requests" // titled "Open requests",
              description="Reply by the due date (28 days, which meets every country's limit). Acknowledge complaints straight away. You can extend once, before the due date, if a request is complex: tell the person why." // with the reply rules.
            >{/* (end of the card's settings) */}
              {open.length === 0 ? ( // If none are open:
                <Empty>No open requests.</Empty> // says so.
              ) : ( // Otherwise:
                <ul className="space-y-6">{/* a list: */}
                  {open.map((r) => { // for each request:
                    const due = r.extended_to ?? r.due_on; // its due date (extended if so),
                    const late = due < today; // and whether it's late.
                    return ( // Shows:
                      <li key={r.id} className="border-b border-zinc-100 pb-6 last:border-0">{/* a list item: */}
                        <p className="text-sm">{/* a line: */}
                          <strong>{requestKindLabel(r.kind)}</strong> from {r.account?.full_name ?? "a deleted account"}{/* the kind and who asked, */}
                          {r.student ? ` about ${r.student.full_name}` : ""}.{" "}{/* who it's about, */}
                          <span className={late ? "font-semibold text-red-700" : "text-zinc-600"}>{/* the due date, in red if late: */}
                            {late ? "Overdue: was due" : "Due"} {plainDate(due)}{/* (the words) */}
                          </span>{/* (end of the date) */}
                          . {REQUEST_STATUS_LABELS[r.status]}{/* where it's up to, */}
                          {r.acknowledged_at ? "" : " (not yet acknowledged)"}.{/* and whether it's been acknowledged. */}
                        </p>{/* End of the line. */}
                        <p className="mt-1 mb-3 text-sm whitespace-pre-line text-zinc-700">{r.details}</p>{/* The details, keeping line breaks. */}
                        <ActionForm action={updatePrivacyRequest} submitLabel="Save">{/* A form that updates it: */}
                          <input type="hidden" name="id" value={r.id} />{/* which request (hidden), */}
                          <Select label="Status" name="status" defaultValue="in_progress">{/* a drop-down of status: */}
                            <option value="in_progress">Being worked on (acknowledges it)</option>{/* being worked on, */}
                            <option value="done">Done</option>{/* done, */}
                            <option value="refused">Refused (give the reason)</option>{/* refused. */}
                          </Select>{/* End of the drop-down. */}
                          <TextArea // The answer box:
                            label="Answer to the person (shown to them)" // its label,
                            name="outcome" // its field name,
                            maxLength={2000} // up to 2,000 characters,
                            rows={2} // two lines tall,
                            defaultValue={r.outcome ?? ""} // starting with any answer already given.
                          />{/* (end of the box) */}
                          {!r.extended_to && ( // If not extended yet:
                            <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
                              <Field label="Extend to (optional)" name="extend_to" type="date" />{/* the new due date, */}
                              <Field label="Why more time is needed" name="extension_reason" maxLength={500} />{/* and why. */}
                            </div> // End of the columns.
                          )}{/* End of that part. */}
                        </ActionForm>{/* End of the form. */}
                      </li> // End of the list item.
                    ); // End of what's shown for this request.
                  })}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of the choice. */}
            </Card>{/* End of the card. */}
            <Card collapsible defaultOpen={false} title={`Closed requests (${closed.length})`}>{/* A closed card of closed requests: */}
              {closed.length === 0 ? ( // if none:
                <Empty>None yet.</Empty> // says so.
              ) : ( // Otherwise:
                <ul className="space-y-2 text-sm">{/* a list: */}
                  {closed.map((r) => ( // for each:
                    <li key={r.id}>{/* a list item: */}
                      {plainDate(r.received_at)}: {requestKindLabel(r.kind)}, {r.account?.full_name ?? "deleted account"}.{" "}{/* when received, the kind and who, */}
                      {REQUEST_STATUS_LABELS[r.status]} {r.closed_at ? plainDate(r.closed_at) : ""}. {r.outcome}{/* the status, when closed, and the answer. */}
                    </li> // (end of the item)
                  ))}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of the choice. */}
              <p className="mt-3 text-xs text-zinc-500">Closed requests are kept for 7 years, then deleted automatically.</p>{/* How long they're kept. */}
            </Card>{/* End of the card. */}
          </> // (end of the group)
        )}{/* End of the requests section. */}

        {section === "breaches" && ( // The breaches section:
          <>{/* (a group:) */}
            <Card // a card:
              title="Record a suspected breach" // titled "Record a suspected breach",
              description="Record every suspected breach, even small ones (for example an email to the wrong parent). Start the record as soon as you know: the clocks start from when CLG found out." // with when to record one.
            >{/* (end of the card's settings) */}
              <ActionForm action={recordIncident} submitLabel="Record it">{/* A form that records it: */}
                <Field label="Short title" name="title" required maxLength={200} />{/* a short title, */}
                <Field label="When CLG found out (Adelaide time)" name="found_at" type="datetime-local" required />{/* when CLG found out, */}
                <TextArea label="What happened" name="what_happened" required maxLength={4000} rows={3} />{/* what happened, */}
                <TextArea // the information involved:
                  label="What information was involved" // (its label)
                  name="data_involved" // (its field name)
                  maxLength={1000} // up to 1,000 characters,
                  rows={2} // two lines tall,
                  hint="For example: names and year levels; an address; learning needs notes." // with examples.
                />{/* (end of the box) */}
                <Field label="About how many people" name="people_affected" type="number" min={0} />{/* About how many people, */}
                <label className="flex items-center gap-2 text-sm">{/* a line holding: */}
                  <input type="checkbox" name="children_affected" /> Children&apos;s information is involved{/* a tick box for children's information. */}
                </label>{/* End of the line. */}
                <fieldset className="text-sm">{/* A group of choices: */}
                  <legend className="mb-1 font-medium text-zinc-800">Where the people affected live</legend>{/* its heading, */}
                  <div className="flex flex-wrap gap-4">{/* a row that wraps: */}
                    {REGIONS.map((r) => ( // for each region:
                      <label key={r.id} className="flex items-center gap-2">{/* a line holding: */}
                        <input type="checkbox" name="regions" value={r.id} defaultChecked={r.id === "AU"} /> {r.label}{/* a tick box for it (Australia ticked to start). */}
                      </label> // End of the line.
                    ))}{/* End of the loop. */}
                  </div>{/* End of the row. */}
                </fieldset>{/* End of the group. */}
              </ActionForm>{/* End of the form. */}
            </Card>{/* End of the card. */}

            {openIncidents.length === 0 ? ( // If no breaches are open:
              <Card title="Open breaches">{/* a card: */}
                <Empty>No open breaches.</Empty>{/* says so. */}
              </Card> // End of the card.
            ) : ( // Otherwise:
              openIncidents.map((i) => { // for each open breach:
                const d = deadlineOf.get(i.id); // its deadlines.
                return ( // Shows:
                  <Card key={i.id} title={i.title} description={`Found ${plainDateTime(i.found_at)}`}>{/* a card with its title and when it was found: */}
                    {d && ( // if there are deadlines:
                      <div className="mb-4 space-y-1 text-sm">{/* a block: */}
                        <p className={d.decision_overdue ? "font-semibold text-red-700" : ""}>{/* a line (red if overdue): */}
                          Decide whether to tell regulators by {plainDateTime(d.decide_by)} (72 hr: UK and EU rule; do
                          it this fast everywhere).{/* when to decide by. */}
                        </p>{/* End of the line. */}
                        <p>Finish the assessment by {plainDateTime(d.assess_by)} at the latest (Australian 30-day limit).</p>{/* When to finish the assessment by. */}
                        <p>{/* A line: */}
                          <strong>Next step:</strong> {d.next_step}.{/* the next step. */}
                        </p>{/* End of the line. */}
                      </div> // End of the block.
                    )}{/* End of that part. */}
                    <p className="mb-2 text-sm whitespace-pre-line text-zinc-700">{i.what_happened}</p>{/* What happened, keeping line breaks. */}
                    <p className="mb-4 text-xs text-zinc-500">{/* A small grey line: */}
                      {i.data_involved ? `Information: ${i.data_involved}. ` : ""}{/* the information involved, */}
                      {i.people_affected != null ? `About ${i.people_affected} people. ` : ""}{/* how many people, */}
                      {i.children_affected ? "Children affected. " : ""}{/* whether children are affected, */}
                      Regions: {i.regions.join(", ")}.{/* the regions, */}
                      {i.decision_reason ? ` Decision: ${i.decision_reason}.` : ""}{/* the decision, */}
                      {i.regulators_told ? ` Told: ${i.regulators_told}.` : ""}{/* and who was told. */}
                    </p>{/* End of the line. */}
                    {i.serious_harm_likely && !i.regulators_told_at && ( // If serious harm is likely and regulators aren't told yet:
                      <ul className="mb-4 list-disc space-y-1 pl-5 text-sm">{/* a bulleted list: */}
                        {REGIONS.filter((r) => i.regions.includes(r.id)).map((r) => ( // for each region involved:
                          <li key={r.id}>{/* a list item: */}
                            {r.label}: <TextLink href={r.url}>{r.regulator}</TextLink>{/* the region and a link to its regulator. */}
                          </li> // (end of the item)
                        ))}{/* End of the loop. */}
                      </ul> // End of the list.
                    )}{/* End of that part. */}
                    <ActionForm action={updateIncident} submitLabel="Save">{/* A form that records the next step: */}
                      <input type="hidden" name="id" value={i.id} />{/* which breach (hidden), */}
                      <Select label="What's happened" name="step" defaultValue="">{/* a drop-down of what's happened: */}
                        <option value="" disabled>{/* a blank first option that can't be picked: */}
                          Choose one{/* "Choose one", */}
                        </option>{/* (end of the option) */}
                        {!i.contained_at && <option value="contained">It is contained</option>}{/* contained (if not yet), */}
                        {i.serious_harm_likely === null && <option value="assessed_serious">Assessed: serious harm is likely</option>}{/* serious harm likely (if not decided), */}
                        {i.serious_harm_likely === null && ( // if not decided:
                          <option value="assessed_not_serious">Assessed: serious harm is not likely</option> // serious harm not likely.
                        )}{/* (end of that option) */}
                        {i.serious_harm_likely && !i.regulators_told_at && <option value="regulators">Regulators told</option>}{/* regulators told (if needed), */}
                        {i.serious_harm_likely && !i.people_told_at && <option value="people">People affected told</option>}{/* people told (if needed), */}
                        <option value="close">Close it</option>{/* close it. */}
                      </Select>{/* End of the drop-down. */}
                      <TextArea // A note box:
                        label="Note" // its label,
                        name="note" // its field name,
                        maxLength={2000} // up to 2,000 characters,
                        rows={2} // two lines tall,
                        hint="The reason for a decision, which regulators were told, or what was learned (when closing)." // and a hint.
                      />{/* (end of the box) */}
                    </ActionForm>{/* End of the form. */}
                  </Card> // End of the card.
                ); // End of what's shown for this breach.
              }) // End of the loop.
            )}{/* End of the choice. */}

            <Card collapsible defaultOpen={false} title={`Closed breaches (${incidentRows.length - openIncidents.length})`}>{/* A closed card of closed breaches: */}
              <ul className="space-y-2 text-sm">{/* a list: */}
                {incidentRows // the breaches:
                  .filter((i) => i.closed_at) // closed ones only,
                  .map((i) => ( // for each:
                    <li key={i.id}>{/* a list item: */}
                      {plainDate(i.found_at)}: {i.title}. {i.serious_harm_likely ? "Notifiable." : "Not notifiable."}{" "}{/* when found, the title, and whether it was notifiable, */}
                      {i.regulators_told ? `Told: ${i.regulators_told}.` : ""}{/* and who was told. */}
                    </li> // (end of the item)
                  ))}{/* End of the loop. */}
              </ul>{/* End of the list. */}
              <p className="mt-3 text-xs text-zinc-500">{/* A small grey note: */}
                Kept for 7 years after closing (Canada needs at least 24 months), then deleted automatically. Records can&apos;t
                be deleted or changed once closed.{/* how long they're kept, and that they can't be changed. */}
              </p>{/* End of the note. */}
            </Card>{/* End of the card. */}
          </> // (end of the group)
        )}{/* End of the breaches section. */}
      </DashboardFrame>{/* End of the dashboard frame. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of AdminPrivacyPage.
