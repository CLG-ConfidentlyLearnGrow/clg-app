import { redirect } from "next/navigation";
import { Card, Empty, Page, Table } from "@/components/ui";
import { needsTwoStep, requireViewer } from "@/lib/auth";
import { dollars, plainDate } from "@/lib/billing/money";
import { adelaideToday } from "@/lib/billing/run";
import { createClient } from "@/lib/supabase/server";

const KIND_LABELS: Record<string, string> = {
  session: "Session",
  late_cancel: "Late cancel",
  min_topup: "2 hr minimum top-up",
  admin: "Admin hours",
};

const hours = (m: number) => `${Math.round((m / 60) * 100) / 100} hr`;

// A tutor's or staff member's own pay: rates and the last 8 weeks of pay
// lines, as worked out from their sign on and sign off times.
export default async function MyPayPage() {
  const viewer = await requireViewer();
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard");
  if (needsTwoStep(viewer)) redirect("/mfa");
  const supabase = await createClient();
  const today = adelaideToday();
  const since = new Date(Date.parse(`${today}T00:00:00Z`) - 56 * 86400000).toISOString().slice(0, 10);
  const [pay, lines, settings] = await Promise.all([
    supabase.from("billing_staff_pay").select("employment, school_rate_cents, tertiary_rate_cents, admin_rate_cents").eq("account_id", viewer.id).maybeSingle(),
    supabase
      .from("billing_pay_lines")
      .select("id, work_date, kind, work_kind, minutes, rate_cents, amount_cents, note, status")
      .eq("account_id", viewer.id)
      .gte("work_date", since)
      .order("work_date", { ascending: false }),
    supabase.rpc("billing_casual_min_on"),
  ]);
  const rows = lines.data ?? [];
  const p = pay.data;

  return (
    <Page title="My pay" intro="Your pay from sessions and admin hours. CLG checks it in Xero before each pay run.">
      <Card title="Your rates">
        {p ? (
          <ul className="space-y-1 text-sm">
            <li>Employment: {p.employment.replace("_", "-")}</li>
            {p.school_rate_cents != null && <li>School tutoring: {dollars(p.school_rate_cents)}/hr</li>}
            {p.tertiary_rate_cents != null && <li>Tertiary and other tutoring: {dollars(p.tertiary_rate_cents)}/hr</li>}
            {p.admin_rate_cents != null && <li>Admin: {dollars(p.admin_rate_cents)}/hr</li>}
            {p.employment === "casual" && settings.data === true && <li>As a casual, you&apos;re paid at least 2 hr for each day you work.</li>}
          </ul>
        ) : (
          <Empty>CLG hasn&apos;t entered your pay rates yet.</Empty>
        )}
      </Card>
      <Card title="Last 8 weeks" description="If a time looks wrong, record the right end time on the session, or contact CLG.">
        {rows.length === 0 ? (
          <Empty>No pay yet.</Empty>
        ) : (
          <Table headings={["Day", "What", "Hours", "Pay", ""]}>
            {rows.map((l) => (
              <tr key={l.id}>
                <td>{plainDate(l.work_date)}</td>
                <td>
                  {KIND_LABELS[l.kind] ?? l.kind}
                  {l.note ? `: ${l.note}` : ""}
                </td>
                <td>{hours(l.minutes)}</td>
                <td>{dollars(l.amount_cents)}</td>
                <td>{l.status === "sent" ? "Sent to payroll" : "Waiting"}</td>
              </tr>
            ))}
          </Table>
        )}
      </Card>
    </Page>
  );
}
