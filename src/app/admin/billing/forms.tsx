// Summary: admin billing forms: family plan, split payers, kept rates, credits, pauses, invoices,
// the billing run, prices, school periods and settings.
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { // The server actions for these forms:
  addCredit, // add a credit,
  addSchoolPeriod, // add a school term or holiday,
  buildInvoice, // build an invoice,
  overridePause, // lift a pause,
  runBillingNow, // run billing now,
  saveBillingSettings, // save billing settings,
  saveFamilyBilling, // save a family's plan,
  saveKeptRate, // save a kept rate,
  savePrice, // save a price,
  saveSplit, // save a split,
  voidInvoice, // cancel an invoice.
} from "@/app/actions/billing"; // (end of the list)
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // The input box, drop-down list and larger text box.
import { PLAN_LABELS } from "@/lib/billing/money"; // The names of each payment plan.

type Option = { id: string; name: string }; // An item in a drop-down: its id and name.

// The form for a family's payment plan and bill payer.
export function FamilyPlanForm({
  familyId, // the family,
  plan, // their current plan,
  billPayerId, // the current bill payer,
  payers, // and the people who can pay.
}: { // (their types:)
  familyId: string; // an id,
  plan: string; // text,
  billPayerId: string | null; // an id or nothing,
  payers: Option[]; // a list of people.
}) { // (end of the settings)
  return ( // Shows:
    <ActionForm action={saveFamilyBilling} submitLabel="Save plan">{/* a form that saves the plan: */}
      <input type="hidden" name="family_id" value={familyId} />{/* the family (hidden), */}
      <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="How often they pay" name="plan" defaultValue={plan}>{/* a drop-down of plans: */}
          {Object.entries(PLAN_LABELS).map(([value, label]) => ( // for each plan:
            <option key={value} value={value}>{/* an option: */}
              {label}{/* its name. */}
            </option> // (end of the option)
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <Select label="Bill payer" name="bill_payer_id" defaultValue={billPayerId ?? ""}>{/* A drop-down of bill payers: */}
          <option value="">Not chosen yet</option>{/* not chosen yet, */}
          {payers.map((p) => ( // for each person:
            <option key={p.id} value={p.id}>{/* an option: */}
              {p.name}{/* their name. */}
            </option> // (end of the option)
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
      </div>{/* End of the columns. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of FamilyPlanForm.

// The form for adding a second payer and their share.
export function SplitForm({ familyId, payers }: { familyId: string; payers: Option[] }) {
  return ( // Shows:
    <ActionForm action={saveSplit} submitLabel="Save split">{/* a form that saves the split: */}
      <input type="hidden" name="family_id" value={familyId} />{/* the family (hidden), */}
      <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="Also pays" name="payer_id" required defaultValue="">{/* a drop-down of people: */}
          <option value="" disabled>{/* a blank first option that can't be picked: */}
            Choose…{/* "Choose…", */}
          </option>{/* (end of the option) */}
          {payers.map((p) => ( // for each person:
            <option key={p.id} value={p.id}>{/* an option: */}
              {p.name}{/* their name. */}
            </option> // (end of the option)
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <Field label="Their share (%)" name="share" inputMode="numeric" required placeholder="50" />{/* Their share as a percentage. */}
      </div>{/* End of the columns. */}
      <p className="text-xs text-zinc-500">{/* A small grey note: */}
        The bill payer pays the rest. Each payer saves their own card or bank debit and sees only their own share and
        payments. Applies to invoices made from now on.{/* how splits work. */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SplitForm.

// The form for keeping an existing family's old hourly rate.
export function KeptRateForm({ familyId, prices }: { familyId: string; prices: Option[] }) {
  return ( // Shows:
    <ActionForm action={saveKeptRate} submitLabel="Save kept rate">{/* a form that saves the kept rate: */}
      <input type="hidden" name="family_id" value={familyId} />{/* the family (hidden), */}
      <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="Price" name="price_item_id" defaultValue={prices[0]?.id}>{/* a drop-down of prices: */}
          {prices.map((p) => ( // for each price:
            <option key={p.id} value={p.id}>{/* an option: */}
              {p.name}{/* its name. */}
            </option> // (end of the option)
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <Field label="Their hourly rate ($)" name="amount" inputMode="decimal" hint="Leave empty to remove the kept rate." />{/* Their hourly rate (blank removes it). */}
      </div>{/* End of the columns. */}
      <Field label="Note (optional)" name="note" maxLength={500} placeholder="For example: existing family, kept rate" />{/* A note (optional). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of KeptRateForm.

// The form for giving a family a credit.
export function CreditForm({ familyId }: { familyId: string }) {
  return ( // Shows:
    <ActionForm action={addCredit} submitLabel="Add credit">{/* a form that adds the credit: */}
      <input type="hidden" name="family_id" value={familyId} />{/* the family (hidden), */}
      <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label="Amount ($)" name="amount" inputMode="decimal" required />{/* the amount, */}
        <Field label="Reason" name="note" required minLength={5} maxLength={500} />{/* the reason. */}
      </div>{/* End of the columns. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of CreditForm.

// The form for lifting a family's pause without payment.
export function OverrideForm({ familyId }: { familyId: string }) {
  return ( // Shows:
    <ActionForm action={overridePause} submitLabel="Lift the pause">{/* a form that lifts the pause: */}
      <input type="hidden" name="family_id" value={familyId} />{/* the family (hidden), */}
      <p className="text-sm text-zinc-600">{/* a grey note: */}
        Only lift a pause without payment when there is a new due date or an agreed payment plan. If it isn&apos;t paid
        by the date you choose, the pause comes back on its own.{/* when to use this, and what happens if it isn't paid. */}
      </p>{/* End of the note. */}
      <Field label="Reason" name="reason" required minLength={5} maxLength={500} />{/* The reason, */}
      <Field label="New due date, or next plan payment date" name="until" type="date" required />{/* the new due date, */}
      <TextArea label="Payment plan (if agreed)" name="payment_plan" maxLength={1000} placeholder="For example: $100 a week each Friday until paid" />{/* and the payment plan (if agreed). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of OverrideForm.

// The form for building an invoice by hand.
export function BuildInvoiceForm({ families }: { families: Option[] }) {
  return ( // Shows:
    <ActionForm action={buildInvoice} submitLabel="Build invoice">{/* a form that builds the invoice: */}
      <p className="text-sm text-zinc-600">{/* a grey note: */}
        The daily run builds invoices on its own. Use this for an upfront booking or a one-off. Each session in the
        dates becomes one line; sessions already billed are skipped.{/* when to use this and how lines are made. */}
      </p>{/* End of the note. */}
      <Select label="Family" name="family_id" required defaultValue="">{/* A drop-down of families: */}
        <option value="" disabled>{/* a blank first option that can't be picked: */}
          Choose…{/* "Choose…", */}
        </option>{/* (end of the option) */}
        {families.map((f) => ( // for each family:
          <option key={f.id} value={f.id}>{/* an option: */}
            {f.name}{/* its name. */}
          </option> // (end of the option)
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <div className="grid gap-3 sm:grid-cols-2">{/* Two columns on wider screens: */}
        <Field label="From" name="from" type="date" required />{/* from, */}
        <Field label="To" name="to" type="date" required />{/* to. */}
      </div>{/* End of the columns. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of BuildInvoiceForm.

// A button to run billing now.
export function RunNowForm() {
  return ( // Shows:
    <ActionForm action={runBillingNow} submitLabel="Run billing now">{/* a form that runs billing: */}
      <p className="text-sm text-zinc-600">{/* a grey note: */}
        Billing runs by itself every morning. This runs it now: builds invoices due to go out, gives cancellation
        credits, sends invoices to Xero, charges saved cards and bank debits that are due, and updates pauses.{/* what the run does. */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of RunNowForm.

// The form for cancelling an invoice with a reason.
export function VoidInvoiceForm({ id }: { id: string }) {
  return ( // Shows:
    <ActionForm action={voidInvoice} submitLabel="Cancel invoice">{/* a form that cancels it: */}
      <input type="hidden" name="id" value={id} />{/* which invoice (hidden), */}
      <Field label="Reason" name="reason" required minLength={5} maxLength={500} />{/* the reason. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of VoidInvoiceForm.

// The form for one price.
export function PriceForm({
  id, // which price,
  amount, // its amount,
  gst, // whether GST applies,
  active, // and whether it's in use.
}: { // (their types:)
  id: string; // an id,
  amount: string; // text,
  gst: boolean; // true or false,
  active: boolean; // true or false.
}) { // (end of the settings)
  return ( // Shows:
    <ActionForm action={savePrice} submitLabel="Save">{/* a form that saves the price: */}
      <input type="hidden" name="id" value={id} />{/* which price (hidden), */}
      <Field label="Price per hour ($, including any GST)" name="amount" defaultValue={amount} inputMode="decimal" required />{/* the price per hour, */}
      <label className="flex items-center gap-2 text-sm">{/* a line holding: */}
        <input type="checkbox" name="gst_applies" defaultChecked={gst} /> GST applies{/* a tick box for GST. */}
      </label>{/* End of the line. */}
      <label className="flex items-center gap-2 text-sm">{/* A line holding: */}
        <input type="checkbox" name="active" defaultChecked={active} /> In use{/* a tick box for "in use". */}
      </label>{/* End of the line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of PriceForm.

// The form for adding a school term or holidays.
export function SchoolPeriodForm() {
  return ( // Shows:
    <ActionForm action={addSchoolPeriod} submitLabel="Add">{/* a form that adds it: */}
      <div className="grid gap-3 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field label="Name" name="name" required placeholder="Term 1 2027" />{/* its name, */}
        <Select label="Type" name="kind" defaultValue="term">{/* a drop-down of type: */}
          <option value="term">School term</option>{/* school term, */}
          <option value="holidays">School holidays</option>{/* school holidays. */}
        </Select>{/* End of the drop-down. */}
        <Field label="Starts" name="starts_on" type="date" required />{/* When it starts, */}
        <Field label="Ends" name="ends_on" type="date" required />{/* when it ends. */}
      </div>{/* End of the columns. */}
      <input type="hidden" name="state" value="SA" />{/* South Australia (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SchoolPeriodForm.

// The form for billing settings.
export function SettingsForm({
  invoiceMode, // how new invoices go to Xero,
  overrideBy, // who can lift a pause,
  showTutor, // and whether to show the tutor on invoices.
}: { // (their types:)
  invoiceMode: string; // text,
  overrideBy: string; // text,
  showTutor: boolean; // true or false.
}) { // (end of the settings)
  return ( // Shows:
    <ActionForm action={saveBillingSettings} submitLabel="Save settings">{/* a form that saves the settings: */}
      <Select label="New invoices in Xero" name="invoice_mode" defaultValue={invoiceMode}>{/* a drop-down for new invoices: */}
        <option value="awaiting_approval">Wait for my approval (pilot)</option>{/* wait for approval, */}
        <option value="send">Approve and send automatically</option>{/* send automatically. */}
      </Select>{/* End of the drop-down. */}
      <Select label="Who can lift a pause without payment" name="override_by" defaultValue={overrideBy}>{/* A drop-down for who can lift a pause: */}
        <option value="owner">Only the owner</option>{/* only the owner, */}
        <option value="admin">Any admin</option>{/* any admin. */}
      </Select>{/* End of the drop-down. */}
      <label className="flex items-center gap-2 text-sm">{/* A line holding: */}
        <input type="checkbox" name="show_tutor_on_invoice" defaultChecked={showTutor} /> Show the tutor&apos;s first
        name on invoice lines{/* a tick box to show the tutor's first name on invoices. */}
      </label>{/* End of the line. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SettingsForm.
