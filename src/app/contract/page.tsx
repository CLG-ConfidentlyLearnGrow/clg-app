// Summary: the "My contract" page for tutors and admin staff (Carla, 17 Nov
// 2026). Lists the contracts CLG has sent them, and opens one to read it,
// sign it, then acknowledge each linked document (the Fair Work statements,
// the Child Safe Policy and the Staff Code of Conduct). Signed contracts stay
// here so staff can read them again at any time.
// See docs/features/employment-contracts.md.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { ContractText } from "@/components/contract-text"; // Shows a contract's wording.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { BackButton, Card, Empty, Table, TextLink } from "@/components/ui"; // Shared page parts.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Checks two-step login, and makes sure someone is signed in.
import { CONTRACT_STATUS_NAMES, EMPLOYMENT_NAMES, contractHref, type ContractStatus, type Employment } from "@/lib/employment-contracts"; // Contract words and the page address.
import { shortDate } from "@/lib/scheduling"; // Shows a date in a short, friendly way.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { AcknowledgeForm, SignForm } from "./forms"; // The signing and acknowledging forms.

// A date and time in Adelaide, written out.
const stamp = (iso: string) => new Date(iso).toLocaleString("en-AU", { timeZone: "Australia/Adelaide", dateStyle: "medium", timeStyle: "short" }); // For example "18 Nov 2026, 9:30 am".

// Shows the page (tutors and admins).
export default async function MyContractPage({ searchParams }: PageProps<"/contract">) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard"); // Not staff: goes to the dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Staff must use two-step login (signing needs it too).
  const params = await searchParams; // Reads the address settings.
  const role = params.as === "admin" && viewer.roles.includes("admin") ? "admin" : viewer.roles.includes("tutor") ? "tutor" : "admin"; // The dashboard to show it in (tutor first).
  const supabase = await createClient(); // Connects to the database.
  const id = typeof params.id === "string" && /^[0-9a-f-]{36}$/.test(params.id) ? params.id : null; // The contract to open, if any.

  // One contract open.
  if (id) { // A contract is open:
    const [{ data }, { data: acks }, { data: docs }] = await Promise.all([ // reads three things at once:
      supabase.from("employment_contracts").select("id, title, body, body_sha256, status, employment, sent_at, signed_at, signed_name, statements, completed_at").eq("id", id).eq("account_id", viewer.id).maybeSingle(), // their contract,
      supabase.from("employment_contract_acknowledgements").select("statement, statement_title, statement_url, acknowledged_at").eq("contract_id", id), // what they have acknowledged,
      supabase.from("employment_contract_documents").select("key, title, url, sort").order("sort"), // and the document links.
    ]); // End of the reads.
    const c = data as { id: string; title: string; body: string; body_sha256: string; status: ContractStatus; employment: Employment; sent_at: string; signed_at: string | null; signed_name: string | null; statements: string[]; completed_at: string | null } | null; // The contract (or nothing).
    const done = (acks ?? []) as { statement: string; statement_title: string; statement_url: string; acknowledged_at: string }[]; // The acknowledgements made.
    const links = (docs ?? []) as { key: string; title: string; url: string }[]; // The document links.
    return ( // Shows:
      <DashboardFrame role={role} roles={viewer.roles} current="contract">{/* the dashboard frame, */}
        <div className="space-y-6">{/* the cards, with space between: */}
          <p><BackButton href={`/contract?as=${role}`}>Back to my contracts</BackButton></p>{/* a button back, */}
          {!c ? ( // Not found:
            <Card title="Contract not found"><p className="text-sm">It may have been withdrawn. Please ask CLG in the Help chat if you were expecting one.</p></Card> // says so.
          ) : ( // Found:
            <>{/* (a group:) */}
              <Card title={c.title} description={`${EMPLOYMENT_NAMES[c.employment]} · sent ${shortDate(c.sent_at)} · ${CONTRACT_STATUS_NAMES[c.status]}`}>{/* the contract card: */}
                {c.status === "sent" && <p className="mb-4 rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-900">Please read the whole contract carefully. If anything is unclear or looks wrong, ask CLG in the <TextLink href="/help">Help chat</TextLink> before signing.</p>}{/* a note before signing, */}
                {c.status === "withdrawn" && <p className="mb-4 rounded-xl bg-zinc-100 px-4 py-3 text-sm">CLG has withdrawn this contract, so it does not need signing. If a new one was sent, it is in your list of contracts.</p>}{/* a note if withdrawn, */}
                <ContractText text={c.body} />{/* the wording. */}
              </Card>{/* End of the contract card. */}
              {c.status === "sent" && ( // Waiting to be signed:
                <Card title="Sign your contract" description="Signing needs two-step login. Your signature is recorded with the date, the time, and a fingerprint of the exact wording above.">{/* the signing card: */}
                  <SignForm id={c.id} hash={c.body_sha256} fullName={viewer.fullName} />{/* the signing form. */}
                </Card> // End of the card.
              )}{/* End of the signing part. */}
              {(c.status === "signed" || c.status === "complete") && ( // Signed:
                <Card title="Acknowledgements" description={c.signed_at ? `You signed this contract on ${stamp(c.signed_at)} as "${c.signed_name}". Please now open and acknowledge each document.` : undefined}>{/* the acknowledgements card: */}
                  <div className="space-y-6">{/* each document, with space between: */}
                    {c.statements.map((key) => { // for each document the contract needs:
                      const made = done.find((a) => a.statement === key); // its acknowledgement, if made,
                      const doc = links.find((d) => d.key === key); // and its current name and link.
                      if (made) return <p key={key} className="text-sm text-teal-800">✓ <a href={made.statement_url} target="_blank" rel="noreferrer" className="underline">{made.statement_title}</a> acknowledged on {stamp(made.acknowledged_at)}.</p>; // Done: a tick, the document and when.
                      if (!doc) return <p key={key} className="text-sm text-zinc-500">One document is not available right now. Please ask CLG in the Help chat.</p>; // The document has gone: says to ask.
                      return <AcknowledgeForm key={key} id={c.id} statement={key} title={doc.title} href={doc.url} fullName={viewer.fullName} />; // Still to do: the form.
                    })}{/* End of the documents. */}
                  </div>{/* End of the list. */}
                  {c.status === "complete" && <p className="mt-6 rounded-xl bg-teal-50 px-4 py-3 text-sm text-teal-900">All done. Thank you. CLG will now send you an email from Xero to enter your tax, bank and superannuation details.</p>}{/* a thank you, once complete. */}
                </Card> // End of the card.
              )}{/* End of the acknowledgements part. */}
            </> // End of the group.
          )}{/* End of the choice. */}
        </div>{/* End of the cards. */}
      </DashboardFrame> // End of the frame.
    ); // End of what's shown.
  } // End of the open contract.

  // The list of their contracts.
  const { data } = await supabase.from("employment_contracts").select("id, title, status, sent_at, signed_at").eq("account_id", viewer.id).order("sent_at", { ascending: false }); // Reads their contracts, newest first.
  const rows = (data ?? []) as { id: string; title: string; status: ContractStatus; sent_at: string; signed_at: string | null }[]; // The contracts.
  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="contract">{/* the dashboard frame, */}
      <Card title="My contract" description="Employment contracts CLG has sent you. Open one to read it, sign it, or read it again later.">{/* the list card: */}
        {rows.length === 0 ? ( // None:
          <Empty>CLG has not sent you a contract in the app yet.</Empty> // says so.
        ) : ( // Some:
          <Table headings={["Sent", "Contract", "Status", ""]}>{/* a table: */}
            {rows.map((r) => ( // for each contract:
              <tr key={r.id}>{/* a row: */}
                <td className="whitespace-nowrap">{shortDate(r.sent_at)}</td>{/* when it was sent, */}
                <td>{r.title}</td>{/* its title, */}
                <td className="whitespace-nowrap">{CONTRACT_STATUS_NAMES[r.status]}</td>{/* where it is up to, */}
                <td className="text-right"><TextLink href={`${contractHref(r.id)}&as=${role}`}>{r.status === "sent" ? "Read and sign" : r.status === "signed" ? "Finish" : "Open"}</TextLink></td>{/* and a link to open it. */}
              </tr> // End of the row.
            ))}{/* End of the contracts. */}
          </Table> // End of the table.
        )}{/* End of the choice. */}
      </Card>{/* End of the list card. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of MyContractPage.
