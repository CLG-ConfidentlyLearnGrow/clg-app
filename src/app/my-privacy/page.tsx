import { makePrivacyRequest, setMarketingEmail } from "@/app/actions/privacy";
import { ActionForm } from "@/components/action-form";
import { Card, Empty, Page, Select, Table, TextArea, TextLink } from "@/components/ui";
import { requireViewer } from "@/lib/auth";
import { PRIVACY_REQUEST_KINDS, REQUEST_STATUS_LABELS, plainDate, requestKindLabel } from "@/lib/privacy";
import { createClient } from "@/lib/supabase/server";

// "Your privacy": everyone's own privacy controls. Download your
// information, ask CLG to fix, delete or stop using it, complain, and turn
// marketing emails on or off. Not behind the agreement page, so a person can
// always reach it, including to withdraw consent.

type Request = {
  id: string;
  kind: string;
  details: string;
  status: string;
  received_at: string;
  due_on: string;
  extended_to: string | null;
  extension_reason: string | null;
  outcome: string | null;
  student: { full_name: string } | null;
};

type Consent = { id: string; kind: string; given_at: string; withdrawn_at: string | null; student: { full_name: string } | null };

const CONSENT_LABELS: Record<string, string> = {
  privacy_policy: "Privacy policy",
  terms_of_service: "Terms of support",
  child_safe_policy: "Child safe policy",
  parental_consent: "Parent or guardian consent",
  marketing_email: "News and offers by email",
};

export default async function MyPrivacyPage() {
  const viewer = await requireViewer();
  const supabase = await createClient();
  const [requests, marketing, consents, links, own] = await Promise.all([
    supabase
      .from("privacy_requests")
      .select("id, kind, details, status, received_at, due_on, extended_to, extension_reason, outcome, student:students(full_name)")
      .eq("account_id", viewer.id)
      .order("received_at", { ascending: false }),
    supabase.rpc("my_marketing_email"),
    supabase
      .from("consent_records")
      .select("id, kind, given_at, withdrawn_at, student:students(full_name)")
      .eq("account_id", viewer.id)
      .order("given_at", { ascending: false })
      .limit(30),
    supabase.from("parent_student_links").select("student:students(id, full_name)").eq("parent_id", viewer.id).eq("can_manage", true),
    supabase.from("students").select("id, full_name").eq("account_id", viewer.id),
  ]);
  const requestRows = (requests.data ?? []) as unknown as Request[];
  const consentRows = (consents.data ?? []) as unknown as Consent[];
  const people = [
    ...((own.data ?? []) as { id: string; full_name: string }[]),
    ...((links.data ?? []) as unknown as { student: { id: string; full_name: string } | null }[])
      .map((l) => l.student)
      .filter((s): s is { id: string; full_name: string } => Boolean(s)),
  ];

  return (
    <Page
      title="Your privacy"
      intro="See what CLG holds about you and your children, ask for changes, and choose what we send you. CLG replies to every request within 28 days."
    >
      <Card title="Download your information" description="One file with your account, your children's records, sessions, progress notes and consents you can see in the app.">
        <a
          href="/my-privacy/download"
          className="inline-block rounded-full bg-teal-700 px-5 py-2.5 text-sm font-medium text-white shadow-sm transition hover:bg-teal-900 hover:font-bold"
        >
          Download (JSON file)
        </a>
        <p className="mt-3 text-xs text-zinc-500">
          The file opens in any text editor and can be moved to another service. Keep it somewhere safe: it holds your
          children&apos;s details.
        </p>
      </Card>

      <Card title="Ask CLG about your information" description="To see, fix or delete information, stop a use of it, withdraw consent, or make a complaint.">
        <ActionForm action={makePrivacyRequest} submitLabel="Send to CLG">
          <Select label="What would you like?" name="kind" required defaultValue="">
            <option value="" disabled>
              Choose one
            </option>
            {PRIVACY_REQUEST_KINDS.map((k) => (
              <option key={k.id} value={k.id}>
                {k.label}
              </option>
            ))}
          </Select>
          {people.length > 0 && (
            <Select label="Who is it about?" name="student_id" defaultValue="">
              <option value="">Me (my own account)</option>
              {people.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.full_name}
                </option>
              ))}
            </Select>
          )}
          <TextArea label="Details" name="details" required minLength={3} maxLength={2000} rows={4} />
        </ActionForm>
        <ul className="mt-4 space-y-1 text-xs text-zinc-500">
          {PRIVACY_REQUEST_KINDS.filter((k) => k.hint).map((k) => (
            <li key={k.id}>
              <strong>{k.label}:</strong> {k.hint}
            </li>
          ))}
        </ul>
      </Card>

      <Card title="Your requests">
        {requestRows.length === 0 ? (
          <Empty>No requests yet.</Empty>
        ) : (
          <ul className="space-y-4 text-sm">
            {requestRows.map((r) => (
              <li key={r.id} className="border-b border-zinc-100 pb-3 last:border-0">
                <p>
                  <strong>{requestKindLabel(r.kind)}</strong>
                  {r.student ? ` about ${r.student.full_name}` : ""}: {REQUEST_STATUS_LABELS[r.status] ?? r.status}
                </p>
                <p className="text-zinc-600">
                  Sent {plainDate(r.received_at)}.{" "}
                  {r.status === "done" || r.status === "refused"
                    ? ""
                    : `CLG will reply by ${plainDate(r.extended_to ?? r.due_on)}.`}
                  {r.extended_to && r.extension_reason ? ` More time needed: ${r.extension_reason}` : ""}
                </p>
                {r.outcome && <p className="mt-1">CLG&apos;s answer: {r.outcome}</p>}
                {r.status === "refused" && (
                  <p className="mt-1 text-xs text-zinc-500">
                    If you&apos;re not happy with this, you can complain to the privacy regulator. In Australia that is
                    the <TextLink href="https://www.oaic.gov.au/privacy/privacy-complaints">OAIC</TextLink>.
                  </p>
                )}
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card title="Emails from CLG">
        <ActionForm action={setMarketingEmail} submitLabel="Save">
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" name="marketing" defaultChecked={marketing.data === true} className="mt-1" />
            <span>Send me CLG news and offers by email. (Off unless you turn it on.)</span>
          </label>
          <p className="text-xs text-zinc-500">
            Messages about sessions, invoices and safety are always sent, because they are part of CLG&apos;s support.
          </p>
        </ActionForm>
      </Card>

      <Card collapsible defaultOpen={false} title="What you have agreed to">
        {consentRows.length === 0 ? (
          <Empty>Nothing recorded.</Empty>
        ) : (
          <Table headings={["Agreement", "Given", "Withdrawn"]}>
            {consentRows.map((c) => (
              <tr key={c.id}>
                <td>
                  {CONSENT_LABELS[c.kind] ?? c.kind}
                  {c.student ? ` for ${c.student.full_name}` : ""}
                </td>
                <td>{plainDate(c.given_at)}</td>
                <td>{c.withdrawn_at ? plainDate(c.withdrawn_at) : "-"}</td>
              </tr>
            ))}
          </Table>
        )}
        <p className="mt-3 text-xs text-zinc-500">
          To withdraw an agreement, use &quot;Withdraw a consent&quot; above. Read the{" "}
          <TextLink href="/privacy">privacy policy</TextLink>.
        </p>
      </Card>
    </Page>
  );
}
