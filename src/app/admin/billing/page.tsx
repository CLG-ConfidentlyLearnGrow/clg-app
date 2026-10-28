import { approveInvoice } from "@/app/actions/billing";
import { RoleTabs } from "@/components/role-tabs";
import { SectionShell } from "@/components/section-shell";
import { Button, Card, Empty, SubHeading, Table, TextLink } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { stripeIsTestMode, stripeKey, xeroConfig } from "@/lib/billing/config";
import { METHOD_LABELS, PLAN_LABELS, STATUS_LABELS, dollars, plainDate, type BillingMethod, type BillingPlan } from "@/lib/billing/money";
import { adelaideToday } from "@/lib/billing/run";
import { xeroConnection } from "@/lib/billing/xero";
import { createClient } from "@/lib/supabase/server";
import {
  BuildInvoiceForm,
  CreditForm,
  FamilyPlanForm,
  KeptRateForm,
  OverrideForm,
  PriceForm,
  RunNowForm,
  SchoolPeriodForm,
  SettingsForm,
  VoidInvoiceForm,
} from "./forms";
import { PaySection } from "./pay-section";

const SECTIONS = [
  { id: "families", label: "Family billing" },
  { id: "invoices", label: "Invoices" },
  { id: "pay", label: "Tutor pay" },
  { id: "prices", label: "Prices and settings" },
  { id: "connections", label: "Stripe and Xero" },
] as const;

type Family = {
  id: string;
  name: string;
  students: {
    full_name: string;
    parent_student_links: { parent_id: string; parent: { account: { full_name: string } | null } | null }[];
  }[];
};
type Account = {
  family_id: string;
  plan: BillingPlan;
  method: BillingMethod;
  payment_ready: boolean;
  bill_payer_id: string | null;
  terms_accepted_at: string | null;
  paused: boolean;
  paused_since: string | null;
};
type Invoice = {
  id: string;
  number: string;
  family_name: string;
  status: keyof typeof STATUS_LABELS;
  period_start: string;
  period_end: string;
  send_on: string;
  due_on: string;
  total_cents: number;
  credit_applied_cents: number;
  discount_cents: number;
  xero_invoice_id: string | null;
};

// Xero connection messages after the owner comes back from Xero.
const XERO_NOTES: Record<string, string> = {
  connected: "Xero is connected.",
  failed: "Xero didn't connect. Please try again, and check the Xero app settings.",
  "owner-only": "Only the owner can connect Xero.",
};

export default async function AdminBillingPage({ searchParams }: PageProps<"/admin/billing">) {
  const viewer = await requireAdmin();
  const params = await searchParams;
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "families";
  const supabase = await createClient();

  const [me, families, accounts, rates, prices, credits, invoices, overrides, periods, settings] = await Promise.all([
    supabase.from("admin_profiles").select("level").eq("account_id", viewer.id).maybeSingle(),
    supabase
      .from("families")
      .select("id, name, students(full_name, parent_student_links(parent_id, parent:parent_profiles(account:accounts(full_name))))")
      .order("name"),
    supabase
      .from("billing_accounts")
      .select("family_id, plan, method, payment_ready, bill_payer_id, terms_accepted_at, paused, paused_since"),
    supabase.from("billing_family_rates").select("family_id, amount_cents, price:billing_price_items(name)"),
    supabase.from("billing_price_items").select("id, code, name, unit, amount_cents, gst_applies, active, session_level").order("code"),
    supabase.from("billing_credits").select("family_id, amount_cents"),
    supabase
      .from("billing_invoices")
      .select("id, number, family_name, status, period_start, period_end, send_on, due_on, total_cents, credit_applied_cents, discount_cents, xero_invoice_id")
      .order("created_at", { ascending: false })
      .limit(100),
    supabase.from("billing_pause_overrides").select("family_id, reason, until_on, payment_plan").is("ended_at", null),
    supabase.from("billing_school_periods").select("id, name, kind, state, starts_on, ends_on").order("starts_on"),
    supabase.from("billing_settings").select("invoice_mode, override_by, show_tutor_on_invoice").maybeSingle(),
  ]);

  const isOwner = me.data?.level === "owner";
  const canOverride = settings.data?.override_by === "admin" || isOwner;
  const familyRows = (families.data ?? []) as unknown as Family[];
  const accountOf = new Map(((accounts.data ?? []) as Account[]).map((a) => [a.family_id, a]));
  const balance = new Map<string, number>();
  for (const c of credits.data ?? []) {
    if (c.family_id) balance.set(c.family_id, (balance.get(c.family_id) ?? 0) + c.amount_cents);
  }
  const ratesOf = (id: string) =>
    ((rates.data ?? []) as unknown as { family_id: string; amount_cents: number; price: { name: string } | null }[]).filter(
      (r) => r.family_id === id,
    );
  const overrideOf = new Map((overrides.data ?? []).map((o) => [o.family_id, o]));
  const sessionPrices = (prices.data ?? []).filter((p) => p.unit === "hour").map((p) => ({ id: p.id, name: p.name }));
  const invoiceRows = (invoices.data ?? []) as Invoice[];
  const waiting = invoiceRows.filter((i) => i.status === "draft" || i.status === "awaiting_approval");
  const paused = familyRows.filter((f) => accountOf.get(f.id)?.paused);

  let xeroName: string | null = null;
  let xeroProblem: string | null = null;
  try {
    xeroName = xeroConfig() ? ((await xeroConnection())?.tenant_name ?? null) : null;
  } catch {
    xeroProblem = "The Xero connection couldn't be read. Check the billing secret settings.";
  }
  let stripeReady = false;
  let stripeProblem: string | null = null;
  try {
    stripeReady = Boolean(stripeKey());
  } catch (e) {
    stripeProblem = (e as Error).message;
  }
  const xeroNote = typeof params.xero === "string" ? XERO_NOTES[params.xero] : undefined;

  return (
    <>
      <RoleTabs roles={viewer.roles} active="admin" />
      <SectionShell
        basePath="/admin/billing"
        label="Billing"
        section={section}
        sections={SECTIONS.map((s) => ({
          ...s,
          count: s.id === "families" ? paused.length || undefined : s.id === "invoices" ? waiting.length || undefined : undefined,
        }))}
      >
        <p className="text-sm">
          <TextLink href="/admin">Back to admin</TextLink>
        </p>

        {section === "families" && (
          <>
            {paused.length > 0 && (
              <Card title="Paused families" description="Support is on hold for these families until they pay.">
                <ul className="space-y-1 text-sm">
                  {paused.map((f) => (
                    <li key={f.id}>
                      <strong>{f.name}</strong>, paused since {plainDate(accountOf.get(f.id)?.paused_since?.slice(0, 10))}
                    </li>
                  ))}
                </ul>
              </Card>
            )}
            {familyRows.length === 0 && <Empty>No families yet.</Empty>}
            {familyRows.map((f) => {
              const acct = accountOf.get(f.id);
              const payers = new Map<string, string>();
              for (const s of f.students) {
                for (const l of s.parent_student_links) payers.set(l.parent_id, l.parent?.account?.full_name ?? "Parent");
              }
              const override = overrideOf.get(f.id);
              return (
                <Card
                  key={f.id}
                  collapsible
                  defaultOpen={false}
                  title={`${f.name}${acct?.paused ? " (paused)" : ""}`}
                  description={
                    acct
                      ? `${PLAN_LABELS[acct.plan]} · ${acct.payment_ready ? METHOD_LABELS[acct.method] : "No automatic payment yet"} · Credit ${dollars(balance.get(f.id))}${acct.terms_accepted_at ? "" : " · Terms not accepted yet"}`
                      : "No billing plan yet"
                  }
                >
                  <p className="mb-4 text-sm text-zinc-600">Students: {f.students.map((s) => s.full_name).join(", ") || "none"}</p>
                  <SubHeading>Plan and bill payer</SubHeading>
                  <FamilyPlanForm
                    familyId={f.id}
                    plan={acct?.plan ?? "weekly"}
                    billPayerId={acct?.bill_payer_id ?? null}
                    payers={[...payers].map(([id, name]) => ({ id, name }))}
                  />
                  {acct && (
                    <>
                      <SubHeading>Kept rate</SubHeading>
                      {ratesOf(f.id).length > 0 ? (
                        <p className="mb-3 text-sm">
                          {ratesOf(f.id)
                            .map((r) => `${r.price?.name}: ${dollars(r.amount_cents)}/hr`)
                            .join(", ")}
                        </p>
                      ) : (
                        <p className="mb-3 text-sm text-zinc-600">Pays the price list.</p>
                      )}
                      <KeptRateForm familyId={f.id} prices={sessionPrices} />
                      <SubHeading>Add credit</SubHeading>
                      <CreditForm familyId={f.id} />
                      {acct.paused && canOverride && (
                        <>
                          <SubHeading>Lift the pause without payment</SubHeading>
                          <OverrideForm familyId={f.id} />
                        </>
                      )}
                      {override && (
                        <p className="mt-4 rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-900">
                          Pause lifted until {plainDate(override.until_on)}: {override.reason}
                          {override.payment_plan ? ` Plan: ${override.payment_plan}` : ""}
                        </p>
                      )}
                    </>
                  )}
                </Card>
              );
            })}
          </>
        )}

        {section === "invoices" && (
          <>
            <Card title="Run billing">
              <RunNowForm />
            </Card>
            <Card title="Invoices" description="Newest first. Drafts go to Xero on their send date.">
              {invoiceRows.length === 0 ? (
                <Empty>No invoices yet.</Empty>
              ) : (
                <Table headings={["Invoice", "Family", "Sessions", "Due", "Total", "Status", ""]}>
                  {invoiceRows.map((i) => (
                    <tr key={i.id}>
                      <td>{i.number}</td>
                      <td>{i.family_name}</td>
                      <td>
                        {plainDate(i.period_start)} to {plainDate(i.period_end)}
                      </td>
                      <td>{plainDate(i.due_on)}</td>
                      <td>
                        {dollars(i.total_cents)}
                        {i.credit_applied_cents > 0 && <span className="block text-xs text-zinc-500">credit {dollars(i.credit_applied_cents)}</span>}
                        {i.discount_cents > 0 && <span className="block text-xs text-zinc-500">discount {dollars(i.discount_cents)}</span>}
                      </td>
                      <td>{STATUS_LABELS[i.status]}</td>
                      <td className="space-y-2">
                        {(i.status === "draft" || i.status === "awaiting_approval") && (
                          <form action={approveInvoice}>
                            <input type="hidden" name="id" value={i.id} />
                            <Button type="submit">{i.xero_invoice_id ? "Mark approved" : "Approve and send"}</Button>
                          </form>
                        )}
                        {(i.status === "draft" || i.status === "awaiting_approval" || i.status === "open") && (
                          <details>
                            <summary className="cursor-pointer text-sm text-teal-800">Cancel…</summary>
                            <VoidInvoiceForm id={i.id} />
                          </details>
                        )}
                      </td>
                    </tr>
                  ))}
                </Table>
              )}
            </Card>
            <Card title="Build an invoice by hand" collapsible defaultOpen={false}>
              <BuildInvoiceForm families={familyRows.filter((f) => accountOf.has(f.id)).map((f) => ({ id: f.id, name: f.name }))} />
            </Card>
          </>
        )}

        {section === "pay" && (
          <PaySection
            periodParam={typeof params.period === "string" ? params.period : null}
            isOwner={isOwner}
            today={adelaideToday()}
          />
        )}

        {section === "prices" && (
          <>
            <Card title="Prices" description="New invoices use these. Families with a kept rate pay that instead.">
              <div className="space-y-6">
                {(prices.data ?? []).map((p) => (
                  <div key={p.id}>
                    <SubHeading>
                      {p.name} {p.active ? "" : "(not in use)"}
                    </SubHeading>
                    <PriceForm id={p.id} amount={(p.amount_cents / 100).toFixed(2)} gst={p.gst_applies} active={p.active} />
                  </div>
                ))}
              </div>
            </Card>
            <Card title="School terms and holidays" description="Needed for families who pay per term. Each holiday period gets its own invoice.">
              {(periods.data ?? []).length === 0 ? (
                <Empty>None entered yet.</Empty>
              ) : (
                <ul className="mb-4 space-y-1 text-sm">
                  {(periods.data ?? []).map((p) => (
                    <li key={p.id}>
                      {p.name} ({p.kind === "term" ? "term" : "holidays"}, {p.state}): {plainDate(p.starts_on)} to {plainDate(p.ends_on)}
                    </li>
                  ))}
                </ul>
              )}
              <SchoolPeriodForm />
            </Card>
            {isOwner && settings.data && (
              <Card title="Settings">
                <SettingsForm
                  invoiceMode={settings.data.invoice_mode}
                  overrideBy={settings.data.override_by}
                  showTutor={settings.data.show_tutor_on_invoice}
                />
              </Card>
            )}
          </>
        )}

        {section === "connections" && (
          <>
            <Card title="Stripe">
              {stripeProblem ? (
                <p className="text-sm text-red-800">{stripeProblem}</p>
              ) : stripeReady ? (
                <p className="text-sm">
                  Connected{stripeIsTestMode() ? " in test mode: no real money moves." : " for live payments."}
                </p>
              ) : (
                <p className="text-sm text-zinc-600">
                  Not connected yet. Add STRIPE_SECRET_KEY (a test key, sk_test_...) and STRIPE_WEBHOOK_SECRET in
                  Vercel&apos;s settings. Until then families can&apos;t save a card or pay in the app.
                </p>
              )}
            </Card>
            <Card title="Xero">
              {xeroNote && <p className="mb-3 text-sm font-medium">{xeroNote}</p>}
              {xeroProblem && <p className="mb-3 text-sm text-red-800">{xeroProblem}</p>}
              {!xeroConfig() ? (
                <p className="text-sm text-zinc-600">
                  Not set up yet. Add XERO_CLIENT_ID, XERO_CLIENT_SECRET, XERO_WEBHOOK_KEY, XERO_STRIPE_CLEARING_ACCOUNT
                  and BILLING_ENCRYPTION_KEY in Vercel&apos;s settings. Until then, approve invoices here and they go
                  straight to the family.
                </p>
              ) : xeroName ? (
                <p className="text-sm">Connected to {xeroName}.</p>
              ) : isOwner ? (
                <a
                  href="/api/billing/xero/connect"
                  className="inline-block rounded-full bg-teal-700 px-5 py-2.5 text-sm font-medium text-white hover:bg-teal-900"
                >
                  Connect Xero
                </a>
              ) : (
                <p className="text-sm text-zinc-600">Not connected. The owner can connect Xero here.</p>
              )}
            </Card>
          </>
        )}
      </SectionShell>
    </>
  );
}
