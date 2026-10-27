import { payInvoiceNow, setUpAutomaticPayment } from "@/app/actions/billing";
import { Button, Card, Empty, Page, Table } from "@/components/ui";
import { requireViewer } from "@/lib/auth";
import { METHOD_LABELS, PLAN_LABELS, STATUS_LABELS, dollars, plainDate, type BillingMethod, type BillingPlan } from "@/lib/billing/money";
import { createClient } from "@/lib/supabase/server";
import { AcceptTermsForm } from "./terms-form";

type Account = {
  family_id: string;
  plan: BillingPlan;
  method: BillingMethod;
  payment_ready: boolean;
  terms_accepted_at: string | null;
  paused: boolean;
};
type Invoice = {
  id: string;
  number: string;
  family_id: string;
  status: keyof typeof STATUS_LABELS;
  due_on: string;
  charge_on: string;
  subtotal_cents: number;
  gst_cents: number;
  discount_cents: number;
  credit_applied_cents: number;
  total_cents: number;
  billing_invoice_lines: { id: string; description: string; amount_cents: number; line_date: string; active: boolean }[];
  billing_payments: { status: string }[];
};

const NOTES: Record<string, string> = {
  "setup=done": "Thanks. Your payment details are saved with Stripe. It can take a minute to show here.",
  "setup=cancelled": "Payment set-up was cancelled. You can try again any time.",
  "setup=not-connected": "Online payment isn't switched on yet. CLG will let you know when it is.",
  "setup=missing": "We couldn't find your billing details. Please contact CLG.",
  "paid=processing": "A payment for this invoice is already on its way.",
};

// Billing for families: plan, invoices, credit, and setting up automatic
// payment. Students under 18 only see whether support is on hold.
export default async function BillingPage({ searchParams }: PageProps<"/billing">) {
  await requireViewer();
  const params = await searchParams;
  const note = Object.entries(params)
    .map(([k, v]) => NOTES[`${k}=${v}`] ?? (k === "paid" ? `Thanks for paying invoice ${v}. It can take a minute to show here.` : null))
    .find(Boolean);
  const supabase = await createClient();

  const [accounts, families, invoices, onHold] = await Promise.all([
    supabase.from("billing_accounts").select("family_id, plan, method, payment_ready, terms_accepted_at, paused"),
    supabase.from("families").select("id, name"),
    supabase
      .from("billing_invoices")
      .select(
        "id, number, family_id, status, due_on, charge_on, subtotal_cents, gst_cents, discount_cents, credit_applied_cents, total_cents, billing_invoice_lines(id, description, amount_cents, line_date, active), billing_payments(status)",
      )
      .neq("status", "void")
      .order("due_on", { ascending: false })
      .limit(24),
    supabase.rpc("my_support_on_hold"),
  ]);
  const accountRows = (accounts.data ?? []) as Account[];
  const nameOf = new Map((families.data ?? []).map((f) => [f.id, f.name]));
  const invoiceRows = (invoices.data ?? []) as unknown as Invoice[];
  const credit = new Map<string, number>();
  await Promise.all(
    accountRows.map(async (a) => {
      const { data } = await supabase.rpc("billing_credit_balance", { p_family: a.family_id });
      credit.set(a.family_id, data ?? 0);
    }),
  );

  return (
    <Page title="Billing" intro="Your plan, invoices and credit with CLG.">
      {note && <p className="rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm text-teal-900">{note}</p>}

      {onHold.data === true && accountRows.length === 0 && (
        <Card title="Sessions on hold">
          <p className="text-sm">Your sessions are on hold for now. Please check with your parent or carer.</p>
        </Card>
      )}

      {accountRows.length === 0 && onHold.data !== true && (
        <Empty>There is no billing for you yet. CLG sets this up once sessions are booked.</Empty>
      )}

      {accountRows.map((a) => {
        const open = invoiceRows.filter((i) => i.family_id === a.family_id && i.status === "open");
        return (
          <div key={a.family_id} className="space-y-6">
            {a.paused && (
              <Card title="Sessions on hold">
                <p className="text-sm">
                  Sessions for your family are on hold because an invoice is overdue. Pay it below and sessions start
                  again straight away. Your tutor has been told the sessions are on hold, but not why.
                </p>
              </Card>
            )}

            <Card title={nameOf.get(a.family_id) ?? "Your family"}>
              <dl className="grid gap-2 text-sm sm:grid-cols-3">
                <div>
                  <dt className="text-zinc-500">Plan</dt>
                  <dd>{PLAN_LABELS[a.plan]}</dd>
                </div>
                <div>
                  <dt className="text-zinc-500">Automatic payment</dt>
                  <dd>{a.payment_ready ? METHOD_LABELS[a.method] : "Not set up yet"}</dd>
                </div>
                <div>
                  <dt className="text-zinc-500">Credit</dt>
                  <dd>{dollars(credit.get(a.family_id))}</dd>
                </div>
              </dl>
              <form action={setUpAutomaticPayment} className="mt-4">
                <input type="hidden" name="family_id" value={a.family_id} />
                <Button type="submit">{a.payment_ready ? "Change card or bank account" : "Set up automatic payment"}</Button>
              </form>
              <p className="mt-2 text-xs text-zinc-500">
                You enter your card or bank details on Stripe&apos;s secure page. CLG never sees or stores them.
                {a.plan === "weekly"
                  ? " Weekly plans pay by card."
                  : " Bank debit gets a small discount, because it costs CLG less."}
              </p>
            </Card>

            {!a.terms_accepted_at && (
              <Card title="Payment terms" description="Please read and agree before your first invoice.">
                <ul className="mb-4 list-disc space-y-1 pl-5 text-sm">
                  <li>Sessions are paid in advance. Weekly and monthly invoices are due 4 days before the first session; per term invoices 1 week before.</li>
                  <li>Weekly and monthly plans pay automatically, by saved card (weekly) or card or bank debit (monthly).</li>
                  <li>If an invoice is overdue, all your family&apos;s sessions go on hold until it is paid.</li>
                  <li>Cancel more than 24 hr before a session for full credit, or 2 to 24 hr before for half credit. Under 2 hr or a missed session gets no credit. If CLG or the tutor cancels, you get full credit.</li>
                  <li>Credit comes off your next invoice for any CLG service. Refunds are given where the law requires.</li>
                </ul>
                <AcceptTermsForm familyId={a.family_id} />
              </Card>
            )}

            <Card title="Invoices">
              {invoiceRows.filter((i) => i.family_id === a.family_id).length === 0 ? (
                <Empty>No invoices yet.</Empty>
              ) : (
                <div className="space-y-6">
                  {invoiceRows
                    .filter((i) => i.family_id === a.family_id)
                    .map((i) => {
                      const pending = i.billing_payments.some((p) => p.status === "processing");
                      return (
                        <div key={i.id}>
                          <div className="mb-2 flex flex-wrap items-center justify-between gap-2 text-sm">
                            <span>
                              <strong>{i.number}</strong> · due {plainDate(i.due_on)} · {pending ? "Payment on its way" : STATUS_LABELS[i.status]}
                            </span>
                            {open.includes(i) && !pending && (
                              <form action={payInvoiceNow}>
                                <input type="hidden" name="id" value={i.id} />
                                <Button type="submit">Pay {dollars(i.total_cents)} now</Button>
                              </form>
                            )}
                          </div>
                          <Table headings={["Session", "Amount"]}>
                            {i.billing_invoice_lines
                              .filter((l) => l.active)
                              .sort((x, y) => x.line_date.localeCompare(y.line_date))
                              .map((l) => (
                                <tr key={l.id}>
                                  <td>{l.description}</td>
                                  <td>{dollars(l.amount_cents)}</td>
                                </tr>
                              ))}
                            {i.credit_applied_cents > 0 && (
                              <tr>
                                <td>Credit used</td>
                                <td>−{dollars(i.credit_applied_cents)}</td>
                              </tr>
                            )}
                            {i.discount_cents > 0 && (
                              <tr>
                                <td>Bank debit discount</td>
                                <td>−{dollars(i.discount_cents)}</td>
                              </tr>
                            )}
                            <tr>
                              <td className="font-semibold">Total{i.gst_cents > 0 ? ` (includes GST ${dollars(i.gst_cents)})` : ""}</td>
                              <td className="font-semibold">{dollars(i.total_cents)}</td>
                            </tr>
                          </Table>
                        </div>
                      );
                    })}
                </div>
              )}
            </Card>
          </div>
        );
      })}
    </Page>
  );
}
