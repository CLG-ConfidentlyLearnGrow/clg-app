// Summary: the Contract templates page for the owner (Carla, 17 Nov 2026).
// Lists every template version by kind of contract, opens one to edit (a
// draft) or to start a new version from (a published one), shows a preview
// of how the wording will look, and publishes or deletes drafts. Also sets
// the names and links of the documents staff acknowledge after signing.
// See docs/features/employment-contracts.md.
//
import { ContractText } from "@/components/contract-text"; // Shows a contract's wording.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { BackButton, Card, Empty, Table, TextLink } from "@/components/ui"; // Shared page parts.
import { requireAdminLevel } from "@/lib/auth"; // The admin check.
import { CONTRACT_TYPE_NAMES, CONTRACT_TYPES, TEMPLATE_STATUS_NAMES, documentLinks, type ContractDocument, type ContractType } from "@/lib/employment-contracts"; // Contract words, and the document link swap list.
import { shortDate } from "@/lib/scheduling"; // Shows a date in a short, friendly way.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { DiscardTemplateForm, DocumentForm, PublishTemplateForm, TemplateForm } from "../forms"; // The template and document forms.

// One template version, as read from the database.
type Template = { id: string; contract_type: ContractType; version: number; title: string; body: string; status: keyof typeof TEMPLATE_STATUS_NAMES; updated_at: string; published_at: string | null }; // Its fields.

// Shows the page (owner only).
export default async function ContractTemplatesPage({ searchParams }: PageProps<"/admin/contracts/templates">) {
  const viewer = await requireAdminLevel(["owner"]); // Must be the owner, with two-step login.
  const params = await searchParams; // Reads the address settings.
  const supabase = await createClient(); // Connects to the database.
  const id = typeof params.id === "string" && /^[0-9a-f-]{36}$/.test(params.id) ? params.id : null; // The template to open, if any.
  const newType = CONTRACT_TYPES.find((t) => t === params.new); // A kind of contract to start a new template for, if asked.

  // One template open (or a new one).
  if (id || newType) { // Editing:
    const { data } = id ? await supabase.from("employment_contract_templates").select("*").eq("id", id).maybeSingle() : { data: null }; // reads the template (none for a new one),
    const { data: docs } = await supabase.from("employment_contract_documents").select("key, title, url, also_known_as"); // the document links, for the preview,
    const t = data as Template | null; // the template.
    const locked = t !== null && t.status !== "draft"; // A published or replaced version cannot change; saving starts a new draft.
    return ( // Shows:
      <DashboardFrame role="admin" roles={viewer.roles} current="contracts">{/* the dashboard frame, */}
        <div className="space-y-6">{/* the cards, with space between: */}
          <p><BackButton href="/admin/contracts/templates">Back to contract templates</BackButton></p>{/* a button back, */}
          {params.saved === "1" && <p className="rounded-xl bg-teal-50 px-4 py-3 text-sm text-teal-900">Saved as a draft. Check the preview below, then publish it when it is ready.</p>}{/* a saved note, after saving, */}
          {id && !t ? <Card title="Template not found"><p className="text-sm">It may have been deleted.</p></Card> : ( // not found, or:
            <>{/* (a group:) */}
              <Card // the editor card:
                title={t ? `${CONTRACT_TYPE_NAMES[t.contract_type]}, version ${t.version} (${TEMPLATE_STATUS_NAMES[t.status]})` : `New template: ${CONTRACT_TYPE_NAMES[newType as ContractType]}`} // titled with the kind, version and status,
                description={locked ? "This version cannot change, because contracts may already have been sent with it. Saving starts the next version as a draft." : "Saving keeps it as a draft. Nothing changes for staff until you publish it."} // with what saving does.
              >{/* (end of the card's settings) */}
                <TemplateForm id={t?.id ?? null} contractType={t?.contract_type ?? (newType as ContractType)} title={t?.title ?? ""} body={t?.body ?? ""} locked={locked} />{/* the editor. */}
              </Card>{/* End of the editor card. */}
              {t?.status === "draft" && ( // A draft: publish or delete.
                <div className="grid gap-6 lg:grid-cols-2">{/* two cards side by side on wide screens: */}
                  <Card title="Publish">{/* the publish card, */}
                    <PublishTemplateForm id={t.id} />{/* with its form, */}
                  </Card>{/* End of the card. */}
                  <Card title="Delete draft">{/* the delete card, */}
                    <DiscardTemplateForm id={t.id} />{/* with its form. */}
                  </Card>{/* End of the card. */}
                </div> // End of the cards.
              )}{/* End of the draft actions. */}
              {t && ( // A saved template: the preview.
                <Card title="Preview (as saved)" description="How the wording looks to staff. Gaps still show in square brackets here; they are filled in when the contract is sent.">{/* the preview card: */}
                  <p className="mb-3 text-lg font-semibold">{t.title}</p>{/* the title, */}
                  <ContractText text={t.body} links={documentLinks((docs ?? []) as ContractDocument[])} />{/* and the wording (old document addresses open the app pages). */}
                </Card> // End of the preview card.
              )}{/* End of the preview. */}
            </> // End of the group.
          )}{/* End of the choice. */}
        </div>{/* End of the cards. */}
      </DashboardFrame> // End of the frame.
    ); // End of what's shown.
  } // End of the editor.

  // The list of templates and the document links.
  const [{ data: rows }, { data: docs }] = await Promise.all([ // Reads two things at once:
    supabase.from("employment_contract_templates").select("id, contract_type, version, title, status, updated_at, published_at").order("contract_type").order("version", { ascending: false }), // every template version,
    supabase.from("employment_contract_documents").select("key, title, url, casual_only, body, approved_at, country_urls").order("sort"), // and the documents staff acknowledge (with any wording kept in the app).
  ]); // End of the reads.
  const templates = (rows ?? []) as Omit<Template, "body">[]; // The template versions.
  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="contracts">{/* the dashboard frame, */}
      <div className="space-y-6">{/* the cards, with space between: */}
        <p><BackButton href="/admin/contracts">Back to contracts</BackButton></p>{/* a button back, */}
        {CONTRACT_TYPES.map((type) => { // for each kind of contract:
          const own = templates.filter((t) => t.contract_type === type); // its versions,
          return ( // shows:
            <Card key={type} title={CONTRACT_TYPE_NAMES[type]} description={own.some((t) => t.status === "published") ? undefined : "No version is in use yet, so this kind of contract cannot be sent."}>{/* a card: */}
              {own.length === 0 ? ( // No versions:
                <Empty>No template yet. <TextLink href={`/admin/contracts/templates?new=${type}`}>Start one</TextLink></Empty> // a link to start one.
              ) : ( // Some versions:
                <Table headings={["Version", "Title", "Status", "Changed", ""]}>{/* a table: */}
                  {own.map((t) => ( // for each version:
                    <tr key={t.id}>{/* a row: */}
                      <td>{t.version}</td>{/* its number, */}
                      <td>{t.title}</td>{/* its title, */}
                      <td className="whitespace-nowrap">{TEMPLATE_STATUS_NAMES[t.status]}</td>{/* where it is up to, */}
                      <td className="whitespace-nowrap">{shortDate(t.published_at ?? t.updated_at)}</td>{/* when it changed, */}
                      <td className="text-right"><TextLink href={`/admin/contracts/templates?id=${t.id}`}>{t.status === "draft" ? "Edit" : "Open"}</TextLink></td>{/* and a link to open it. */}
                    </tr> // End of the row.
                  ))}{/* End of the versions. */}
                </Table> // End of the table.
              )}{/* End of the choice. */}
            </Card> // End of the card.
          ); // End of what's shown.
        })}{/* End of the kinds. */}
        <Card title="Documents staff acknowledge" description="After signing, staff open each of these and acknowledge it with their typed name. Casual-only documents are skipped for part-time and full-time staff. Each acknowledgement keeps the name and link it was given at the time. The main link is for Australia; links for other countries are kept ready for when CLG works there.">{/* the documents card: */}
          <div className="space-y-6">{/* each document's form, with space between: */}
            {((docs ?? []) as { key: string; title: string; url: string; casual_only: boolean; body: string; approved_at: string | null; country_urls: Record<string, string> | null }[]).map((d) => <DocumentForm key={d.key} doc={d} />)}{/* one form per document. */}
          </div>{/* End of the forms. */}
        </Card>{/* End of the documents card. */}
      </div>{/* End of the cards. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of ContractTemplatesPage.
