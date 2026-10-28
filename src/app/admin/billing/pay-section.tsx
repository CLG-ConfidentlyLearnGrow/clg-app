import { removePayLine } from "@/app/actions/pay";
import { Button, Card, Empty, SubHeading, Table, TextLink } from "@/components/ui";
import { xeroConfig } from "@/lib/billing/config";
import { dollars, plainDate } from "@/lib/billing/money";
import { listXeroEarningsRates, listXeroEmployees } from "@/lib/billing/payroll";
import { xeroConnection } from "@/lib/billing/xero";
import { createClient } from "@/lib/supabase/server";
import { AdminTimeForm, PayPeriodForm, SendTimesheetsForm, StaffPayForm, WorkOutPayForm, type StaffPay } from "./pay-forms";

type Line = {
  id: string;
  account_id: string | null;
  staff_name: string;
  work_date: string;
  kind: "session" | "late_cancel" | "min_topup" | "admin";
  work_kind: string;
  minutes: number;
  rate_cents: number;
  amount_cents: number;
  under_award: boolean;
  note: string | null;
  status: "pending" | "sent";
};

const KIND_LABELS: Record<Line["kind"], string> = {
  session: "Session",
  late_cancel: "Late cancel",
  min_topup: "2 hr minimum top-up",
  admin: "Admin hours",
};

function addDays(day: string, n: number) {
  return new Date(Date.parse(`${day}T00:00:00Z`) + n * 86400000).toISOString().slice(0, 10);
}

const hours = (m: number) => `${Math.round((m / 60) * 100) / 100} hr`;

// Tutor and staff pay: rates, each pay period's lines, and sending them to
// Xero Payroll.
export async function PaySection({ periodParam, isOwner, today }: { periodParam: string | null; isOwner: boolean; today: string }) {
  const supabase = await createClient();
  const pick = periodParam && /^\d{4}-\d{2}-\d{2}$/.test(periodParam) ? periodParam : addDays(today, -1);
  const { data: period } = await supabase
    .rpc("billing_pay_period", { p_day: pick })
    .single<{ period_start: string; period_end: string }>();
  const start = period?.period_start ?? pick;
  const end = period?.period_end ?? pick;
  const length = Math.round((Date.parse(end) - Date.parse(start)) / 86400000) + 1;

  const [roles, pay, lines, problems, settings, emails] = await Promise.all([
    supabase.from("account_roles").select("account_id, role, account:accounts(full_name)").in("role", ["tutor", "admin"]),
    supabase.from("billing_staff_pay").select("*"),
    supabase.from("billing_pay_lines").select("*").gte("work_date", start).lte("work_date", end).order("work_date"),
    supabase.from("billing_pay_problems").select("*").gte("work_date", start).lte("work_date", end),
    supabase.from("billing_settings").select("pay_period_days, pay_period_anchor, casual_min_enabled").maybeSingle(),
    supabase.from("account_private").select("account_id, email"),
  ]);

  const staff = new Map<string, string>();
  for (const r of (roles.data ?? []) as unknown as { account_id: string; account: { full_name: string } | null }[]) {
    staff.set(r.account_id, r.account?.full_name ?? "Staff");
  }
  const staffList = [...staff].map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name));
  const payOf = new Map(((pay.data ?? []) as StaffPay[]).map((p) => [p.account_id, p]));
  const lineRows = (lines.data ?? []) as Line[];
  const byPerson = new Map<string, Line[]>();
  for (const l of lineRows) byPerson.set(l.staff_name, [...(byPerson.get(l.staff_name) ?? []), l]);
  const emailOf = new Map((emails.data ?? []).map((e) => [e.account_id, e.email.toLowerCase()]));

  // Xero Payroll lists, when Xero is connected, so admins pick from them.
  let xeroEmployees: { id: string; name: string; email: string }[] | null = null;
  let xeroRates: { id: string; name: string }[] | null = null;
  let xeroNote: string | null = null;
  if (xeroConfig() && (await xeroConnection().catch(() => null))) {
    try {
      const [emps, rates] = await Promise.all([listXeroEmployees(), listXeroEarningsRates()]);
      xeroEmployees = emps.map((e) => ({ id: e.EmployeeID, name: `${e.FirstName} ${e.LastName}`, email: (e.Email ?? "").toLowerCase() }));
      xeroRates = rates.map((r) => ({ id: r.EarningsRateID, name: r.Name }));
    } catch (e) {
      xeroNote = `Couldn't read Xero Payroll: ${(e as Error).message} You may need to connect Xero again to allow payroll.`;
    }
  }

  const pending = lineRows.filter((l) => l.status === "pending");
  const underAward = lineRows.filter((l) => l.under_award);

  return (
    <>
      <Card title={`Pay period ${plainDate(start)} to ${plainDate(end)}`}>
        <p className="mb-4 flex gap-4 text-sm">
          <TextLink href={`/admin/billing?section=pay&period=${addDays(start, -length)}`}>« Earlier</TextLink>
          <TextLink href={`/admin/billing?section=pay&period=${addDays(start, length)}`}>Later »</TextLink>
        </p>
        {settings.data && !settings.data.casual_min_enabled && (
          <p className="mb-4 rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-900">
            The 2 hr minimum top-up for casual staff is switched off for now, so short days are paid only for the time
            worked. The awards require at least 2 hr pay for each day a casual attends work, so check this with your
            employment adviser. {isOwner ? "You can turn it back on under Pay period below." : ""}
          </p>
        )}
        {underAward.length > 0 && (
          <p className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
            {underAward.length} line(s) pay under the award minimum for that person&apos;s employment type. Check their
            rate before sending.
          </p>
        )}
        {(problems.data ?? []).length > 0 && (
          <div className="mb-4 rounded-xl bg-amber-50 px-4 py-3 text-sm text-amber-900">
            <p className="font-medium">Waiting on a pay rate:</p>
            <ul className="list-disc pl-5">
              {(problems.data ?? []).map((p) => (
                <li key={p.session_id}>
                  {p.full_name}, {plainDate(p.work_date)}: {p.problem}
                </li>
              ))}
            </ul>
          </div>
        )}
        {byPerson.size === 0 ? (
          <Empty>No pay in this period yet.</Empty>
        ) : (
          <div className="space-y-6">
            {[...byPerson].map(([name, own]) => (
              <div key={name}>
                <SubHeading>
                  {name}: {hours(own.reduce((t, l) => t + l.minutes, 0))}, {dollars(own.reduce((t, l) => t + l.amount_cents, 0))}
                </SubHeading>
                <Table headings={["Day", "What", "Hours", "Rate", "Pay", ""]}>
                  {own.map((l) => (
                    <tr key={l.id} className={l.under_award ? "bg-red-50" : undefined}>
                      <td>{plainDate(l.work_date)}</td>
                      <td>
                        {KIND_LABELS[l.kind]} ({l.work_kind}){l.note ? `: ${l.note}` : ""}
                      </td>
                      <td>{hours(l.minutes)}</td>
                      <td>{dollars(l.rate_cents)}/hr</td>
                      <td>{dollars(l.amount_cents)}</td>
                      <td>
                        {l.status === "sent" ? (
                          "In Xero"
                        ) : l.kind === "admin" ? (
                          <form action={removePayLine}>
                            <input type="hidden" name="id" value={l.id} />
                            <Button type="submit">Remove</Button>
                          </form>
                        ) : (
                          "Waiting"
                        )}
                      </td>
                    </tr>
                  ))}
                </Table>
              </div>
            ))}
          </div>
        )}
        <div className="mt-6 grid gap-6 sm:grid-cols-2">
          <WorkOutPayForm from={start} to={end} />
          {pending.length > 0 && <SendTimesheetsForm periodStart={start} />}
        </div>
      </Card>

      <Card title="Record admin hours" collapsible defaultOpen={false}>
        <AdminTimeForm staff={staffList.filter((s) => payOf.get(s.id)?.admin_rate_cents != null)} />
      </Card>

      <Card title="Pay rates" description="Up to three hourly rates per person. Leave a rate empty if it doesn't apply.">
        {xeroNote && <p className="mb-4 text-sm text-red-800">{xeroNote}</p>}
        {staffList.length === 0 ? (
          <Empty>No tutors or admins yet.</Empty>
        ) : (
          <div className="space-y-6">
            {staffList.map((s) => {
              const p = payOf.get(s.id) ?? null;
              const email = emailOf.get(s.id);
              const suggested = xeroEmployees?.find((e) => e.email && e.email === email)?.id ?? null;
              return (
                <details key={s.id} className="rounded-xl border border-zinc-200 p-4">
                  <summary className="cursor-pointer text-sm font-medium">
                    {s.name}
                    {p
                      ? ` · ${p.employment.replace("_", "-")} · school ${p.school_rate_cents != null ? dollars(p.school_rate_cents) : "–"}, tertiary ${p.tertiary_rate_cents != null ? dollars(p.tertiary_rate_cents) : "–"}, admin ${p.admin_rate_cents != null ? dollars(p.admin_rate_cents) : "–"}`
                      : " · no pay details yet"}
                  </summary>
                  <div className="mt-4">
                    <StaffPayForm
                      accountId={s.id}
                      pay={p}
                      xeroEmployees={xeroEmployees?.map(({ id, name }) => ({ id, name })) ?? null}
                      xeroRates={xeroRates}
                      suggestedEmployee={suggested}
                    />
                  </div>
                </details>
              );
            })}
          </div>
        )}
      </Card>

      {isOwner && settings.data && (
        <Card title="Pay period and casual minimum" collapsible defaultOpen={false}>
          <PayPeriodForm
            days={settings.data.pay_period_days}
            anchor={settings.data.pay_period_anchor}
            casualMin={settings.data.casual_min_enabled}
          />
        </Card>
      )}
    </>
  );
}
