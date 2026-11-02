import { Card, Empty, Table } from "@/components/ui";
import { localToday, shortDate } from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";
import { LeavingForm } from "./leaving-form";
import { LEAVING_REASONS } from "./leaving-reasons";

type Row = {
  id: string;
  who: string;
  name: string;
  left_on: string;
  reason: string;
  details: string | null;
  left_happy: boolean | null;
  review_asked: boolean;
};

// Why families and tutors leave, so CLG can see patterns over time.
export async function LeavingSection() {
  const supabase = await createClient();
  const [rowsRes, familiesRes, tutorsRes] = await Promise.all([
    supabase.rpc("list_leaving_records"),
    supabase.from("families").select("id, name").order("name"),
    supabase.from("tutor_profiles").select("account_id, account:accounts(full_name)"),
  ]);
  const rows = (rowsRes.data ?? []) as Row[];
  const people = [
    ...((familiesRes.data ?? []) as { id: string; name: string }[]).map((f) => ({ value: `family:${f.id}`, label: `Family: ${f.name}` })),
    ...((tutorsRes.data ?? []) as unknown as { account_id: string; account: { full_name: string } | null }[]).map((t) => ({
      value: `tutor:${t.account_id}`,
      label: `Tutor: ${t.account?.full_name ?? "Tutor"}`,
    })),
  ];
  return (
    <>
      <Card
        title="Why people left"
        description="Record why each family or tutor leaves CLG. For families who leave happy, ask for a testimonial or Google review."
      >
        {rows.length === 0 ? (
          <Empty>Nothing recorded yet.</Empty>
        ) : (
          <Table headings={["Left", "Who", "Reason", "Happy?", "Review asked"]}>
            {rows.map((r) => (
              <tr key={r.id}>
                <td>{shortDate(r.left_on)}</td>
                <td>
                  {r.who === "tutor" ? "Tutor" : "Family"}: {r.name}
                </td>
                <td>
                  {LEAVING_REASONS[r.reason] ?? r.reason}
                  {r.details && <span className="block text-zinc-600">{r.details}</span>}
                </td>
                <td>{r.left_happy === null ? "Not sure" : r.left_happy ? "Yes" : "No"}</td>
                <td>{r.review_asked ? "Yes" : "No"}</td>
              </tr>
            ))}
          </Table>
        )}
      </Card>
      <Card collapsible defaultOpen={false} title="Record someone leaving">
        <LeavingForm people={people} today={localToday()} />
      </Card>
    </>
  );
}
