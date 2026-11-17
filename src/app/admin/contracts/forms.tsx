// Summary: the admin forms for employment contracts: sending a contract
// (choose the staff member, the contract and the employment type, then type
// into each gap that does not fill in by itself), withdrawing a contract that
// has not been signed, recording the Xero self-setup invite, saving a
// template, publishing or deleting a draft, and changing a document's link.
// See docs/features/employment-contracts.md.
//
"use client"; // Runs in the browser, so the gap boxes can change as the contract is chosen.

import { useState } from "react"; // Keeps track of the chosen contract and employment type.
import { discardContractTemplate, publishContractTemplate, recordXeroInvite, saveContractDocument, saveContractTemplate, sendContract, withdrawContract } from "@/app/actions/employment-contracts"; // The server actions for contracts.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // Form boxes and lists.
import { AUTO_GAPS, CONTRACT_TYPES, CONTRACT_TYPE_NAMES, EMPLOYMENT_NAMES, employmentsFor, findGaps, roleFor, type ContractType } from "@/lib/employment-contracts"; // Contract words and the gap reader.

// A published template, as the send form needs it.
export type SendTemplate = { id: string; contract_type: ContractType; title: string; body: string; version: number }; // Its id, kind, title, wording and version.
// A staff member who can be sent a contract.
export type SendStaff = { account_id: string; full_name: string; is_tutor: boolean; is_admin: boolean }; // Their account, name and roles.

// The send form. The gap boxes change to match the contract chosen.
export function SendContractForm({ templates, staff, preselect }: { templates: SendTemplate[]; staff: SendStaff[]; preselect?: string }) {
  const [templateId, setTemplateId] = useState(templates[0]?.id ?? ""); // The chosen contract (the first one to start).
  const template = templates.find((t) => t.id === templateId); // That contract's details.
  const gaps = template ? findGaps(`${template.title}\n${template.body}`).filter((g) => !g.auto) : []; // The gaps an admin types (the rest fill in by themselves).
  const people = template ? staff.filter((s) => (roleFor(template.contract_type) === "tutor" ? s.is_tutor : s.is_admin)) : []; // Staff who hold the role this contract is for.
  if (templates.length === 0) return <p className="text-sm text-zinc-600">No contract is ready to send yet. The owner publishes contract templates on the Contract templates page.</p>; // Nothing published yet: says so.
  return ( // Shows:
    <ActionForm action={sendContract} submitLabel="Send contract">{/* a form that sends the contract: */}
      <Select label="Contract" name="template_id" value={templateId} onChange={(e) => setTemplateId(e.target.value)}>{/* the contract list (changing it changes the boxes): */}
        {templates.map((t) => <option key={t.id} value={t.id}>{CONTRACT_TYPE_NAMES[t.contract_type]}: {t.title} (version {t.version})</option>)}{/* each published contract. */}
      </Select>{/* End of the list. */}
      <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="Staff member" name="account_id" required defaultValue={people.some((p) => p.account_id === preselect) ? preselect : ""} key={`${templateId}-people`}>{/* who it goes to: */}
          <option value="" disabled>Choose a person</option>{/* a prompt, */}
          {people.map((p) => <option key={p.account_id} value={p.account_id}>{p.full_name}</option>)}{/* and each person with the right role. */}
        </Select>{/* End of the list. */}
        <Select label="Employment type" name="employment" required key={`${templateId}-employment`} defaultValue={template ? employmentsFor(template.contract_type)[0] : ""}>{/* casual, part-time or full-time: */}
          {(template ? employmentsFor(template.contract_type) : []).map((e) => <option key={e} value={e}>{EMPLOYMENT_NAMES[e]}</option>)}{/* only the types this contract allows. */}
        </Select>{/* End of the list. */}
      </div>{/* End of the columns. */}
      {gaps.length > 0 ? ( // Gaps to type:
        <fieldset className="space-y-3 rounded-xl border border-zinc-200 p-4" key={`${templateId}-gaps`}>{/* a box of them: */}
          <legend className="px-1 text-sm font-semibold">Details to fill in</legend>{/* its heading, */}
          <p className="text-xs text-zinc-500">These go into the contract where the same words appear in square brackets. Their name, email, employment type and today&rsquo;s date fill in by themselves.</p>{/* what they are, */}
          <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
            {gaps.map((g) => ( // for each gap:
              <Field // a text box:
                key={g.key} // (its key)
                label={g.label} // labelled with the gap's words,
                name={`gap:${g.key}`} // named after its key,
                required={!g.fallback} // needed unless it has fallback words,
                maxLength={2000} // up to 2,000 characters,
                hint={g.fallback ? `Leave empty to show "${g.fallback}".` : undefined} // and, if optional, what an empty box shows.
              /> // End of the box.
            ))}{/* End of the gaps. */}
          </div>{/* End of the columns. */}
        </fieldset> // End of the box.
      ) : ( // No gaps to type:
        <p className="text-sm text-zinc-600">Everything in this contract fills in by itself.</p> // says so.
      )}{/* End of the gaps part. */}
      <p className="text-xs text-zinc-500">If they already have a contract waiting to be signed, it is withdrawn and replaced by this one. They are emailed a link to read and sign it in the app.</p>{/* What happens. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SendContractForm.

// Withdraws a contract that has not been signed.
export function WithdrawContractForm({ id }: { id: string }) {
  return ( // Shows:
    <ActionForm action={withdrawContract} submitLabel="Withdraw this contract">{/* a form that withdraws it: */}
      <input type="hidden" name="id" value={id} />{/* the contract's id, hidden, */}
      <Field label="Why (only admins see this)" name="reason" maxLength={500} placeholder="For example: wrong start date" />{/* the reason. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of WithdrawContractForm.

// Records that the Xero self-setup invite has been sent.
export function XeroInviteForm({ id }: { id: string }) {
  return ( // Shows:
    <ActionForm action={recordXeroInvite} submitLabel="I have sent the Xero invite">{/* a form that records it: */}
      <input type="hidden" name="id" value={id} />{/* the contract's id, hidden. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of XeroInviteForm.

// The template editor: kind, title and wording, with a live list of the gaps found.
export function TemplateForm({ id, contractType, title, body, locked }: { id: string | null; contractType: ContractType; title: string; body: string; locked: boolean }) {
  const [text, setText] = useState(body); // The wording as it is typed (to list the gaps).
  const [heading, setHeading] = useState(title); // The title as it is typed.
  const gaps = findGaps(`${heading}\n${text}`); // The gaps found so far.
  return ( // Shows:
    <ActionForm action={saveContractTemplate} submitLabel={locked ? "Save as a new draft version" : "Save draft"}>{/* a form that saves it: */}
      <input type="hidden" name="id" value={id ?? ""} />{/* the template's id (blank for a new one), hidden, */}
      {id ? ( // An existing template:
        <input type="hidden" name="contract_type" value={contractType} /> // keeps its kind,
      ) : ( // A new one:
        <Select label="Kind of contract" name="contract_type" defaultValue={contractType}>{/* chooses its kind: */}
          {CONTRACT_TYPES.map((t) => <option key={t} value={t}>{CONTRACT_TYPE_NAMES[t]}</option>)}{/* each kind. */}
        </Select> // End of the list.
      )}{/* End of the kind. */}
      <Field label="Title" name="title" required maxLength={200} value={heading} onChange={(e) => setHeading(e.target.value)} />{/* the title, */}
      <TextArea label="Wording" name="body" required rows={22} value={text} onChange={(e) => setText(e.target.value)} hint="Paste from the contract's Claude Doc: open it, choose Export, then Markdown, and paste everything here. Put gaps in square brackets, for example [Start date]. Gaps with the same words get the same value." />{/* the wording, */}
      <div className="rounded-xl bg-zinc-50 p-4 text-sm">{/* the gaps found: */}
        <p className="font-semibold">Gaps found ({gaps.length})</p>{/* a heading with the count, */}
        {gaps.length === 0 ? <p className="mt-1 text-zinc-600">None yet.</p> : ( // none, or:
          <ul className="mt-2 space-y-1">{/* a list: */}
            {gaps.map((g) => ( // for each gap:
              <li key={g.key}>{/* a line: */}
                <span className="font-medium">[{g.label}]</span>{" "}{/* its words, */}
                <span className="text-zinc-600">{g.auto ? `fills in by itself (${AUTO_GAPS[g.key]})` : g.fallback ? `admin types it, or it shows "${g.fallback}"` : "admin types it when sending"}</span>{/* and how it is filled. */}
              </li> // End of the line.
            ))}{/* End of the gaps. */}
          </ul> // End of the list.
        )}{/* End of the choice. */}
        <p className="mt-3 text-xs text-zinc-500">Fill in by themselves: {Object.keys(AUTO_GAPS).map((k) => `[${k.replace(/_/g, " ")}]`).join(", ")}.</p>{/* the full list of automatic gaps. */}
      </div>{/* End of the gaps found. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of TemplateForm.

// Publishes a draft (with a tick to confirm the wording has been checked).
export function PublishTemplateForm({ id }: { id: string }) {
  return ( // Shows:
    <ActionForm action={publishContractTemplate} submitLabel="Publish this version">{/* a form that publishes it: */}
      <input type="hidden" name="id" value={id} />{/* the template's id, hidden, */}
      <label className="flex items-start gap-2 text-sm">{/* the confirm tick: */}
        <input type="checkbox" name="confirm" className="mt-1" />{/* a tick box, */}
        <span>I have checked the wording below, including that every gap shows as expected. New contracts of this kind will use this version.</span>{/* and its words. */}
      </label>{/* End of the line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of PublishTemplateForm.

// Deletes a draft.
export function DiscardTemplateForm({ id }: { id: string }) {
  return ( // Shows:
    <ActionForm action={discardContractTemplate} submitLabel="Delete this draft">{/* a form that deletes it: */}
      <input type="hidden" name="id" value={id} />{/* the template's id, hidden. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of DiscardTemplateForm.

// Changes one acknowledged document's name and link.
export function DocumentForm({ doc }: { doc: { key: string; title: string; url: string; casual_only: boolean } }) {
  return ( // Shows:
    <ActionForm action={saveContractDocument} submitLabel="Save">{/* a form that saves it: */}
      <input type="hidden" name="key" value={doc.key} />{/* which document, hidden, */}
      <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label={`Name${doc.casual_only ? " (casual staff only)" : ""}`} name="title" required maxLength={200} defaultValue={doc.title} />{/* its name, */}
        <Field label="Link" name="url" required maxLength={500} defaultValue={doc.url} hint="A web address starting with https://, or an app page starting with /" />{/* and its link. */}
      </div>{/* End of the columns. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of DocumentForm.
