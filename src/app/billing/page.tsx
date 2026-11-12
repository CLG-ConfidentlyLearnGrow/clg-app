// Summary: the families' Billing page: plan choice, automatic payment, payment terms and invoices.
//
import { payInvoiceNow, setUpAutomaticPayment } from "@/app/actions/billing"; // The server actions to pay an invoice and set up automatic payment.
import { Button, Card, Empty, Page, Table } from "@/components/ui"; // The button, card, "nothing yet" note, page frame and table.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { METHOD_LABELS, PLAN_LABELS, PLAN_SCOPE_NOTE, STATUS_LABELS, dollars, plainDate, type BillingMethod, type BillingPlan } from "@/lib/billing/money"; // Billing words and helpers: methods, plans, statuses, dollars, dates, and their types.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { ChoosePlanForm } from "./plan-form"; // The form for choosing a plan.
import { AcceptTermsForm } from "./terms-form"; // The form for agreeing to the payment terms.

// A family's billing account as the database gives it.
type Account = {
  family_id: string; // the family,
  bill_payer_id: string | null; // the bill payer (if chosen),
  plan: BillingPlan; // the plan,
  method: BillingMethod; // card or bank debit,
  payment_ready: boolean; // whether automatic payment is set up,
  terms_accepted_at: string | null; // when the terms were agreed (if they were),
  paused: boolean; // and whether support is paused.
}; // End of the shape.
// An invoice as the database gives it.
type Invoice = {
  id: string; // its id,
  number: string; // its number,
  family_id: string; // the family,
  status: keyof typeof STATUS_LABELS; // its status,
  due_on: string; // when it's due,
  charge_on: string; // when it will be charged,
  subtotal_cents: number; // total before GST,
  gst_cents: number; // the GST,
  discount_cents: number; // any discount,
  credit_applied_cents: number; // any credit used,
  total_cents: number; // the total,
  billing_invoice_lines: { id: string; description: string; amount_cents: number; line_date: string; active: boolean }[]; // its lines,
  billing_payments: { status: string }[]; // and its payments' statuses.
}; // End of the shape.

const NOTES: Record<string, string> = { // Messages for each note in the address:
  "setup=done": "Thanks. Your payment details are saved with Stripe. It can take a minute to show here.", // payment details saved,
  "setup=cancelled": "Payment set-up was cancelled. You can try again any time.", // set-up cancelled,
  "setup=not-connected": "Online payment isn't switched on yet. CLG will let you know when it is.", // online payment not on yet,
  "setup=missing": "We couldn't find your billing details. Please contact CLG.", // billing details not found,
  "paid=processing": "A payment for this invoice is already on its way.", // a payment already on its way.
}; // End of the list.

// Billing for families: plan, invoices, credit, and setting up automatic
// payment. Students under 18 only see whether support is on hold.
export default async function BillingPage({ searchParams }: PageProps<"/billing">) {
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const params = await searchParams; // Reads the address settings.
  const note = Object.entries(params) // The message to show:
    .map(([k, v]) => NOTES[`${k}=${v}`] ?? (k === "paid" ? `Thanks for paying invoice ${v}. It can take a minute to show here.` : null)) // a known note, or thanks for paying an invoice,
    .find(Boolean); // the first one found.
  const supabase = await createClient(); // Connects to the database.

  // This page is only ever about the person's own families. Someone who is
  // also an admin can see every family's billing in the admin screens, so the
  // reads below are limited to the families they pay for themselves.
  const [choices, myShares] = await Promise.all([ // Reads two things at once:
    supabase.rpc("billing_my_plan_choices"), // the families this person pays for (as a parent or adult learner), and their plan choice,
    supabase.from("billing_payers").select("family_id").eq("account_id", viewer.id), // and any family where they pay a split share.
  ]); // End of the reads.
  const myFamilies = [ // The ids of this person's own families:
    ...new Set([ // (each once)
      ...((choices.data ?? []) as { family_id: string }[]).map((c) => c.family_id), // the families they pay for,
      ...(myShares.data ?? []).map((r) => r.family_id), // plus the families where they pay a share.
    ]), // (end of the set)
  ]; // End of the list.

  const [accounts, families, invoices, onHold, splits] = await Promise.all([ // Reads five things at once:
    supabase.from("billing_accounts").select("family_id, bill_payer_id, plan, method, payment_ready, terms_accepted_at, paused").in("family_id", myFamilies), // their own families' billing accounts,
    supabase.from("families").select("id, name").in("id", myFamilies), // their own families' names,
    supabase // the invoices:
      .from("billing_invoices") // (from the invoices table)
      .select( // (with these fields:)
        "id, number, family_id, status, due_on, charge_on, subtotal_cents, gst_cents, discount_cents, credit_applied_cents, total_cents, billing_invoice_lines(id, description, amount_cents, line_date, active), billing_payments(status)", // totals, lines and payments,
      ) // (end of the fields)
      .in("family_id", myFamilies) // for their own families only,
      .neq("status", "void") // not cancelled,
      .order("due_on", { ascending: false }) // newest due date first,
      .limit(24), // at most 24;
    supabase.rpc("my_support_on_hold"), // whether this person's support is on hold,
    // Split payments: a payer sees their own row; the main payer sees the split.
    supabase.from("billing_payers").select("family_id, account_id, share_percent, method, payment_ready").in("family_id", myFamilies), // and split payment shares in their own families.
  ]); // End of the reads.
  const choiceRows = (choices.data ?? []) as { family_id: string; family_name: string; plan: BillingPlan; chosen: boolean; can_change: boolean }[]; // The plan choices.
  const choiceOf = new Map(choiceRows.map((c) => [c.family_id, c])); // Each family's plan choice, by family.
  const splitRows = (splits.data ?? []) as { family_id: string; account_id: string; share_percent: number; method: BillingMethod; payment_ready: boolean }[]; // The split shares.
  const accountRows = (accounts.data ?? []) as Account[]; // The billing accounts.
  const nameOf = new Map((families.data ?? []).map((f) => [f.id, f.name])); // Each family's name, by id.
  const invoiceRows = (invoices.data ?? []) as unknown as Invoice[]; // The invoices.
  const credit = new Map<string, number>(); // Each family's credit.
  await Promise.all( // Reads every family's credit at once:
    accountRows.map(async (a) => { // for each account:
      const { data } = await supabase.rpc("billing_credit_balance", { p_family: a.family_id }); // asks the database for the credit,
      credit.set(a.family_id, data ?? 0); // and keeps it.
    }), // (end of each account)
  ); // (end of the reads)
  // What this person still owes on each unpaid invoice: the whole invoice,
  // or their own share when the family splits its invoices.
  const owed = new Map<string, number>(); // What this person owes on each unpaid invoice.
  await Promise.all( // Works it out for every unpaid invoice at once:
    invoiceRows // (the invoices)
      .filter((i) => i.status === "open") // only unpaid ones,
      .map(async (i) => { // for each:
        const { data } = await supabase.rpc("billing_invoice_payers", { p_invoice: i.id }); // asks who pays what,
        const rows = (data ?? []) as { payer_id: string | null; amount_cents: number; paid_cents: number; pending_cents: number }[]; // the payers' shares,
        const mine = rows.length === 1 ? rows[0] : rows.find((r) => r.payer_id === viewer.id); // their share (or the only one),
        if (mine) owed.set(i.id, Math.max(0, mine.amount_cents - mine.paid_cents - mine.pending_cents)); // and keeps what's still owed.
      }), // (end of each invoice)
  ); // (end of the work)

  return ( // Shows:
    <Page title="Billing" intro="Your plan, invoices and credit with CLG.">{/* a page titled "Billing": */}
      {note && <p className="rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm text-teal-900">{note}</p>}{/* the message, if any, */}

      {onHold.data === true && accountRows.length === 0 && ( // on hold with no billing of their own (e.g. a student):
        <Card title="Sessions on hold">{/* a card: */}
          <p className="text-sm">Your sessions are on hold for now. Please check with your parent or carer.</p>{/* saying sessions are on hold. */}
        </Card> // End of the card.
      )}{/* End of that part. */}

      {choiceRows // The plan choices:
        .filter((c) => !c.chosen && c.can_change) // not chosen yet and still changeable,
        .map((c) => ( // for each:
          <Card // a card:
            key={`plan-${c.family_id}`} // (its key)
            title={choiceRows.length > 1 ? `How often would you like to pay? (${c.family_name})` : "How often would you like to pay?"} // titled with the question (and family name if more than one),
            description="Please choose before your first invoice. You can change it until CLG sends that invoice." // with when to choose by.
          >{/* (end of the card's settings) */}
            <ChoosePlanForm familyId={c.family_id} plan={c.plan} chosen={false} />{/* The plan form. */}
          </Card> // End of the card.
        ))}{/* End of the loop. */}

      {accountRows.length === 0 && choiceRows.length === 0 && onHold.data !== true && ( // No billing at all:
        <Empty>There is no billing for you yet. CLG sets this up once sessions are booked.</Empty> // says so.
      )}{/* End of that part. */}

      {accountRows.map((a) => { // For each billing account:
        const open = invoiceRows.filter((i) => i.family_id === a.family_id && i.status === "open"); // its unpaid invoices,
        const familySplits = splitRows.filter((r) => r.family_id === a.family_id); // its split shares,
        const myShare = familySplits.find((r) => r.account_id === viewer.id); // this person's share (if they're a second payer),
        const mainShare = 100 - familySplits.reduce((t, r) => t + r.share_percent, 0); // the main payer's share,
        const ready = myShare ? myShare.payment_ready : a.payment_ready; // whether this person's automatic payment is set up,
        const method = myShare ? myShare.method : a.method; // and their payment method.
        return ( // Shows:
          <div key={a.family_id} className="space-y-6">{/* a block with space between parts: */}
            {a.paused && ( // if paused:
              <Card title="Sessions on hold">{/* a card: */}
                <p className="text-sm">{/* a line: */}
                  Sessions for your family are on hold because an invoice is overdue. Pay it below and sessions start
                  again straight away. Your tutor has been told the sessions are on hold, but not why.{/* why, and how to start again. */}
                </p>{/* End of the line. */}
              </Card> // End of the card.
            )}{/* End of that part. */}

            <Card title={nameOf.get(a.family_id) ?? "Your family"}>{/* A card named after the family: */}
              <dl className="grid gap-2 text-sm sm:grid-cols-3">{/* three columns on wider screens: */}
                <div>{/* a group: */}
                  <dt className="text-zinc-500">Plan</dt>{/* "Plan", */}
                  <dd>{choiceOf.get(a.family_id)?.chosen === false ? "Not chosen yet" : PLAN_LABELS[a.plan]}</dd>{/* the plan (or "Not chosen yet"). */}
                </div>{/* End of the group. */}
                <div>{/* A group: */}
                  <dt className="text-zinc-500">Automatic payment</dt>{/* "Automatic payment", */}
                  <dd>{ready ? METHOD_LABELS[method] : "Not set up yet"}</dd>{/* the method (or "Not set up yet"). */}
                </div>{/* End of the group. */}
                <div>{/* A group: */}
                  <dt className="text-zinc-500">Credit</dt>{/* "Credit", */}
                  <dd>{dollars(credit.get(a.family_id))}</dd>{/* the credit. */}
                </div>{/* End of the group. */}
              </dl>{/* End of the columns. */}
              <form action={setUpAutomaticPayment} className="mt-4">{/* A form that sets up automatic payment: */}
                <input type="hidden" name="family_id" value={a.family_id} />{/* the family (hidden), */}
                <Button type="submit">{ready ? "Change card or bank account" : "Set up automatic payment"}</Button>{/* the button, worded for set up or change. */}
              </form>{/* End of the form. */}
              {choiceOf.get(a.family_id)?.chosen && choiceOf.get(a.family_id)?.can_change && ( // If they chose a plan and can still change it:
                <details className="mt-4 text-sm">{/* a section that opens when clicked: */}
                  <summary className="cursor-pointer">Change how often you pay</summary>{/* its heading, */}
                  <div className="mt-3">{/* a block: */}
                    <ChoosePlanForm familyId={a.family_id} plan={a.plan} chosen />{/* the plan form. */}
                  </div>{/* End of the block. */}
                </details> // End of the section.
              )}{/* End of that part. */}
              {myShare && ( // If they're a second payer:
                <p className="mt-3 text-sm">{/* a line: */}
                  Your family&apos;s invoices are shared. You pay {myShare.share_percent}% of each one from your own card or
                  bank account, and another payer pays the rest.{/* their share and that another payer pays the rest. */}
                </p> // End of the line.
              )}{/* End of that part. */}
              {!myShare && familySplits.length > 0 && a.bill_payer_id === viewer.id && ( // If they're the main payer of a split family:
                <p className="mt-3 text-sm">{/* a line: */}
                  Your family&apos;s invoices are shared. You pay {mainShare}% of each one, and the other payer pays the rest
                  from their own card or bank account.{/* their share and that the other payer pays the rest. */}
                </p> // End of the line.
              )}{/* End of that part. */}
              <p className="mt-2 text-xs text-zinc-500">{/* A small grey note: */}
                You enter your card or bank details on Stripe&apos;s secure page. CLG never sees or stores them.{/* card details go to Stripe, */}
                {a.plan === "weekly" // weekly plans:
                  ? " Weekly plans pay by card." // pay by card,
                  : " Bank debit gets a small discount, because it costs CLG less."}{/* other plans: bank debit gets a discount. */}
              </p>{/* End of the note. */}
            </Card>{/* End of the card. */}

            {!a.terms_accepted_at && ( // If the terms aren't agreed:
              <Card title="Payment terms" description="Please read and agree before your first invoice.">{/* a card: */}
                <ul className="mb-4 list-disc space-y-1 pl-5 text-sm">{/* a bulleted list: */}
                  <li>{PLAN_SCOPE_NOTE}</li>{/* what the plan covers, */}
                  <li>Sessions are paid in advance. Weekly and monthly invoices are due 4 days before the first session; per term invoices 1 week before.</li>{/* paying in advance, */}
                  <li>Weekly and monthly plans pay automatically, by saved card (weekly) or card or bank debit (monthly).</li>{/* automatic payment, */}
                  <li>If an invoice is overdue, all your family&apos;s sessions go on hold until it is paid.</li>{/* holds when overdue, */}
                  <li>Cancel more than 24 hr before a session for full credit, or 2 to 24 hr before for half credit. Under 2 hr or a missed session gets no credit. If CLG or the tutor cancels, you get full credit.</li>{/* cancellations, */}
                  <li>Credit comes off your next invoice for any CLG service. Refunds are given where the law requires.</li>{/* credits and refunds. */}
                </ul>{/* End of the list. */}
                <AcceptTermsForm familyId={a.family_id} />{/* The agree form. */}
              </Card> // End of the card.
            )}{/* End of that part. */}

            <Card title="Invoices">{/* A card of invoices: */}
              {invoiceRows.filter((i) => i.family_id === a.family_id).length === 0 ? ( // if none:
                <Empty>No invoices yet.</Empty> // says so.
              ) : ( // Otherwise:
                <div className="space-y-6">{/* a block with space between parts: */}
                  {invoiceRows // the invoices:
                    .filter((i) => i.family_id === a.family_id) // this family's,
                    .map((i) => { // for each:
                      const pending = i.billing_payments.some((p) => p.status === "processing"); // true if a payment is on its way.
                      return ( // Shows:
                        <div key={i.id}>{/* a block: */}
                          <div className="mb-2 flex flex-wrap items-center justify-between gap-2 text-sm">{/* a row: */}
                            <span>{/* the words: */}
                              <strong>{i.number}</strong> · due {plainDate(i.due_on)} · {pending ? "Payment on its way" : STATUS_LABELS[i.status]}{/* number, due date and status. */}
                            </span>{/* End of the words. */}
                            {open.includes(i) && (owed.get(i.id) ?? 0) > 0 && ( // If unpaid and they owe something:
                              <form action={payInvoiceNow}>{/* a form that pays it: */}
                                <input type="hidden" name="id" value={i.id} />{/* which invoice (hidden), */}
                                <Button type="submit">{/* the button: */}
                                  Pay {dollars(owed.get(i.id))} now{(owed.get(i.id) ?? 0) < i.total_cents ? " (your share)" : ""}{/* "Pay $X now", noting if it's their share. */}
                                </Button>{/* End of the button. */}
                              </form> // End of the form.
                            )}{/* End of that part. */}
                          </div>{/* End of the row. */}
                          <Table headings={["Session", "Amount"]}>{/* A table with these headings: */}
                            {i.billing_invoice_lines // the lines:
                              .filter((l) => l.active) // only active ones,
                              .sort((x, y) => x.line_date.localeCompare(y.line_date)) // in date order,
                              .map((l) => ( // for each:
                                <tr key={l.id}>{/* a row: */}
                                  <td>{l.description}</td>{/* the description, */}
                                  <td>{dollars(l.amount_cents)}</td>{/* the amount. */}
                                </tr> // End of the row.
                              ))}{/* End of the lines. */}
                            {i.credit_applied_cents > 0 && ( // If credit was used:
                              <tr>{/* a row: */}
                                <td>Credit used</td>{/* "Credit used", */}
                                <td>−{dollars(i.credit_applied_cents)}</td>{/* the amount taken off. */}
                              </tr> // End of the row.
                            )}{/* End of that part. */}
                            {i.discount_cents > 0 && ( // If there's a bank debit discount:
                              <tr>{/* a row: */}
                                <td>Bank debit discount</td>{/* "Bank debit discount", */}
                                <td>−{dollars(i.discount_cents)}</td>{/* the amount taken off. */}
                              </tr> // End of the row.
                            )}{/* End of that part. */}
                            <tr>{/* A row: */}
                              <td className="font-semibold">Total{i.gst_cents > 0 ? ` (includes GST ${dollars(i.gst_cents)})` : ""}</td>{/* "Total" (with GST if any), */}
                              <td className="font-semibold">{dollars(i.total_cents)}</td>{/* the total. */}
                            </tr>{/* End of the row. */}
                          </Table>{/* End of the table. */}
                        </div> // End of the block.
                      ); // End of what's shown for this invoice.
                    })}{/* End of the invoices loop. */}
                </div> // End of the block.
              )}{/* End of the choice. */}
            </Card>{/* End of the card. */}
          </div> // End of the block.
        ); // End of what's shown for this account.
      })}{/* End of the accounts loop. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of BillingPage.
