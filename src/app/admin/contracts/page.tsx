// Summary: the Contracts page for admins (Carla, 17 Nov 2026). The owner and
// Operations admins send employment contracts to staff and see where each
// one is up to; Finance admins can look and record the Xero step. Opening a
// contract shows its exact wording, the signature record, each document
// acknowledged, the pay sent since (backup evidence of acceptance), and the
// Xero self-setup step once it is signed.
// See docs/features/employment-contracts.md.
//
import type { ReactNode } from "react"; // The type for "anything that can be shown".
import { ContractText } from "@/components/contract-text"; // Shows a contract's wording.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { BackButton, Card, Empty, SubHeading, Table, TextLink } from "@/components/ui"; // Shared page parts.
import { FULL_ADMIN, requireAdminLevel } from "@/lib/auth"; // The owner-and-Operations group, and the admin check.
import { CONTRACT_STATUS_NAMES, CONTRACT_TYPE_NAMES, EMPLOYMENT_NAMES, documentLinks, type ContractDocument, type ContractStatus, type ContractType, type Employment } from "@/lib/employment-contracts"; // Contract words, and the document link swap list.
import { shortDate } from "@/lib/scheduling"; // Shows a date in a short, friendly way.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { SendContractForm, WithdrawContractForm, XeroInviteForm, type SendStaff, type SendTemplate } from "./forms"; // The admin forms.
import { MarkOutsideWorkSeenForm, OUTSIDE_WORK_KINDS, type OutsideWork } from "@/components/outside-work-forms"; // The owner's "mark as seen" form, and the kinds of outside role in words.

// One contract, as read from the database.
type Contract = { // Its fields:
  id: string; // its id,
  account_id: string | null; // the staff member,
  staff_name: string; // their name when sent,
  staff_email: string; // their email when sent,
  contract_type: ContractType; // the kind of contract,
  template_version: number; // the template version,
  employment: Employment; // casual, part-time or full-time,
  title: string; // the title,
  filled_values: Record<string, string>; // the gaps and their values,
  body: string; // the wording as sent,
  body_sha256: string; // its fingerprint,
  statements: string[]; // the documents to acknowledge,
  status: ContractStatus; // where it is up to,
  sent_at: string; // when it was sent,
  sent_by_name: string; // who sent it,
  signed_at: string | null; // when it was signed,
  signed_name: string | null; // the typed signature,
  pay_notice_shown: boolean; // whether the pay notice was shown,
  completed_at: string | null; // when it was completed,
  withdrawn_at: string | null; // when it was withdrawn,
  withdrawn_reason: string | null; // why,
  xero_invite_at: string | null; // when the Xero invite was recorded.
}; // End of the shape.

// One acknowledgement, as read from the database.
type Ack = { statement: string; statement_version: number; statement_title: string; statement_url: string; typed_name: string; acknowledged_at: string }; // Which document and version, its name and link, the typed name, and when.

// The filters along the top of the list.
const FILTERS = [ // Each filter's id, words and the statuses it shows:
  { id: "open", label: "Waiting on staff", statuses: ["sent", "signed"] }, // still waiting on the staff member,
  { id: "complete", label: "Complete", statuses: ["complete"] }, // complete,
  { id: "withdrawn", label: "Withdrawn", statuses: ["withdrawn"] }, // withdrawn,
  { id: "all", label: "All", statuses: ["sent", "signed", "complete", "withdrawn"] }, // everything.
]; // End of the filters.

// A date and time in Adelaide, written out (for signature records).
const stamp = (iso: string) => new Date(iso).toLocaleString("en-AU", { timeZone: "Australia/Adelaide", dateStyle: "medium", timeStyle: "short" }) + " (Adelaide time)"; // For example "18 Nov 2026, 9:30 am (Adelaide time)".

// One labelled detail.
function Detail({ label, children }: { label: string; children: ReactNode }) { // Takes the label and the detail.
  return ( // Shows:
    <div>{/* a block: */}
      <p className="text-xs font-semibold tracking-wide text-zinc-500 uppercase">{label}</p>{/* the label, small and grey, */}
      <div className="mt-0.5 text-sm">{children}</div>{/* and the detail. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of Detail.

// Shows the page (owner, Operations and Finance admins).
export default async function ContractsPage({ searchParams }: PageProps<"/admin/contracts">) {
  const viewer = await requireAdminLevel(["owner", "operations", "finance"]); // Must be the owner, an Operations admin or a Finance admin, with two-step login.
  const canSend = FULL_ADMIN.includes(viewer.level); // Only the owner and Operations admins send and withdraw.
  const params = await searchParams; // Reads the address settings.
  const supabase = await createClient(); // Connects to the database.
  const id = typeof params.id === "string" && /^[0-9a-f-]{36}$/.test(params.id) ? params.id : null; // The contract to open, if any.

  // One contract in full.
  if (id) { // A contract is open:
    const [{ data }, { data: acks }, { data: pay }, { data: docs }] = await Promise.all([ // reads four things at once:
      supabase.from("employment_contracts").select("*").eq("id", id).maybeSingle(), // the contract,
      supabase.from("employment_contract_acknowledgements").select("statement, statement_version, statement_title, statement_url, typed_name, acknowledged_at").eq("contract_id", id).order("statement_version", { ascending: false }), // its acknowledgements, newest version first,
      supabase.rpc("employment_contract_pay_evidence", { p_id: id }), // pay sent since it was sent,
      supabase.from("employment_contract_documents").select("key, title, url, also_known_as"), // and the document links (with their older addresses).
    ]); // End of the reads.
    const c = data as Contract | null; // The contract (or nothing if not found).
    const evidence = ((pay ?? []) as { first_paid_work_date: string | null; paid_lines: number }[])[0]; // The pay evidence row.
    const ackRows = (acks ?? []) as Ack[]; // The acknowledgements.
    return ( // Shows:
      <DashboardFrame role="admin" roles={viewer.roles} current="contracts">{/* the dashboard frame, */}
        <div className="space-y-6">{/* the cards, with space between: */}
          <p><BackButton href="/admin/contracts">Back to all contracts</BackButton></p>{/* a button back to the list, */}
          {!c ? ( // Not found:
            <Card title="Contract not found"><p className="text-sm">It may have been removed.</p></Card> // says so.
          ) : ( // Found:
            <>{/* (a group:) */}
              <Card title={c.title} description={`${c.staff_name} · ${CONTRACT_STATUS_NAMES[c.status]}`}>{/* the summary card: */}
                <div className="grid gap-4 sm:grid-cols-3">{/* three columns on wider screens: */}
                  <Detail label="Staff member">{c.staff_name}<br />{c.staff_email}</Detail>{/* who, */}
                  <Detail label="Contract">{CONTRACT_TYPE_NAMES[c.contract_type]}, version {c.template_version}<br />{EMPLOYMENT_NAMES[c.employment]}</Detail>{/* which contract and type, */}
                  <Detail label="Sent">{stamp(c.sent_at)}<br />by {c.sent_by_name}</Detail>{/* when and by whom, */}
                  <Detail label="Signed">{c.signed_at ? <>{stamp(c.signed_at)}<br />Typed name: &ldquo;{c.signed_name}&rdquo;, with two-step login and consent to sign electronically</> : "Not yet"}</Detail>{/* the signature record, */}
                  <Detail label="Pay notice">{c.signed_at ? (c.pay_notice_shown ? "Shown when signing: accepting pay is further acceptance of the terms." : "Not recorded") : "Shown when they sign"}</Detail>{/* the pay notice, */}
                  <Detail label="Pay since it was sent">{evidence?.paid_lines ? `${evidence.paid_lines} pay line${evidence.paid_lines === 1 ? "" : "s"} sent to Xero, first for work on ${shortDate(evidence.first_paid_work_date ?? c.sent_at)}` : "None yet"}</Detail>{/* the pay evidence, */}
                  {c.withdrawn_at && <Detail label="Withdrawn">{stamp(c.withdrawn_at)}{c.withdrawn_reason ? `: ${c.withdrawn_reason}` : ""}</Detail>}{/* and when withdrawn (if it was). */}
                </div>{/* End of the columns. */}
                <SubHeading>Documents acknowledged</SubHeading>{/* A heading: */}
                <ul className="space-y-1 text-sm">{/* each document: */}
                  {c.statements.map((key) => { // for each document the contract needs:
                    const a = ackRows.find((r) => r.statement === key); // its newest acknowledgement, if made,
                    return ( // shows:
                      <li key={key} className={a ? "text-teal-800" : "text-zinc-500"}>{/* a line, green when done: */}
                        {a ? "✓" : "○"} {a ? <a href={a.statement_url} target="_blank" rel="noreferrer" className="underline">{a.statement_title}</a> : key}{/* a tick or circle and the document, */}
                        {a ? `: version ${a.statement_version} acknowledged ${stamp(a.acknowledged_at)} as "${a.typed_name}"` : ": not yet"}{/* and which version, when, as whom. */}
                      </li> // End of the line.
                    ); // End of what's shown.
                  })}{/* End of the documents. */}
                </ul>{/* End of the list. */}
                <p className="mt-4 text-xs text-zinc-500">Wording fingerprint (SHA-256): <span className="font-mono break-all">{c.body_sha256}</span>. This proves the wording below is exactly what was sent and signed.</p>{/* The fingerprint. */}
              </Card>{/* End of the summary card. */}

              {(c.status === "signed" || c.status === "complete") && ( // Signed: the Xero step.
                <Card title="Xero self-setup" description={c.xero_invite_at ? `Invite recorded ${stamp(c.xero_invite_at)}.` : "Send them Xero's self-setup invite so they enter their own tax, bank and super details."}>{/* a card: */}
                  {c.xero_invite_at ? ( // Already done:
                    <p className="text-sm">Once they finish the Xero form, approve it in Xero (Payroll, then Employees), then match them to Xero on <TextLink href="/admin/billing">Billing</TextLink> under Staff pay.</p> // the remaining steps.
                  ) : ( // Still to do:
                    <>{/* (a group:) */}
                      <ol className="mb-4 list-decimal space-y-1 pl-5 text-sm">{/* the steps: */}
                        <li>In Xero, go to Payroll, then Employees, then New employee, and choose <strong>Invite to self-onboard</strong>.</li>{/* where to go, */}
                        <li>Enter their name <strong>{c.staff_name}</strong> and email <strong>{c.staff_email}</strong>, choose Employee and the income type, set a due date before {c.filled_values.start_date ? `their start date (${c.filled_values.start_date})` : "their start date"}, and name yourself as the contact.</li>{/* what to enter, */}
                        <li>Press Send invite. Xero emails them a secure form. Then press the button below.</li>{/* and send it. */}
                      </ol>{/* End of the steps. */}
                      <p className="mb-4 text-xs text-zinc-500">Xero does not let other apps send this invite, so it is sent from Xero itself.</p>{/* Why it is done in Xero. */}
                      <XeroInviteForm id={c.id} />{/* The button. */}
                    </> // End of the group.
                  )}{/* End of the choice. */}
                </Card> // End of the Xero card.
              )}{/* End of the Xero step. */}

              {canSend && c.status === "sent" && ( // Not signed yet, and this admin can withdraw:
                <Card title="Withdraw" description="Use this if the contract has a mistake. Then send a corrected one." collapsible defaultOpen={false}>{/* a closed card: */}
                  <WithdrawContractForm id={c.id} />{/* the withdraw form. */}
                </Card> // End of the card.
              )}{/* End of the withdraw part. */}

              <Card title="Contract as sent">{/* the wording card: */}
                <ContractText text={c.body} links={documentLinks((docs ?? []) as ContractDocument[])} />{/* the exact wording (old document addresses open the app pages). */}
              </Card>{/* End of the wording card. */}
            </> // End of the group.
          )}{/* End of the choice. */}
        </div>{/* End of the cards. */}
      </DashboardFrame> // End of the frame.
    ); // End of what's shown.
  } // End of the open contract.

  // The list, and the send form.
  const filter = FILTERS.find((f) => f.id === params.status) ?? FILTERS[0]; // The filter chosen (waiting on staff by default).
  const [{ data: rows }, { data: templates }, { data: staff }, { data: rereadRows }] = await Promise.all([ // Reads four things at once:
    supabase.from("employment_contracts").select("id, staff_name, contract_type, employment, status, sent_at, signed_at, completed_at, xero_invite_at").in("status", filter.statuses).order("sent_at", { ascending: false }).limit(300), // the contracts in this filter, newest first,
    canSend ? supabase.from("employment_contract_templates").select("id, contract_type, title, body, version").eq("status", "published").order("contract_type") : Promise.resolve({ data: [] }), // the published templates (for the send form),
    canSend ? supabase.rpc("staff_directory") : Promise.resolve({ data: [] }), // the staff list (for the send form),
    canSend ? supabase.rpc("policy_rereads_outstanding") : Promise.resolve({ data: [] }), // and who still has a new policy version to read (Carla, 22 Nov 2026).
  ]); // End of the reads.
  const rereads = (rereadRows ?? []) as { contract_id: string; staff_name: string; title: string; version: number; version_at: string | null }[]; // Who still has a new version to read.
  const contracts = (rows ?? []) as Pick<Contract, "id" | "staff_name" | "contract_type" | "employment" | "status" | "sent_at" | "signed_at" | "completed_at" | "xero_invite_at">[]; // The contracts listed.
  const people = ((staff ?? []) as (SendStaff & { left_on: string | null })[]) // The staff list:
    .filter((s) => !s.left_on && (s.is_tutor || s.is_admin)) // current tutors and admins only,
    .sort((a, b) => a.full_name.localeCompare(b.full_name)); // in name order.
  const preselect = typeof params.to === "string" ? params.to : undefined; // A person to choose in the send form (from a link), if any.
  // Work outside CLG (owner only: contract clause 6.7, Carla 22 Nov 2026).
  const outside = viewer.level === "owner" // Only for the owner:
    ? (((await supabase.from("outside_work_reports").select("id, account_id, kind, role_title, organisation, details, paid, starts_on, ends_on, owner_seen_at, owner_note").order("owner_seen_at", { ascending: true, nullsFirst: true }).order("starts_on", { ascending: false }).limit(200)).data ?? []) as (OutsideWork & { account_id: string; owner_seen_at: string | null; owner_note: string | null })[]) // every report, not yet seen first,
    : []; // otherwise none.
  const outsideNames = new Map((outside.length ? ((await supabase.from("accounts").select("id, full_name").in("id", [...new Set(outside.map((o) => o.account_id))])).data ?? []) : []).map((a) => [a.id as string, a.full_name as string])); // Each staff member's name, by id.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="contracts">{/* the dashboard frame, */}
      <div className="space-y-6">{/* the cards, with space between: */}
        {canSend && ( // The owner and Operations admins:
          <Card title="Send a contract" description="Choose the person and the contract, type in the details that do not fill in by themselves, and send it. They read and sign it in the app.">{/* the send card: */}
            <SendContractForm templates={(templates ?? []) as SendTemplate[]} staff={people} preselect={preselect} />{/* the send form, */}
            {viewer.level === "owner" && <p className="mt-4 text-sm"><TextLink href="/admin/contracts/templates">Contract templates and document links</TextLink></p>}{/* and, for the owner, the templates link. */}
          </Card> // End of the send card.
        )}{/* End of the send part. */}
        {viewer.level === "owner" && ( // The owner:
          <Card collapsible defaultOpen={outside.some((o) => !o.owner_seen_at)} title="Work outside CLG" description="Roles staff do outside CLG (contract clause 6.7), newest not yet seen first. Staff add these on My contract, and you get a notice each time one is added, changed or ended. Only you see this.">{/* the work outside CLG card: */}
            {outside.length === 0 ? <Empty>No staff have reported work outside CLG.</Empty> : ( // None, or the list:
              <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                {outside.map((o) => ( // for each report:
                  <li key={o.id} className="space-y-2 py-3 first:pt-0">{/* a row: */}
                    <p><span className="font-medium">{outsideNames.get(o.account_id) ?? "A staff member"}</span>: {o.role_title}{o.organisation ? ` at ${o.organisation}` : ""} · {OUTSIDE_WORK_KINDS[o.kind]} · {o.paid ? "Paid" : "Unpaid"}</p>{/* who, the role, where, kind and paid, */}
                    <p className="text-zinc-600">From {shortDate(o.starts_on)}{o.ends_on ? ` to ${shortDate(o.ends_on)}` : ", still going"}{o.owner_seen_at ? ` · Seen ${shortDate(o.owner_seen_at)}` : " · Not yet seen"}</p>{/* the dates and whether it was seen, */}
                    {o.details && <p className="whitespace-pre-line">{o.details}</p>}{/* their details, */}
                    <MarkOutsideWorkSeenForm id={o.id} note={o.owner_note} />{/* and the "mark as seen" form with the note. */}
                  </li> // End of the row.
                ))}{/* End of the reports. */}
              </ul> // End of the list.
            )}{/* End of the choice. */}
          </Card> // End of the card.
        )}{/* End of the work outside CLG part. */}
        {rereads.length > 0 && ( // Someone still has a new policy version to read:
          <Card title="New policy versions still to read" description="These staff have not yet read and ticked the newest version of a policy linked to their contract. They see it on My contract, with a number on the menu.">{/* a card: */}
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {rereads.map((r) => ( // for each person and policy:
                <li key={`${r.contract_id}-${r.title}`} className="flex flex-wrap items-center justify-between gap-2 py-2 first:pt-0">{/* a row: */}
                  <span><span className="font-medium">{r.staff_name}</span> · {r.title}, version {r.version}{r.version_at ? ` (since ${shortDate(r.version_at)})` : ""}</span>{/* who, which policy and since when, */}
                  <TextLink href={`/admin/contracts?id=${r.contract_id}`}>Open contract</TextLink>{/* and a link to their contract. */}
                </li> // End of the row.
              ))}{/* End of the list. */}
            </ul>{/* End of the list. */}
          </Card> // End of the card.
        )}{/* End of the reread part. */}
        <Card title="Contracts" description="Every contract sent to staff. Open one to see its wording, the signature record and the Xero step.">{/* the list card: */}
          <div className="mb-4 flex flex-wrap gap-2">{/* the filter buttons (wrap on small screens): */}
            {FILTERS.map((f) => ( // for each filter:
              <TextLink // a link:
                key={f.id} // (its id)
                href={f.id === "open" ? "/admin/contracts" : `/admin/contracts?status=${f.id}`} // to the list with that filter,
                aria-current={f.id === filter.id ? "page" : undefined} // marked as current when chosen,
                className={`rounded-full border px-3 py-1 text-sm ${f.id === filter.id ? "border-brand bg-brand text-white" : "border-zinc-300 text-zinc-700 hover:border-brand"}`} // filled in when chosen.
              >{/* (end of the link's settings) */}
                {f.label}{/* its words. */}
              </TextLink> // End of the link.
            ))}{/* End of the filters. */}
          </div>{/* End of the filters. */}
          {contracts.length === 0 ? ( // None:
            <Empty>No contracts here.</Empty> // says so.
          ) : ( // Otherwise:
            <Table headings={["Sent", "Staff member", "Contract", "Status", "Xero", ""]}>{/* a table: */}
              {contracts.map((c) => ( // for each contract:
                <tr key={c.id}>{/* a row: */}
                  <td className="whitespace-nowrap">{shortDate(c.sent_at)}</td>{/* when it was sent, */}
                  <td>{c.staff_name}</td>{/* who, */}
                  <td>{CONTRACT_TYPE_NAMES[c.contract_type]} ({EMPLOYMENT_NAMES[c.employment]})</td>{/* which contract, */}
                  <td className="whitespace-nowrap">{CONTRACT_STATUS_NAMES[c.status]}</td>{/* where it is up to, */}
                  <td className="whitespace-nowrap text-xs">{c.xero_invite_at ? "Invite sent" : c.status === "signed" || c.status === "complete" ? "To do" : ""}</td>{/* the Xero step, */}
                  <td className="text-right"><TextLink href={`/admin/contracts?id=${c.id}`}>Open</TextLink></td>{/* and a link to open it. */}
                </tr> // End of the row.
              ))}{/* End of the contracts. */}
            </Table> // End of the table.
          )}{/* End of the choice. */}
        </Card>{/* End of the list card. */}
      </div>{/* End of the cards. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of ContractsPage.
