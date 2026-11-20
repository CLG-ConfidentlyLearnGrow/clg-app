// Summary: the server actions for employment contracts (Carla, 17 Nov 2026).
// The owner writes and publishes contract templates and sets the links of
// the documents staff acknowledge. The owner and Operations admins send a
// contract to a staff member (typing in any gaps that do not fill in by
// themselves) and can withdraw one that has not been signed. The staff
// member signs their contract, then acknowledges each linked document.
// Admins record when the Xero self-setup invite has been sent. The database
// checks every rule again. See docs/features/employment-contracts.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { z } from "zod"; // The form-checking library.
import { FULL_ADMIN, requireAdminLevel, requireViewer } from "@/lib/auth"; // The admin level groups and checks, and the signed-in check.
import { emailIsSetUp, sendEmails } from "@/lib/email/send"; // Checks email is set up, and sends emails.
import { CONTRACT_TYPES, contractHref } from "@/lib/employment-contracts"; // The kinds of contract, and the contract page address.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The plain database messages that are safe to show as they are (they start
// with these words); anything else gets a general message.
const PLAIN = /^(Only |Please |Choose |That |This |Each |The contract has|The details|The country)/; // The starts of this module's own plain messages.

// Picks the message to show for a database problem.
function problem(error: { message: string } | null, fallback: string): string { // Takes the problem and a general message.
  if (error && PLAIN.test(error.message)) return error.message; // A plain message: shows it as it is.
  if (error) console.error("Employment contracts:", error.message); // Anything else: notes it in the server log,
  return fallback; // and shows the general message.
} // End of problem.

// Refreshes every contracts page after a change.
function refresh() { // No inputs.
  revalidatePath("/admin/contracts"); // The admin contracts page,
  revalidatePath("/admin/contracts/templates"); // the template editor,
  revalidatePath("/contract"); // and the staff member's own contract page.
} // End of refresh.

// ---------------------------------------------------------------------------
// Templates and documents (owner only).
// ---------------------------------------------------------------------------

// The rules for saving a template.
const templateSchema = z.object({ // The form's fields:
  id: z.union([z.literal(""), z.uuid()]).default(""), // the template being changed (blank for a new one),
  contract_type: z.enum(CONTRACT_TYPES, "Choose the kind of contract."), // which kind of contract,
  title: z.string().trim().min(3, "Please give the template a title.").max(200, "Please keep the title under 200 characters."), // its title,
  body: z.string().min(1, "Please paste or write the contract wording.").max(100000, "The wording is too long (over 100,000 characters)."), // its wording.
}); // End of the rules.

// Saves a template as a draft (a published version is never changed: saving
// it starts the next version's draft). Opens the saved draft afterwards.
export async function saveContractTemplate(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner"]); // Only the owner (the database checks again).
  const parsed = templateSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const supabase = await createClient(); // Connects as the owner.
  const { data, error } = await supabase.rpc("employment_contract_template_save", { // Saves it:
    p_id: v.id || null, // the template (or none for a new one),
    p_contract_type: v.contract_type, // its kind,
    p_title: v.title, // its title,
    p_body: v.body.replace(/\r\n?/g, "\n"), // and its wording (with tidy line endings).
  }); // End of the save.
  if (error || typeof data !== "string") return { error: problem(error, "Could not save the template. Please try again.") }; // Failed: says why.
  refresh(); // Refreshes the pages.
  redirect(`/admin/contracts/templates?id=${data}&saved=1`); // Opens the saved draft.
} // End of saveContractTemplate.

// Publishes a draft so it is used for new contracts.
export async function publishContractTemplate(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner"]); // Only the owner (the database checks again).
  const id = z.uuid().safeParse(formData.get("id")); // Checks the template id looks right.
  if (!id.success) return { error: "That template was not found." }; // Odd id: plain message.
  if (formData.get("confirm") !== "on") return { error: "Please tick that you have checked the wording." }; // Asks for the check first.
  const supabase = await createClient(); // Connects as the owner.
  const { error } = await supabase.rpc("employment_contract_template_publish", { p_id: id.data }); // Publishes it.
  if (error) return { error: problem(error, "Could not publish the template. Please try again.") }; // Failed: says why.
  refresh(); // Refreshes the pages.
  return { message: "Published. New contracts of this kind now use this version. Contracts already sent keep their own wording." }; // Confirms it.
} // End of publishContractTemplate.

// Deletes a draft that is not wanted.
export async function discardContractTemplate(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner"]); // Only the owner (the database checks again).
  const id = z.uuid().safeParse(formData.get("id")); // Checks the template id looks right.
  if (!id.success) return { error: "That template was not found." }; // Odd id: plain message.
  const supabase = await createClient(); // Connects as the owner.
  const { error } = await supabase.rpc("employment_contract_template_discard", { p_id: id.data }); // Deletes the draft.
  if (error) return { error: problem(error, "Could not delete the draft. Please try again.") }; // Failed: says why.
  refresh(); // Refreshes the pages.
  redirect("/admin/contracts/templates"); // Back to the list of templates.
} // End of discardContractTemplate.

// The rules for a document's name and link.
const documentSchema = z.object({ // The form's fields:
  key: z.string().regex(/^[a-z_]{2,40}$/, "That document was not found."), // which document,
  title: z.string().trim().min(3, "Please give the document a name.").max(200, "Please keep the name under 200 characters."), // its name,
  url: z.string().trim().max(500, "Please keep the link under 500 characters.").regex(/^(https:\/\/|\/)/, "The link must start with https:// or be a page in this app (starting with /)."), // its link (Australia's),
  country_urls: z.string().max(5000, "Please keep the country links shorter.").default(""), // and links for other countries, one per line.
}); // End of the rules.

// Reads the "other countries" box: one line each, a two-letter country code,
// a space, then the link (for example "NZ https://..."). Gives back the
// links by country, or a plain message about the first line it cannot read.
function readCountryUrls(text: string): { urls: Record<string, string> } | { error: string } { // Takes the box's text.
  const urls: Record<string, string> = {}; // The links found so far.
  for (const raw of text.split(/\r?\n/)) { // Goes through each line:
    const line = raw.trim(); // without spaces at the ends,
    if (!line) continue; // skipping blank lines.
    const m = line.match(/^([A-Za-z]{2})\s*[:\-]?\s+(\S+)$/); // A code, a space, then the link?
    if (!m) return { error: `This line could not be read: "${line}". Write the two-letter country code, a space, then the link.` }; // No: says which line.
    urls[m[1].toUpperCase()] = m[2]; // Keeps it under the capitalised code.
  } // End of the lines.
  return { urls }; // Hands back the links.
} // End of readCountryUrls.

// Changes the name or link of a document staff acknowledge.
export async function saveContractDocument(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner"]); // Only the owner (the database checks again).
  const parsed = documentSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const countries = readCountryUrls(parsed.data.country_urls); // Reads the other-country links.
  if ("error" in countries) return { error: countries.error }; // A line could not be read: says which.
  const supabase = await createClient(); // Connects as the owner.
  const { error } = await supabase.rpc("employment_contract_document_save", { p_key: parsed.data.key, p_title: parsed.data.title, p_url: parsed.data.url }); // Saves the name and main link.
  if (error) return { error: problem(error, "Could not save the link. Please try again.") }; // Failed: says why.
  const { error: countryError } = await supabase.rpc("employment_contract_document_save_country_urls", { p_key: parsed.data.key, p_urls: countries.urls }); // Saves the other-country links.
  if (countryError) return { error: problem(countryError, "The name and main link were saved, but the country links were not. Please check them and save again.") }; // Failed: says why.
  refresh(); // Refreshes the pages.
  return { message: "Saved. Contracts signed from now on use this name and link." }; // Confirms it.
} // End of saveContractDocument.

// The rules for a document's wording kept in the app.
const documentTextSchema = z.object({ // The form's fields:
  key: z.string().regex(/^[a-z_]{2,40}$/, "That document was not found."), // which document,
  body: z.string().max(100000, "The wording is too long (over 100,000 characters).").default(""), // its wording.
}); // End of the rules.

// Saves the wording of a document kept in the app (such as the Child Safe
// Policy), and whether it is approved (final). Until approved, its page shows
// a draft label (Carla, 18 Nov 2026).
export async function saveContractDocumentText(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner"]); // Only the owner (the database checks again).
  const parsed = documentTextSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const approved = formData.get("approved") === "on"; // Whether "Approved" is ticked.
  const supabase = await createClient(); // Connects as the owner.
  const { error } = await supabase.rpc("employment_contract_document_save_text", { p_key: parsed.data.key, p_body: parsed.data.body.replace(/\r\n?/g, "\n"), p_approved: approved }); // Saves it (with tidy line endings).
  if (error) return { error: problem(error, "Could not save the wording. Please try again.") }; // Failed: says why.
  refresh(); // Refreshes the pages.
  revalidatePath(`/policies/${parsed.data.key}`); // Refreshes the document's own page.
  return { message: approved ? "Saved and approved. Staff see it without the draft label." : "Saved as a draft. Staff see it with a draft label until you tick Approved." }; // Confirms it.
} // End of saveContractDocumentText.

// ---------------------------------------------------------------------------
// Sending and withdrawing (owner and Operations admins).
// ---------------------------------------------------------------------------

// The rules for sending (the typed gaps are read separately).
const sendSchema = z.object({ // The form's fields:
  template_id: z.uuid("Choose a contract template."), // which template,
  account_id: z.uuid("Choose the staff member."), // who it goes to,
  employment: z.enum(["casual", "part_time", "full_time"], "Choose the employment type."), // casual, part-time or full-time.
}); // End of the rules.

// Fills a template for one staff member and sends it, then emails them a
// link to sign it, with links to the documents they will acknowledge.
export async function sendContract(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FULL_ADMIN); // Only the owner or an Operations admin (the database checks again).
  const parsed = sendSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const values: Record<string, string> = {}; // The typed gap values, by key.
  for (const [name, value] of formData.entries()) { // Goes through every field:
    if (name.startsWith("gap:") && typeof value === "string") values[name.slice(4)] = value.trim(); // keeps each gap box's words under its key.
  } // End of the fields.
  const supabase = await createClient(); // Connects as the signed-in admin.
  const { data: id, error } = await supabase.rpc("employment_contract_send", { // Sends it:
    p_template: parsed.data.template_id, // the template,
    p_account: parsed.data.account_id, // the staff member,
    p_employment: parsed.data.employment, // the employment type,
    p_values: values, // and the typed gaps.
  }); // End of the send.
  if (error || typeof id !== "string") return { error: problem(error, "Could not send the contract. Please try again.") }; // Failed: says why (for example which gaps are empty).
  refresh(); // Refreshes the pages.

  // Emails the staff member. The contract is in the app either way.
  const [{ data: sent }, { data: docs }] = await Promise.all([ // Reads two things at once:
    supabase.from("employment_contracts").select("staff_email, staff_name, title, statements").eq("id", id).single(), // the contract just sent,
    supabase.from("employment_contract_documents").select("key, title, url"), // and the document links.
  ]); // End of the reads.
  if (!sent || !emailIsSetUp()) return { message: "Sent. They will see it in the app the next time they sign in. (No email was sent because email is not set up.)" }; // No email possible: says so.
  const links = ((docs ?? []) as { key: string; title: string; url: string }[]) // The documents this contract needs:
    .filter((d) => (sent.statements as string[]).includes(d.key)) // just those,
    .map((d) => `- ${d.title}: ${d.url.startsWith("/") ? `https://app.clgtutoring.com${d.url}` : d.url}`) // as "name: link" lines (app pages get the full address),
    .join("\n"); // one per line.
  const failed = await sendEmails([{ // Sends one email:
    id: `employment-contract-${id}`, // an id for it (once per contract),
    email: sent.staff_email as string, // to the staff member,
    first_name: String(sent.staff_name).split(" ")[0] || null, // greeting them by first name,
    subject: `Your employment contract from CLG is ready to sign`, // the subject line,
    body: `${sent.title} is ready for you in the CLG app. Please read it carefully, then sign it in the app. After signing, you will be asked to acknowledge each of these documents, which you can read now:\n\n${links}\n\nIf you have any questions before signing, ask CLG in the app's Help chat.`, // what to do, with the document links,
    link: contractHref(id), // the button opens the contract,
    button: "Read and sign your contract", // the button's words,
    footer: "You get this email because CLG Tutoring has sent you an employment contract.", // and why they got it.
  }]); // End of the email.
  if (failed) { // The email did not go:
    console.error("Employment contract email:", failed); // notes why in the server log,
    return { message: "Sent, but the email could not be sent. They will still see it in the app; you may like to tell them yourself." }; // and says so.
  } // End of that case.
  return { message: "Sent. They have been emailed a link to read and sign it." }; // Confirms both.
} // End of sendContract.

// Withdraws a contract that has not been signed.
export async function withdrawContract(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FULL_ADMIN); // Only the owner or an Operations admin (the database checks again).
  const id = z.uuid().safeParse(formData.get("id")); // Checks the contract id looks right.
  if (!id.success) return { error: "That contract was not found." }; // Odd id: plain message.
  const reason = String(formData.get("reason") ?? "").trim().slice(0, 500); // Why (up to 500 characters).
  const supabase = await createClient(); // Connects as the signed-in admin.
  const { error } = await supabase.rpc("employment_contract_withdraw", { p_id: id.data, p_reason: reason }); // Withdraws it.
  if (error) return { error: problem(error, "Could not withdraw the contract. Please try again.") }; // Failed: says why.
  refresh(); // Refreshes the pages.
  return { message: "Withdrawn. They no longer see it as waiting. Send a new contract if needed." }; // Confirms it.
} // End of withdrawContract.

// Records that the Xero self-setup invite has been sent (from inside Xero).
export async function recordXeroInvite(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner", "operations", "finance"]); // Owner, Operations or Finance (the database checks again).
  const id = z.uuid().safeParse(formData.get("id")); // Checks the contract id looks right.
  if (!id.success) return { error: "That contract was not found." }; // Odd id: plain message.
  const supabase = await createClient(); // Connects as the signed-in admin.
  const { error } = await supabase.rpc("employment_contract_xero_done", { p_id: id.data }); // Records it.
  if (error) return { error: problem(error, "Could not record it. Please try again.") }; // Failed: says why.
  refresh(); // Refreshes the pages.
  return { message: "Recorded. Once they finish the Xero form, approve their details in Xero (Payroll > Employees), then match them to Xero on Admin > Billing > Staff pay." }; // Confirms, with the next steps in Xero.
} // End of recordXeroInvite.

// ---------------------------------------------------------------------------
// Signing and acknowledging (the staff member).
// ---------------------------------------------------------------------------

// The rules for signing.
const signSchema = z.object({ // The form's fields:
  id: z.uuid("That contract was not found."), // which contract,
  typed_name: z.string().trim().min(2, "Please type your full name.").max(200, "Please type your full name."), // their typed name,
  body_sha256: z.string().regex(/^[0-9a-f]{64}$/, "Please reload the page and try again."), // the fingerprint of the wording they were shown,
}); // End of the rules.

// Signs a contract.
export async function signContract(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Must be signed in.
  const parsed = signSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  if (formData.get("agree") !== "on") return { error: "Please tick that you have read the contract and agree to its terms." }; // Asks for the agreement.
  const supabase = await createClient(); // Connects as the staff member.
  const { error } = await supabase.rpc("employment_contract_sign", { // Signs it:
    p_id: parsed.data.id, // the contract,
    p_typed_name: parsed.data.typed_name, // the typed name,
    p_body_sha256: parsed.data.body_sha256, // the wording they saw,
    p_consent_electronic: formData.get("consent") === "on", // whether they agreed to sign electronically,
    p_pay_notice_shown: formData.get("pay_notice") === "shown", // and whether the pay notice was on the page.
  }); // End of the signing.
  if (error) return { error: problem(error, "Could not sign the contract. Please try again.") }; // Failed: says why.
  refresh(); // Refreshes the pages.
  return { message: "Signed. Thank you. Please now acknowledge each document below." }; // Confirms, with the next step.
} // End of signContract.

// The rules for acknowledging a document.
const acknowledgeSchema = z.object({ // The form's fields:
  id: z.uuid("That contract was not found."), // which contract,
  statement: z.string().regex(/^[a-z_]{2,40}$/, "That document was not found."), // which document,
  typed_name: z.string().trim().min(2, "Please type your full name.").max(200, "Please type your full name."), // their typed name.
}); // End of the rules.

// Acknowledges one document after signing.
export async function acknowledgeContractDocument(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Must be signed in.
  const parsed = acknowledgeSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  if (formData.get("read") !== "on") return { error: "Please tick that you have opened and read the document." }; // Asks for the tick.
  const supabase = await createClient(); // Connects as the staff member.
  const { error } = await supabase.rpc("employment_contract_acknowledge", { p_id: parsed.data.id, p_statement: parsed.data.statement, p_typed_name: parsed.data.typed_name }); // Records it.
  if (error) return { error: problem(error, "Could not save. Please try again.") }; // Failed: says why.
  refresh(); // Refreshes the pages.
  return { message: "Acknowledged." }; // Confirms it.
} // End of acknowledgeContractDocument.

