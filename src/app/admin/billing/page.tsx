// Summary: the admin Billing page: family plans and splits, invoices, staff pay,
// prices and settings, and the Stripe and Xero connections.
//
import { approveInvoice, removeSplit } from "@/app/actions/billing"; // The billing actions: approve an invoice, remove a split payer.
import { RoleTabs } from "@/components/role-tabs"; // The tabs for each dashboard the person can use.
import { getToDoCounts } from "@/lib/to-do-counts"; // Reads the to-do numbers.
import { SectionShell } from "@/components/section-shell"; // The page frame with a side menu.
import { Button, Card, Empty, SubHeading, Table, TextLink } from "@/components/ui"; // Shared page parts: button, card, empty line, small heading, table and text link.
import { FINANCE, PAY, requireAdminLevel } from "@/lib/auth"; // Admin levels that can see billing and staff pay, and the level check.
import { stripeIsTestMode, stripeKey, xeroConfig } from "@/lib/billing/config"; // Stripe and Xero setting readers.
import { METHOD_LABELS, PLAN_LABELS, STATUS_LABELS, dollars, plainDate, type BillingMethod, type BillingPlan } from "@/lib/billing/money"; // Billing labels, money and date formatting, and their types.
import { adelaideToday } from "@/lib/billing/run"; // Today's date in Adelaide.
import { xeroConnection } from "@/lib/billing/xero"; // Reads the Xero connection.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { // The billing forms:
  BuildInvoiceForm, // build an invoice by hand,
  CreditForm, // add credit,
  FamilyPlanForm, // a family's plan,
  KeptRateForm, // a family's kept rate,
  OverrideForm, // lift a pause without payment,
  PriceForm, // a price,
  RunNowForm, // run billing now,
  SchoolPeriodForm, // a school term or holiday,
  SettingsForm, // billing settings,
  SplitForm, // a split payer,
  VoidInvoiceForm, // cancel an invoice.
} from "./forms"; // End of the forms.
import { PaySection } from "./pay-section"; // The staff pay section.

const SECTIONS = [ // The side menu's sections:
  { id: "families", label: "Family billing" }, // family billing,
  { id: "invoices", label: "Invoices" }, // invoices,
  { id: "pay", label: "Staff pay" }, // staff pay,
  { id: "prices", label: "Prices and settings" }, // prices and settings,
  { id: "connections", label: "Stripe and Xero" }, // Stripe and Xero.
] as const; // End of the sections.

type Family = { // A family as read here:
  id: string; // its id,
  name: string; // its name,
  students: { // its students:
    full_name: string; // each student's name,
    parent_student_links: { parent_id: string; parent: { account: { full_name: string } | null } | null }[]; // and their parents' ids and names.
  }[]; // (end of a student)
}; // End of Family.
type Account = { // A family's billing account:
  family_id: string; // the family,
  plan: BillingPlan; // their plan,
  method: BillingMethod; // how they pay,
  payment_ready: boolean; // whether automatic payment is set up,
  bill_payer_id: string | null; // the bill payer (if chosen),
  terms_accepted_at: string | null; // when terms were accepted (if yet),
  plan_chosen_at: string | null; // when the plan was chosen (if yet),
  paused: boolean; // whether support is paused,
  paused_since: string | null; // since when (if paused).
}; // End of Account.
type Invoice = { // An invoice as listed:
  id: string; // its id,
  number: string; // its number,
  family_name: string; // the family's name,
  status: keyof typeof STATUS_LABELS; // its status,
  period_start: string; // the first session date,
  period_end: string; // the last session date,
  send_on: string; // when it's sent,
  due_on: string; // when it's due,
  total_cents: number; // the total (in cents),
  credit_applied_cents: number; // credit used (in cents),
  discount_cents: number; // discount (in cents),
  xero_invoice_id: string | null; // and its Xero id (if sent there).
}; // End of Invoice.

// Xero connection messages after the owner comes back from Xero.
const XERO_NOTES: Record<string, string> = { // The messages:
  connected: "Xero is connected.", // connected,
  failed: "Xero didn't connect. Please try again, and check the Xero app settings.", // failed,
  "owner-only": "Only the owner can connect Xero.", // someone other than the owner tried.
}; // End of the messages.

export default async function AdminBillingPage({ searchParams }: PageProps<"/admin/billing">) { // The page itself (reads the address's settings).
  const viewer = await requireAdminLevel(FINANCE); // Must be an admin with billing access.
  const params = await searchParams; // The address's settings.
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "families"; // Which section is open (families if none or unknown).
  const supabase = await createClient(); // Connects to the database.

  const [me, families, accounts, rates, prices, credits, invoices, overrides, periods, settings, splits] = await Promise.all([ // Reads everything at once:
    supabase.from("admin_profiles").select("level").eq("account_id", viewer.id).maybeSingle(), // this admin's own level,
    supabase // the families:
      .from("families") // from families,
      .select("id, name, students(full_name, parent_student_links(parent_id, parent:parent_profiles(account:accounts(full_name))))") // with their students and parents,
      .order("name"), // by name.
    supabase // the billing accounts:
      .from("billing_accounts") // from billing_accounts,
      .select("family_id, plan, method, payment_ready, bill_payer_id, terms_accepted_at, plan_chosen_at, paused, paused_since"), // with plan, payment and pause details.
    supabase.from("billing_family_rates").select("family_id, amount_cents, price:billing_price_items(name)"), // kept rates, with the price's name,
    supabase.from("billing_price_items").select("id, code, name, unit, amount_cents, gst_applies, active, session_level").order("code"), // the price list,
    supabase.from("billing_credits").select("family_id, amount_cents"), // every credit,
    supabase // the invoices:
      .from("billing_invoices") // from billing_invoices,
      .select("id, number, family_name, status, period_start, period_end, send_on, due_on, total_cents, credit_applied_cents, discount_cents, xero_invoice_id") // with these details,
      .order("created_at", { ascending: false }) // newest first,
      .limit(100), // up to 100.
    supabase.from("billing_pause_overrides").select("family_id, reason, until_on, payment_plan").is("ended_at", null), // pauses lifted without payment, still in place,
    supabase.from("billing_school_periods").select("id, name, kind, state, starts_on, ends_on").order("starts_on"), // school terms and holidays, earliest first,
    supabase.from("billing_settings").select("invoice_mode, override_by, show_tutor_on_invoice").maybeSingle(), // billing settings,
    supabase.from("billing_payers").select("family_id, account_id, share_percent, method, payment_ready"), // and split payers.
  ]); // End of the reads.
  const splitRows = (splits.data ?? []) as { family_id: string; account_id: string; share_percent: number; method: BillingMethod; payment_ready: boolean }[]; // The split payers.

  // Emergency owner access counts as owner here too.
  const isOwner = viewer.level === "owner" || me.data?.level === "owner"; // Whether they're the owner (or have emergency owner access).
  const canEditPay = PAY.includes(viewer.level); // Whether they can change staff pay.
  const canOverride = settings.data?.override_by === "admin" || isOwner; // Whether they can lift a pause (set in billing settings; the owner always can).
  const familyRows = (families.data ?? []) as unknown as Family[]; // The families.
  const accountOf = new Map(((accounts.data ?? []) as Account[]).map((a) => [a.family_id, a])); // Each family's billing account, by family.
  const balance = new Map<string, number>(); // Each family's credit total.
  for (const c of credits.data ?? []) { // For each credit:
    if (c.family_id) balance.set(c.family_id, (balance.get(c.family_id) ?? 0) + c.amount_cents); // adds it to that family's total.
  } // End of the loop.
  const ratesOf = (id: string) => // Gives one family's kept rates:
    ((rates.data ?? []) as unknown as { family_id: string; amount_cents: number; price: { name: string } | null }[]).filter( // from all kept rates,
      (r) => r.family_id === id, // just this family's.
    ); // (end of the filter)
  const overrideOf = new Map((overrides.data ?? []).map((o) => [o.family_id, o])); // Each family's lifted pause, by family.
  const sessionPrices = (prices.data ?? []).filter((p) => p.unit === "hour").map((p) => ({ id: p.id, name: p.name })); // Prices charged by the hour (for kept rates).
  const invoiceRows = (invoices.data ?? []) as Invoice[]; // The invoices.
  const paused = familyRows.filter((f) => accountOf.get(f.id)?.paused); // Families on pause.

  let xeroName: string | null = null; // The connected Xero organisation's name.
  let xeroProblem: string | null = null; // A Xero problem message (if any).
  try { // Tries to read the Xero connection:
    xeroName = xeroConfig() ? ((await xeroConnection())?.tenant_name ?? null) : null; // its name, if Xero is set up and connected.
  } catch { // If it failed:
    xeroProblem = "The Xero connection couldn't be read. Check the billing secret settings."; // notes the problem.
  } // End of the fallback.
  let stripeReady = false; // Whether Stripe is set up.
  let stripeProblem: string | null = null; // A Stripe problem message (if any).
  try { // Tries to read the Stripe key:
    stripeReady = Boolean(stripeKey()); // set up if there is one.
  } catch (e) { // If it failed:
    stripeProblem = (e as Error).message; // notes the problem.
  } // End of the fallback.
  const xeroNote = typeof params.xero === "string" ? XERO_NOTES[params.xero] : undefined; // The Xero message after coming back from Xero (if any).

  // Numbers on the menu: families on hold, invoices and staff hours to approve.
  const todo = await getToDoCounts(viewer.roles); // The to-do numbers.

  return ( // Shows:
    <>{/* (a group) */}
      <RoleTabs roles={viewer.roles} active="admin" />{/* the dashboard tabs, with Admin open, */}
      <SectionShell // the page frame:
        basePath="/admin/billing" // at this address,
        label="Billing" // labelled "Billing",
        role="admin" // in the admin colours,
        section={section} // on the open section,
        sections={SECTIONS.map((s) => ({ ...s, count: todo.get("billing", s.id) }))} // with each section's to-do number on the menu.
      >{/* (end of the frame's settings) */}
        <p className="text-sm">{/* a line of links: */}
          <TextLink href="/admin">Back to admin</TextLink>{/* back to admin, */}
          {" · "}{/* a dot between, */}
          <TextLink href="/admin/staff">Staff directory</TextLink>{/* the staff directory. */}
        </p>{/* End of the line. */}

        {section === "families" && ( // The family billing section:
          <>{/* (a group) */}
            {paused.length > 0 && ( // If any families are paused:
              <Card title="Paused families" description="Support is on hold for these families until they pay.">{/* a card: */}
                <ul className="space-y-1 text-sm">{/* a list: */}
                  {paused.map((f) => ( // for each paused family:
                    <li key={f.id}>{/* a row: */}
                      <strong>{f.name}</strong>, paused since {plainDate(accountOf.get(f.id)?.paused_since?.slice(0, 10))}{/* its name and since when. */}
                    </li> // End of the row.
                  ))}{/* End of the loop. */}
                </ul>{/* End of the list. */}
              </Card> // End of the card.
            )}{/* End of this part. */}
            {familyRows.length === 0 && <Empty>No families yet.</Empty>}{/* No families yet: says so. */}
            {familyRows.map((f) => { // For each family:
              const acct = accountOf.get(f.id); // its billing account,
              const payers = new Map<string, string>(); // its parents (who can pay), by id:
              for (const s of f.students) { // for each student,
                for (const l of s.parent_student_links) payers.set(l.parent_id, l.parent?.account?.full_name ?? "Parent"); // adds each of their parents.
              } // End of the loop.
              const override = overrideOf.get(f.id); // its lifted pause (if any).
              return ( // Shows:
                <Card // a fold-up card:
                  key={f.id} // one per family,
                  collapsible // can fold,
                  defaultOpen={false} // folded to start,
                  title={`${f.name}${acct?.paused ? " (paused)" : ""}`} // the family's name (and paused, if so),
                  description={ // a summary line:
                    acct // if they have an account:
                      ? `${acct.plan_chosen_at ? PLAN_LABELS[acct.plan] : "Plan not chosen yet"} · ${acct.payment_ready ? METHOD_LABELS[acct.method] : "No automatic payment yet"} · Credit ${dollars(balance.get(f.id))}${acct.terms_accepted_at ? "" : " · Terms not accepted yet"}` // the plan, payment method, credit, and whether terms are accepted,
                      : "No billing plan yet" // otherwise no plan yet.
                  } // (end of the summary)
                >{/* (end of the card's settings) */}
                  <p className="mb-4 text-sm text-zinc-600">Students: {f.students.map((s) => s.full_name).join(", ") || "none"}</p>{/* the students' names. */}
                  <SubHeading>Plan and bill payer</SubHeading>{/* a small heading, */}
                  <FamilyPlanForm // the plan and bill payer form:
                    familyId={f.id} // the family,
                    plan={acct?.plan ?? "weekly"} // the plan (weekly to start),
                    billPayerId={acct?.bill_payer_id ?? null} // the bill payer,
                    payers={[...payers].map(([id, name]) => ({ id, name }))} // the parents to choose from.
                  />{/* End of the form. */}
                  {acct && ( // If they have an account:
                    <>{/* (a group) */}
                      <SubHeading>Split payments</SubHeading>{/* a small heading, */}
                      {splitRows.filter((r) => r.family_id === f.id).length > 0 ? ( // if there are split payers:
                        <ul className="mb-3 space-y-2 text-sm">{/* a list: */}
                          <li>{/* the bill payer's row: */}
                            {payers.get(acct.bill_payer_id ?? "") ?? "Bill payer"} (bill payer):{" "}{/* their name, */}
                            {100 - splitRows.filter((r) => r.family_id === f.id).reduce((t, r) => t + r.share_percent, 0)}%{/* and their share (what's left after the others). */}
                          </li>{/* End of the row. */}
                          {splitRows // the split payers:
                            .filter((r) => r.family_id === f.id) // just this family's,
                            .map((r) => ( // each as:
                              <li key={r.account_id} className="flex flex-wrap items-center gap-3">{/* a row: */}
                                <span>{/* (a group) */}
                                  {payers.get(r.account_id) ?? "Payer"}: {r.share_percent}% ·{" "}{/* their name and share, */}
                                  {r.payment_ready ? METHOD_LABELS[r.method] : "no automatic payment yet"}{/* and how they pay. */}
                                </span>{/* End of the group. */}
                                <form action={removeSplit}>{/* a remove form: */}
                                  <input type="hidden" name="family_id" value={f.id} />{/* the family (hidden), */}
                                  <input type="hidden" name="payer_id" value={r.account_id} />{/* the payer (hidden), */}
                                  <Button type="submit">Remove</Button>{/* the remove button. */}
                                </form>{/* End of the form. */}
                              </li> // End of the row.
                            ))}{/* End of the loop. */}
                        </ul> // End of the list.
                      ) : ( // otherwise:
                        <p className="mb-3 text-sm text-zinc-600">The bill payer pays each invoice in full.</p> // the bill payer pays in full.
                      )}{/* End of this part. */}
                      {acct.bill_payer_id ? ( // If there's a bill payer:
                        <SplitForm // the add-a-split form:
                          familyId={f.id} // the family,
                          payers={[...payers].filter(([id]) => id !== acct.bill_payer_id).map(([id, name]) => ({ id, name }))} // the other parents to choose from.
                        /> // End of the form.
                      ) : ( // otherwise:
                        <p className="mb-3 text-sm text-zinc-600">Choose a bill payer first to split payments.</p> // says to choose a bill payer first.
                      )}{/* End of this part. */}
                      <SubHeading>Kept rate</SubHeading>{/* a small heading, */}
                      {ratesOf(f.id).length > 0 ? ( // if they have kept rates:
                        <p className="mb-3 text-sm">{/* a line: */}
                          {ratesOf(f.id) // their kept rates:
                            .map((r) => `${r.price?.name}: ${dollars(r.amount_cents)}/hr`) // each as price name and hourly amount,
                            .join(", ")}{/* joined with commas. */}
                        </p> // End of the line.
                      ) : ( // otherwise:
                        <p className="mb-3 text-sm text-zinc-600">Pays the price list.</p> // they pay the price list.
                      )}{/* End of this part. */}
                      {isOwner && <KeptRateForm familyId={f.id} prices={sessionPrices} />}{/* The kept rate form (owner only). */}
                      <SubHeading>Add credit</SubHeading>{/* a small heading, */}
                      <CreditForm familyId={f.id} />{/* the add credit form. */}
                      {acct.paused && canOverride && ( // If paused and this admin can lift it:
                        <>{/* (a group) */}
                          <SubHeading>Lift the pause without payment</SubHeading>{/* a small heading, */}
                          <OverrideForm familyId={f.id} />{/* the lift-pause form. */}
                        </> // End of the group.
                      )}{/* End of this part. */}
                      {override && ( // If a pause is lifted:
                        <p className="mt-4 rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-900">{/* a notice: */}
                          Pause lifted until {plainDate(override.until_on)}: {override.reason}{/* until when and why, */}
                          {override.payment_plan ? ` Plan: ${override.payment_plan}` : ""}{/* and the payment plan (if any). */}
                        </p> // End of the notice.
                      )}{/* End of this part. */}
                    </> // End of the group.
                  )}{/* End of the account part. */}
                </Card> // End of the card.
              ); // End of what's shown for this family.
            })}{/* End of the loop. */}
          </> // End of the group.
        )}{/* End of the family section. */}

        {section === "invoices" && ( // The invoices section:
          <>{/* (a group) */}
            <Card title="Run billing">{/* a "Run billing" card: */}
              <RunNowForm />{/* the run-now form. */}
            </Card>{/* End of the card. */}
            <Card title="Invoices" description="Newest first. Drafts go to Xero on their send date.">{/* the invoices card: */}
              {invoiceRows.length === 0 ? ( // if none:
                <Empty>No invoices yet.</Empty> // says so.
              ) : ( // otherwise:
                <Table headings={["Invoice", "Family", "Sessions", "Due", "Total", "Status", ""]}>{/* a table with these headings: */}
                  {invoiceRows.map((i) => ( // for each invoice:
                    <tr key={i.id}>{/* a row: */}
                      <td>{i.number}</td>{/* its number, */}
                      <td>{i.family_name}</td>{/* the family, */}
                      <td>{/* the sessions cell: */}
                        {plainDate(i.period_start)} to {plainDate(i.period_end)}{/* from and to dates. */}
                      </td>{/* End of the cell. */}
                      <td>{plainDate(i.due_on)}</td>{/* the due date, */}
                      <td>{/* the total cell: */}
                        {dollars(i.total_cents)}{/* the total, */}
                        {i.credit_applied_cents > 0 && <span className="block text-xs text-zinc-500">credit {dollars(i.credit_applied_cents)}</span>}{/* credit used (if any), */}
                        {i.discount_cents > 0 && <span className="block text-xs text-zinc-500">discount {dollars(i.discount_cents)}</span>}{/* discount (if any). */}
                      </td>{/* End of the cell. */}
                      <td>{STATUS_LABELS[i.status]}</td>{/* the status, */}
                      <td className="space-y-2">{/* the buttons cell: */}
                        {(i.status === "draft" || i.status === "awaiting_approval") && ( // if a draft or awaiting approval:
                          <form action={approveInvoice}>{/* the approve form: */}
                            <input type="hidden" name="id" value={i.id} />{/* the invoice (hidden), */}
                            <Button type="submit">{i.xero_invoice_id ? "Mark approved" : "Approve and send"}</Button>{/* the button (approve only if already in Xero; otherwise approve and send). */}
                          </form> // End of the form.
                        )}{/* End of this part. */}
                        {(i.status === "draft" || i.status === "awaiting_approval" || i.status === "open") && ( // if not yet paid or cancelled:
                          <details>{/* a fold-out: */}
                            <summary className="cursor-pointer text-sm text-teal-800">Cancel…</summary>{/* its heading, */}
                            <VoidInvoiceForm id={i.id} />{/* the cancel form. */}
                          </details> // End of the fold-out.
                        )}{/* End of this part. */}
                      </td>{/* End of the cell. */}
                    </tr> // End of the row.
                  ))}{/* End of the loop. */}
                </Table> // End of the table.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}
            <Card title="Build an invoice by hand" collapsible defaultOpen={false}>{/* a fold-up card: */}
              <BuildInvoiceForm families={familyRows.filter((f) => accountOf.has(f.id)).map((f) => ({ id: f.id, name: f.name }))} />{/* the build-an-invoice form, for families with an account. */}
            </Card>{/* End of the card. */}
          </> // End of the group.
        )}{/* End of the invoices section. */}

        {section === "pay" && ( // The staff pay section:
          <PaySection // the pay section:
            periodParam={typeof params.period === "string" ? params.period : null} // the pay period from the address (if any),
            isOwner={isOwner} // whether they're the owner,
            canEdit={canEditPay} // whether they can change pay,
            today={adelaideToday()} // and today's date.
          /> // (end of the pay section)
        )}{/* End of the staff pay section. */}

        {section === "prices" && ( // The prices and settings section:
          <>{/* (a group) */}
            <Card title="Prices" description="New invoices use these. Families with a kept rate pay that instead.">{/* the prices card: */}
              <div className="space-y-6">{/* a list: */}
                {(prices.data ?? []).map((p) => ( // for each price:
                  <div key={p.id}>{/* a block: */}
                    <SubHeading>{/* a small heading: */}
                      {p.name} {p.active ? "" : "(not in use)"}{/* the name (and if not in use). */}
                    </SubHeading>{/* End of the heading. */}
                    {isOwner ? ( // if they're the owner:
                      <PriceForm id={p.id} amount={(p.amount_cents / 100).toFixed(2)} gst={p.gst_applies} active={p.active} /> // the price form.
                    ) : ( // otherwise:
                      <p className="text-sm">{/* a line: */}
                        {dollars(p.amount_cents)}{/* the amount, */}
                        {p.gst_applies ? " plus GST" : ""}. Only the owner changes prices.{/* plus GST if it applies, and who can change it. */}
                      </p> // End of the line.
                    )}{/* End of this part. */}
                  </div> // End of the block.
                ))}{/* End of the loop. */}
              </div>{/* End of the list. */}
            </Card>{/* End of the card. */}
            <Card title="School terms and holidays" description="Needed for families who pay per term. Each holiday period gets its own invoice.">{/* the school terms card: */}
              {(periods.data ?? []).length === 0 ? ( // if none:
                <Empty>None entered yet.</Empty> // says so.
              ) : ( // otherwise:
                <ul className="mb-4 space-y-1 text-sm">{/* a list: */}
                  {(periods.data ?? []).map((p) => ( // for each term or holiday:
                    <li key={p.id}>{/* a row: */}
                      {p.name} ({p.kind === "term" ? "term" : "holidays"}, {p.state}): {plainDate(p.starts_on)} to {plainDate(p.ends_on)}{/* its name, kind, state and dates. */}
                    </li> // End of the row.
                  ))}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of this part. */}
              <SchoolPeriodForm />{/* the add-a-term form. */}
            </Card>{/* End of the card. */}
            {isOwner && settings.data && ( // For the owner, if settings are read:
              <Card title="Settings">{/* a settings card: */}
                <SettingsForm // the settings form:
                  invoiceMode={settings.data.invoice_mode} // how invoices are sent,
                  overrideBy={settings.data.override_by} // who can lift a pause,
                  showTutor={settings.data.show_tutor_on_invoice} // whether the tutor shows on invoices.
                />{/* End of the form. */}
              </Card> // End of the card.
            )}{/* End of this part. */}
          </> // End of the group.
        )}{/* End of the prices section. */}

        {section === "connections" && ( // The connections section:
          <>{/* (a group) */}
            <Card title="Stripe">{/* the Stripe card: */}
              {stripeProblem ? ( // if there's a problem:
                <p className="text-sm text-red-800">{stripeProblem}</p> // the problem.
              ) : stripeReady ? ( // if set up:
                <p className="text-sm">{/* a line: */}
                  Connected{stripeIsTestMode() ? " in test mode: no real money moves." : " for live payments."}{/* connected (and whether in test mode). */}
                </p> // End of the line.
              ) : ( // otherwise:
                <p className="text-sm text-zinc-600">{/* a line: */}
                  Not connected yet. Add STRIPE_SECRET_KEY (a test key, sk_test_...) and STRIPE_WEBHOOK_SECRET in
                  Vercel&apos;s settings. Until then families can&apos;t save a card or pay in the app.{/* what to add, and what's not possible until then. */}
                </p> // End of the line.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}
            <Card title="Xero">{/* the Xero card: */}
              {xeroNote && <p className="mb-3 text-sm font-medium">{xeroNote}</p>}{/* the message after coming back from Xero (if any), */}
              {xeroProblem && <p className="mb-3 text-sm text-red-800">{xeroProblem}</p>}{/* the Xero problem (if any), */}
              {!xeroConfig() ? ( // if Xero isn't set up:
                <p className="text-sm text-zinc-600">{/* a line: */}
                  Not set up yet. Add XERO_CLIENT_ID, XERO_CLIENT_SECRET, XERO_WEBHOOK_KEY, XERO_STRIPE_CLEARING_ACCOUNT
                  and BILLING_ENCRYPTION_KEY in Vercel&apos;s settings. Until then, approve invoices here and they go
                  straight to the family.{/* what to add, and what happens until then. */}
                </p> // End of the line.
              ) : xeroName ? ( // if connected:
                <p className="text-sm">Connected to {xeroName}.</p> // the organisation's name.
              ) : isOwner ? ( // if not connected and they're the owner:
                <a // a button-style link:
                  href="/api/billing/xero/connect" // to start connecting,
                  className="inline-block rounded-full bg-teal-700 px-5 py-2.5 text-sm font-medium text-white hover:bg-teal-900" // styled as a button.
                >{/* (end of the link's settings) */}
                  Connect Xero{/* its words, */}
                </a> // end of the link.
              ) : ( // otherwise:
                <p className="text-sm text-zinc-600">Not connected. The owner can connect Xero here.</p> // only the owner can connect.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}
          </> // End of the group.
        )}{/* End of the connections section. */}
      </SectionShell>{/* End of the page frame. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of AdminBillingPage.
