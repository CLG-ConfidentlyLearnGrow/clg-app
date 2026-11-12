// Summary: the "Your privacy" page: download your information, make requests, emails, and agreements.
//
import { makePrivacyRequest, setMarketingEmail } from "@/app/actions/privacy"; // The server actions for privacy requests and marketing emails.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Empty, Page, Select, Table, TextArea, TextLink } from "@/components/ui"; // The card, "nothing yet" note, page frame, drop-down, table, text box and link style.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { PRIVACY_REQUEST_KINDS, REQUEST_STATUS_LABELS, plainDate, requestKindLabel } from "@/lib/privacy"; // Request kinds and statuses, dates in words, and request names.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// "Your privacy": everyone's own privacy controls. Download your
// information, ask CLG to fix, delete or stop using it, complain, and turn
// marketing emails on or off. Not behind the agreement page, so a person can
// always reach it, including to withdraw consent.

// A privacy request as the database gives it.
type Request = {
  id: string; // its id,
  kind: string; // the kind of request,
  details: string; // the details,
  status: string; // where it's up to,
  received_at: string; // when it was received,
  due_on: string; // when it's due,
  extended_to: string | null; // a later due date (if extended),
  extension_reason: string | null; // why it was extended,
  outcome: string | null; // CLG's answer (if given),
  student: { full_name: string } | null; // and the child it's about (if any).
}; // End of the shape.

type Consent = { id: string; kind: string; given_at: string; withdrawn_at: string | null; student: { full_name: string } | null }; // An agreement: its kind, when given and withdrawn, and the child (if any).

const CONSENT_LABELS: Record<string, string> = { // Words for each kind of agreement:
  privacy_policy: "Privacy policy", // privacy policy,
  terms_of_service: "Terms of support", // terms of support,
  child_safe_policy: "Child safe policy", // child safe policy,
  parental_consent: "Parent or guardian consent", // parent or guardian consent,
  marketing_email: "News and offers by email", // marketing emails.
}; // End of the list.

// Shows the "Your privacy" page.
export default async function MyPrivacyPage() {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const supabase = await createClient(); // Connects to the database.
  const [requests, marketing, consents, links, own] = await Promise.all([ // Reads five things at once:
    supabase // their requests:
      .from("privacy_requests") // (from the privacy requests table)
      .select("id, kind, details, status, received_at, due_on, extended_to, extension_reason, outcome, student:students(full_name)") // with their details,
      .eq("account_id", viewer.id) // made by this person,
      .order("received_at", { ascending: false }), // newest first;
    supabase.rpc("my_marketing_email"), // whether marketing emails are on;
    supabase // their agreements:
      .from("consent_records") // (from the agreements table)
      .select("id, kind, given_at, withdrawn_at, student:students(full_name)") // with their details,
      .eq("account_id", viewer.id) // for this person,
      .order("given_at", { ascending: false }) // newest first,
      .limit(30), // at most 30;
    supabase.from("parent_student_links").select("student:students(id, full_name)").eq("parent_id", viewer.id).eq("can_manage", true), // the children they manage,
    supabase.from("students").select("id, full_name").eq("account_id", viewer.id), // and their own student profile (if any).
  ]); // End of the reads.
  const requestRows = (requests.data ?? []) as unknown as Request[]; // The requests.
  const consentRows = (consents.data ?? []) as unknown as Consent[]; // The agreements.
  const people = [ // Who a request can be about:
    ...((own.data ?? []) as { id: string; full_name: string }[]), // their own student profile,
    ...((links.data ?? []) as unknown as { student: { id: string; full_name: string } | null }[]) // and their children:
      .map((l) => l.student) // (each child)
      .filter((s): s is { id: string; full_name: string } => Boolean(s)), // leaving out missing ones.
  ]; // End of the list.

  return ( // Shows:
    <Page // a page:
      title="Your privacy" // titled "Your privacy",
      intro="See what CLG holds about you and your children, ask for changes, and choose what we send you. CLG replies to every request within 28 days." // with a short explanation.
    >{/* (end of the page's settings) */}
      <Card title="Download your information" description="One file with your account, your children's records, sessions, progress notes and consents you can see in the app.">{/* A card for downloading: */}
        <a // a link styled as a button:
          href="/my-privacy/download" // to the download,
          className="inline-block rounded-full bg-teal-700 px-5 py-2.5 text-sm font-medium text-white shadow-sm transition hover:bg-teal-900 hover:font-bold" // (the button style).
        >{/* (end of the link's settings) */}
          Download (JSON file){/* "Download (JSON file)". */}
        </a>{/* End of the link. */}
        <p className="mt-3 text-xs text-zinc-500">{/* A small grey note: */}
          The file opens in any text editor and can be moved to another service. Keep it somewhere safe: it holds your
          children&apos;s details.{/* to keep it somewhere safe. */}
        </p>{/* End of the note. */}
      </Card>{/* End of the card. */}

      <Card title="Ask CLG about your information" description="To see, fix or delete information, stop a use of it, withdraw consent, or make a complaint.">{/* A card for requests: */}
        <ActionForm action={makePrivacyRequest} submitLabel="Send to CLG">{/* a form that sends the request: */}
          <Select label="What would you like?" name="kind" required defaultValue="">{/* a drop-down of what they'd like: */}
            <option value="" disabled>{/* a blank first option that can't be picked: */}
              Choose one{/* "Choose one", */}
            </option>{/* (end of the option) */}
            {PRIVACY_REQUEST_KINDS.map((k) => ( // for each kind:
              <option key={k.id} value={k.id}>{/* an option: */}
                {k.label}{/* its words. */}
              </option> // (end of the option)
            ))}{/* End of the loop. */}
          </Select>{/* End of the drop-down. */}
          {people.length > 0 && ( // If they have children:
            <Select label="Who is it about?" name="student_id" defaultValue="">{/* a drop-down of who it's about: */}
              <option value="">Me (my own account)</option>{/* themselves, */}
              {people.map((p) => ( // for each child:
                <option key={p.id} value={p.id}>{/* an option: */}
                  {p.full_name}{/* their name. */}
                </option> // (end of the option)
              ))}{/* End of the loop. */}
            </Select> // End of the drop-down.
          )}{/* End of that part. */}
          <TextArea label="Details" name="details" required minLength={3} maxLength={2000} rows={4} />{/* The details box. */}
        </ActionForm>{/* End of the form. */}
        <ul className="mt-4 space-y-1 text-xs text-zinc-500">{/* A small grey list: */}
          {PRIVACY_REQUEST_KINDS.filter((k) => k.hint).map((k) => ( // for each kind with a hint:
            <li key={k.id}>{/* a list item: */}
              <strong>{k.label}:</strong> {k.hint}{/* its name and hint. */}
            </li> // (end of the item)
          ))}{/* End of the loop. */}
        </ul>{/* End of the list. */}
      </Card>{/* End of the card. */}

      <Card title="Your requests">{/* A card of their requests: */}
        {requestRows.length === 0 ? ( // if none:
          <Empty>No requests yet.</Empty> // says so.
        ) : ( // Otherwise:
          <ul className="space-y-4 text-sm">{/* a list: */}
            {requestRows.map((r) => ( // for each request:
              <li key={r.id} className="border-b border-zinc-100 pb-3 last:border-0">{/* a list item: */}
                <p>{/* a line: */}
                  <strong>{requestKindLabel(r.kind)}</strong>{/* the kind in bold, */}
                  {r.student ? ` about ${r.student.full_name}` : ""}: {REQUEST_STATUS_LABELS[r.status] ?? r.status}{/* who it's about, and where it's up to. */}
                </p>{/* End of the line. */}
                <p className="text-zinc-600">{/* A grey line: */}
                  Sent {plainDate(r.received_at)}.{" "}{/* when it was sent, */}
                  {r.status === "done" || r.status === "refused" // if it's finished,
                    ? "" // nothing,
                    : `CLG will reply by ${plainDate(r.extended_to ?? r.due_on)}.`}{/* otherwise when CLG will reply by, */}
                  {r.extended_to && r.extension_reason ? ` More time needed: ${r.extension_reason}` : ""}{/* and why more time is needed, if so. */}
                </p>{/* End of the line. */}
                {r.outcome && <p className="mt-1">CLG&apos;s answer: {r.outcome}</p>}{/* CLG's answer, if given. */}
                {r.status === "refused" && ( // If refused:
                  <p className="mt-1 text-xs text-zinc-500">{/* a small grey note: */}
                    If you&apos;re not happy with this, you can complain to the privacy regulator. In Australia that is
                    the <TextLink href="https://www.oaic.gov.au/privacy/privacy-complaints">OAIC</TextLink>.{/* how to complain to the OAIC. */}
                  </p> // End of the note.
                )}{/* End of that part. */}
              </li> // End of the list item.
            ))}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}

      <Card title="Emails from CLG">{/* A card for emails: */}
        <ActionForm action={setMarketingEmail} submitLabel="Save">{/* a form that saves the choice: */}
          <label className="flex items-start gap-2 text-sm">{/* a line holding: */}
            <input type="checkbox" name="marketing" defaultChecked={marketing.data === true} className="mt-1" />{/* a tick box for news and offers, */}
            <span>Send me CLG news and offers by email. (Off unless you turn it on.)</span>{/* and its words. */}
          </label>{/* End of the line. */}
          <p className="text-xs text-zinc-500">{/* A small grey note: */}
            Messages about sessions, invoices and safety are always sent, because they are part of CLG&apos;s support.{/* that service messages are always sent. */}
          </p>{/* End of the note. */}
        </ActionForm>{/* End of the form. */}
      </Card>{/* End of the card. */}

      <Card collapsible defaultOpen={false} title="What you have agreed to">{/* A closed card of agreements: */}
        {consentRows.length === 0 ? ( // if none:
          <Empty>Nothing recorded.</Empty> // says so.
        ) : ( // Otherwise:
          <Table headings={["Agreement", "Given", "Withdrawn"]}>{/* a table with these headings: */}
            {consentRows.map((c) => ( // for each agreement:
              <tr key={c.id}>{/* a row: */}
                <td>{/* a cell: */}
                  {CONSENT_LABELS[c.kind] ?? c.kind}{/* the agreement's name, */}
                  {c.student ? ` for ${c.student.full_name}` : ""}{/* and the child, if any. */}
                </td>{/* End of the cell. */}
                <td>{plainDate(c.given_at)}</td>{/* When given, */}
                <td>{c.withdrawn_at ? plainDate(c.withdrawn_at) : "-"}</td>{/* when withdrawn (or "-"). */}
              </tr> // End of the row.
            ))}{/* End of the loop. */}
          </Table> // End of the table.
        )}{/* End of the choice. */}
        <p className="mt-3 text-xs text-zinc-500">{/* A small grey note: */}
          To withdraw an agreement, use &quot;Withdraw a consent&quot; above. Read the{" "}{/* how to withdraw, and a link to */}
          <TextLink href="/privacy">privacy policy</TextLink>.{/* the privacy policy. */}
        </p>{/* End of the note. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of MyPrivacyPage.
