import { recordIncident, updateIncident, updatePrivacyRequest } from "@/app/actions/privacy";
import { ActionForm } from "@/components/action-form";
import { RoleTabs } from "@/components/role-tabs";
import { SectionShell } from "@/components/section-shell";
import { Card, Empty, Field, Select, TextArea, TextLink } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { REGIONS, REQUEST_STATUS_LABELS, plainDate, plainDateTime, requestKindLabel } from "@/lib/privacy";
import { createClient } from "@/lib/supabase/server";

// Privacy requests and the breach register (owner and operations admins).
// See docs/features/privacy-laws-baseline.md for the rules behind the dates.

const SECTIONS = [
  { id: "requests", label: "Privacy requests" },
  { id: "breaches", label: "Breach register" },
] as const;

type Request = {
  id: string;
  kind: string;
  details: string;
  status: string;
  received_at: string;
  due_on: string;
  acknowledged_at: string | null;
  extended_to: string | null;
  outcome: string | null;
  closed_at: string | null;
  account: { full_name: string } | null;
  student: { full_name: string } | null;
};

type Incident = {
  id: string;
  title: string;
  found_at: string;
  what_happened: string;
  data_involved: string | null;
  people_affected: number | null;
  children_affected: boolean;
  regions: string[];
  contained_at: string | null;
  serious_harm_likely: boolean | null;
  decision_reason: string | null;
  regulators_told_at: string | null;
  regulators_told: string | null;
  people_told_at: string | null;
  closed_at: string | null;
};
type Deadline = { id: string; decide_by: string; assess_by: string; next_step: string; decision_overdue: boolean };

export default async function AdminPrivacyPage({ searchParams }: PageProps<"/admin/privacy">) {
  const viewer = await requireAdmin();
  const params = await searchParams;
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "requests";
  const supabase = await createClient();

  const [requests, incidents, deadlines] = await Promise.all([
    supabase
      .from("privacy_requests")
      .select(
        "id, kind, details, status, received_at, due_on, acknowledged_at, extended_to, outcome, closed_at, account:accounts(full_name), student:students(full_name)",
      )
      .order("received_at", { ascending: false })
      .limit(200),
    supabase.from("privacy_incidents").select("*").order("found_at", { ascending: false }).limit(200),
    supabase.from("privacy_incident_deadlines").select("*"),
  ]);
  const requestRows = (requests.data ?? []) as unknown as Request[];
  const open = requestRows.filter((r) => !r.closed_at);
  const closed = requestRows.filter((r) => r.closed_at);
  const incidentRows = (incidents.data ?? []) as Incident[];
  const deadlineOf = new Map(((deadlines.data ?? []) as Deadline[]).map((d) => [d.id, d]));
  const openIncidents = incidentRows.filter((i) => !i.closed_at);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <>
      <RoleTabs roles={viewer.roles} active="admin" />
      <SectionShell
        basePath="/admin/privacy"
        label="Privacy"
        role="admin"
        section={section}
        sections={SECTIONS.map((s) => ({
          ...s,
          count: s.id === "requests" ? open.length || undefined : openIncidents.length || undefined,
        }))}
      >
        <p className="text-sm">
          <TextLink href="/admin?section=records">Back to privacy and records</TextLink>
        </p>

        {section === "requests" && (
          <>
            <Card
              title="Open requests"
              description="Reply by the due date (28 days, which meets every country's limit). Acknowledge complaints straight away. You can extend once, before the due date, if a request is complex: tell the person why."
            >
              {open.length === 0 ? (
                <Empty>No open requests.</Empty>
              ) : (
                <ul className="space-y-6">
                  {open.map((r) => {
                    const due = r.extended_to ?? r.due_on;
                    const late = due < today;
                    return (
                      <li key={r.id} className="border-b border-zinc-100 pb-6 last:border-0">
                        <p className="text-sm">
                          <strong>{requestKindLabel(r.kind)}</strong> from {r.account?.full_name ?? "a deleted account"}
                          {r.student ? ` about ${r.student.full_name}` : ""}.{" "}
                          <span className={late ? "font-semibold text-red-700" : "text-zinc-600"}>
                            {late ? "Overdue: was due" : "Due"} {plainDate(due)}
                          </span>
                          . {REQUEST_STATUS_LABELS[r.status]}
                          {r.acknowledged_at ? "" : " (not yet acknowledged)"}.
                        </p>
                        <p className="mt-1 mb-3 text-sm whitespace-pre-line text-zinc-700">{r.details}</p>
                        <ActionForm action={updatePrivacyRequest} submitLabel="Save">
                          <input type="hidden" name="id" value={r.id} />
                          <Select label="Status" name="status" defaultValue="in_progress">
                            <option value="in_progress">Being worked on (acknowledges it)</option>
                            <option value="done">Done</option>
                            <option value="refused">Refused (give the reason)</option>
                          </Select>
                          <TextArea
                            label="Answer to the person (shown to them)"
                            name="outcome"
                            maxLength={2000}
                            rows={2}
                            defaultValue={r.outcome ?? ""}
                          />
                          {!r.extended_to && (
                            <div className="grid gap-4 sm:grid-cols-2">
                              <Field label="Extend to (optional)" name="extend_to" type="date" />
                              <Field label="Why more time is needed" name="extension_reason" maxLength={500} />
                            </div>
                          )}
                        </ActionForm>
                      </li>
                    );
                  })}
                </ul>
              )}
            </Card>
            <Card collapsible defaultOpen={false} title={`Closed requests (${closed.length})`}>
              {closed.length === 0 ? (
                <Empty>None yet.</Empty>
              ) : (
                <ul className="space-y-2 text-sm">
                  {closed.map((r) => (
                    <li key={r.id}>
                      {plainDate(r.received_at)}: {requestKindLabel(r.kind)}, {r.account?.full_name ?? "deleted account"}.{" "}
                      {REQUEST_STATUS_LABELS[r.status]} {r.closed_at ? plainDate(r.closed_at) : ""}. {r.outcome}
                    </li>
                  ))}
                </ul>
              )}
              <p className="mt-3 text-xs text-zinc-500">Closed requests are kept for 7 years, then deleted automatically.</p>
            </Card>
          </>
        )}

        {section === "breaches" && (
          <>
            <Card
              title="Record a suspected breach"
              description="Record every suspected breach, even small ones (for example an email to the wrong parent). Start the record as soon as you know: the clocks start from when CLG found out."
            >
              <ActionForm action={recordIncident} submitLabel="Record it">
                <Field label="Short title" name="title" required maxLength={200} />
                <Field label="When CLG found out (Adelaide time)" name="found_at" type="datetime-local" required />
                <TextArea label="What happened" name="what_happened" required maxLength={4000} rows={3} />
                <TextArea
                  label="What information was involved"
                  name="data_involved"
                  maxLength={1000}
                  rows={2}
                  hint="For example: names and year levels; an address; learning needs notes."
                />
                <Field label="About how many people" name="people_affected" type="number" min={0} />
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" name="children_affected" /> Children&apos;s information is involved
                </label>
                <fieldset className="text-sm">
                  <legend className="mb-1 font-medium text-zinc-800">Where the people affected live</legend>
                  <div className="flex flex-wrap gap-4">
                    {REGIONS.map((r) => (
                      <label key={r.id} className="flex items-center gap-2">
                        <input type="checkbox" name="regions" value={r.id} defaultChecked={r.id === "AU"} /> {r.label}
                      </label>
                    ))}
                  </div>
                </fieldset>
              </ActionForm>
            </Card>

            {openIncidents.length === 0 ? (
              <Card title="Open breaches">
                <Empty>No open breaches.</Empty>
              </Card>
            ) : (
              openIncidents.map((i) => {
                const d = deadlineOf.get(i.id);
                return (
                  <Card key={i.id} title={i.title} description={`Found ${plainDateTime(i.found_at)}`}>
                    {d && (
                      <div className="mb-4 space-y-1 text-sm">
                        <p className={d.decision_overdue ? "font-semibold text-red-700" : ""}>
                          Decide whether to tell regulators by {plainDateTime(d.decide_by)} (72 hr: UK and EU rule; do
                          it this fast everywhere).
                        </p>
                        <p>Finish the assessment by {plainDateTime(d.assess_by)} at the latest (Australian 30-day limit).</p>
                        <p>
                          <strong>Next step:</strong> {d.next_step}.
                        </p>
                      </div>
                    )}
                    <p className="mb-2 text-sm whitespace-pre-line text-zinc-700">{i.what_happened}</p>
                    <p className="mb-4 text-xs text-zinc-500">
                      {i.data_involved ? `Information: ${i.data_involved}. ` : ""}
                      {i.people_affected != null ? `About ${i.people_affected} people. ` : ""}
                      {i.children_affected ? "Children affected. " : ""}
                      Regions: {i.regions.join(", ")}.
                      {i.decision_reason ? ` Decision: ${i.decision_reason}.` : ""}
                      {i.regulators_told ? ` Told: ${i.regulators_told}.` : ""}
                    </p>
                    {i.serious_harm_likely && !i.regulators_told_at && (
                      <ul className="mb-4 list-disc space-y-1 pl-5 text-sm">
                        {REGIONS.filter((r) => i.regions.includes(r.id)).map((r) => (
                          <li key={r.id}>
                            {r.label}: <TextLink href={r.url}>{r.regulator}</TextLink>
                          </li>
                        ))}
                      </ul>
                    )}
                    <ActionForm action={updateIncident} submitLabel="Save">
                      <input type="hidden" name="id" value={i.id} />
                      <Select label="What's happened" name="step" defaultValue="">
                        <option value="" disabled>
                          Choose one
                        </option>
                        {!i.contained_at && <option value="contained">It is contained</option>}
                        {i.serious_harm_likely === null && <option value="assessed_serious">Assessed: serious harm is likely</option>}
                        {i.serious_harm_likely === null && (
                          <option value="assessed_not_serious">Assessed: serious harm is not likely</option>
                        )}
                        {i.serious_harm_likely && !i.regulators_told_at && <option value="regulators">Regulators told</option>}
                        {i.serious_harm_likely && !i.people_told_at && <option value="people">People affected told</option>}
                        <option value="close">Close it</option>
                      </Select>
                      <TextArea
                        label="Note"
                        name="note"
                        maxLength={2000}
                        rows={2}
                        hint="The reason for a decision, which regulators were told, or what was learned (when closing)."
                      />
                    </ActionForm>
                  </Card>
                );
              })
            )}

            <Card collapsible defaultOpen={false} title={`Closed breaches (${incidentRows.length - openIncidents.length})`}>
              <ul className="space-y-2 text-sm">
                {incidentRows
                  .filter((i) => i.closed_at)
                  .map((i) => (
                    <li key={i.id}>
                      {plainDate(i.found_at)}: {i.title}. {i.serious_harm_likely ? "Notifiable." : "Not notifiable."}{" "}
                      {i.regulators_told ? `Told: ${i.regulators_told}.` : ""}
                    </li>
                  ))}
              </ul>
              <p className="mt-3 text-xs text-zinc-500">
                Kept for 7 years after closing (Canada needs at least 24 months), then deleted automatically. Records can&apos;t
                be deleted or changed once closed.
              </p>
            </Card>
          </>
        )}
      </SectionShell>
    </>
  );
}
