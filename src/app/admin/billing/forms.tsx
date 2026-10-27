"use client";

import {
  addCredit,
  addSchoolPeriod,
  buildInvoice,
  overridePause,
  runBillingNow,
  saveBillingSettings,
  saveFamilyBilling,
  saveKeptRate,
  savePrice,
  voidInvoice,
} from "@/app/actions/billing";
import { ActionForm } from "@/components/action-form";
import { Field, Select, TextArea } from "@/components/ui";
import { PLAN_LABELS } from "@/lib/billing/money";

type Option = { id: string; name: string };

export function FamilyPlanForm({
  familyId,
  plan,
  billPayerId,
  payers,
}: {
  familyId: string;
  plan: string;
  billPayerId: string | null;
  payers: Option[];
}) {
  return (
    <ActionForm action={saveFamilyBilling} submitLabel="Save plan">
      <input type="hidden" name="family_id" value={familyId} />
      <div className="grid gap-3 sm:grid-cols-2">
        <Select label="How often they pay" name="plan" defaultValue={plan}>
          {Object.entries(PLAN_LABELS).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </Select>
        <Select label="Bill payer" name="bill_payer_id" defaultValue={billPayerId ?? ""}>
          <option value="">Not chosen yet</option>
          {payers.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </Select>
      </div>
    </ActionForm>
  );
}

export function KeptRateForm({ familyId, prices }: { familyId: string; prices: Option[] }) {
  return (
    <ActionForm action={saveKeptRate} submitLabel="Save kept rate">
      <input type="hidden" name="family_id" value={familyId} />
      <div className="grid gap-3 sm:grid-cols-2">
        <Select label="Price" name="price_item_id" defaultValue={prices[0]?.id}>
          {prices.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </Select>
        <Field label="Their hourly rate ($)" name="amount" inputMode="decimal" hint="Leave empty to remove the kept rate." />
      </div>
      <Field label="Note (optional)" name="note" maxLength={500} placeholder="For example: existing family, kept rate" />
    </ActionForm>
  );
}

export function CreditForm({ familyId }: { familyId: string }) {
  return (
    <ActionForm action={addCredit} submitLabel="Add credit">
      <input type="hidden" name="family_id" value={familyId} />
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Amount ($)" name="amount" inputMode="decimal" required />
        <Field label="Reason" name="note" required minLength={5} maxLength={500} />
      </div>
    </ActionForm>
  );
}

export function OverrideForm({ familyId }: { familyId: string }) {
  return (
    <ActionForm action={overridePause} submitLabel="Lift the pause">
      <input type="hidden" name="family_id" value={familyId} />
      <p className="text-sm text-zinc-600">
        Only lift a pause without payment when there is a new due date or an agreed payment plan. If it isn&apos;t paid
        by the date you choose, the pause comes back on its own.
      </p>
      <Field label="Reason" name="reason" required minLength={5} maxLength={500} />
      <Field label="New due date, or next plan payment date" name="until" type="date" required />
      <TextArea label="Payment plan (if agreed)" name="payment_plan" maxLength={1000} placeholder="For example: $100 a week each Friday until paid" />
    </ActionForm>
  );
}

export function BuildInvoiceForm({ families }: { families: Option[] }) {
  return (
    <ActionForm action={buildInvoice} submitLabel="Build invoice">
      <p className="text-sm text-zinc-600">
        The daily run builds invoices on its own. Use this for an upfront booking or a one-off. Each session in the
        dates becomes one line; sessions already billed are skipped.
      </p>
      <Select label="Family" name="family_id" required defaultValue="">
        <option value="" disabled>
          Choose…
        </option>
        {families.map((f) => (
          <option key={f.id} value={f.id}>
            {f.name}
          </option>
        ))}
      </Select>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="From" name="from" type="date" required />
        <Field label="To" name="to" type="date" required />
      </div>
    </ActionForm>
  );
}

export function RunNowForm() {
  return (
    <ActionForm action={runBillingNow} submitLabel="Run billing now">
      <p className="text-sm text-zinc-600">
        Billing runs by itself every morning. This runs it now: builds invoices due to go out, gives cancellation
        credits, sends invoices to Xero, charges saved cards and bank debits that are due, and updates pauses.
      </p>
    </ActionForm>
  );
}

export function VoidInvoiceForm({ id }: { id: string }) {
  return (
    <ActionForm action={voidInvoice} submitLabel="Cancel invoice">
      <input type="hidden" name="id" value={id} />
      <Field label="Reason" name="reason" required minLength={5} maxLength={500} />
    </ActionForm>
  );
}

export function PriceForm({
  id,
  amount,
  gst,
  active,
}: {
  id: string;
  amount: string;
  gst: boolean;
  active: boolean;
}) {
  return (
    <ActionForm action={savePrice} submitLabel="Save">
      <input type="hidden" name="id" value={id} />
      <Field label="Price per hour ($, including any GST)" name="amount" defaultValue={amount} inputMode="decimal" required />
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" name="gst_applies" defaultChecked={gst} /> GST applies
      </label>
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" name="active" defaultChecked={active} /> In use
      </label>
    </ActionForm>
  );
}

export function SchoolPeriodForm() {
  return (
    <ActionForm action={addSchoolPeriod} submitLabel="Add">
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Name" name="name" required placeholder="Term 1 2027" />
        <Select label="Type" name="kind" defaultValue="term">
          <option value="term">School term</option>
          <option value="holidays">School holidays</option>
        </Select>
        <Field label="Starts" name="starts_on" type="date" required />
        <Field label="Ends" name="ends_on" type="date" required />
      </div>
      <input type="hidden" name="state" value="SA" />
    </ActionForm>
  );
}

export function SettingsForm({
  invoiceMode,
  overrideBy,
  showTutor,
}: {
  invoiceMode: string;
  overrideBy: string;
  showTutor: boolean;
}) {
  return (
    <ActionForm action={saveBillingSettings} submitLabel="Save settings">
      <Select label="New invoices in Xero" name="invoice_mode" defaultValue={invoiceMode}>
        <option value="awaiting_approval">Wait for my approval (pilot)</option>
        <option value="send">Approve and send automatically</option>
      </Select>
      <Select label="Who can lift a pause without payment" name="override_by" defaultValue={overrideBy}>
        <option value="owner">Only the owner</option>
        <option value="admin">Any admin</option>
      </Select>
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" name="show_tutor_on_invoice" defaultChecked={showTutor} /> Show the tutor&apos;s first
        name on invoice lines
      </label>
    </ActionForm>
  );
}
