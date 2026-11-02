import { endAddOn } from "@/app/actions/add-ons";
import { Card, Empty, SubHeading, Table } from "@/components/ui";
import { dollars } from "@/lib/billing/money";
import { shortDate } from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";
import { GiveAddOnForm, SetAddOnForm, type AddOn } from "./add-on-forms";

type Member = {
  add_on: string;
  student_id: string;
  starts_on: string;
  ends_on: string | null;
  note: string | null;
  student: { full_name: string } | null;
};

const MODE_NAMES = { free: "Free for everyone", paid: "Paid", off: "Off" } as const;

// Add-ons such as study plans: extras on top of tutoring. Free while they
// are being tested; later the owner switches them to paid and admins give
// them to the students who pay.
export async function AddOnsSection({ isOwner }: { isOwner: boolean }) {
  const supabase = await createClient();
  const [addOnsRes, membersRes, studentsRes] = await Promise.all([
    supabase
      .from("add_ons")
      .select("code, name, description, mode, price_cents, price_period, gst_applies")
      .order("name"),
    supabase
      .from("add_on_members")
      .select("add_on, student_id, starts_on, ends_on, note, student:students(full_name)")
      .order("starts_on"),
    supabase.from("students").select("id, full_name").order("full_name"),
  ]);
  const addOns = (addOnsRes.data ?? []) as AddOn[];
  const members = (membersRes.data ?? []) as unknown as Member[];
  const students = (studentsRes.data ?? []) as { id: string; full_name: string }[];

  return (
    <>
      {addOns.map((a) => {
        const list = members.filter((m) => m.add_on === a.code);
        return (
          <Card
            key={a.code}
            title={`Add-on: ${a.name}`}
            description={a.description ?? undefined}
          >
            <p className="text-sm">
              Now: <strong>{MODE_NAMES[a.mode]}</strong>
              {a.price_cents ? ` · ${dollars(a.price_cents)} a ${a.price_period}${a.gst_applies ? " incl. GST" : ""}` : ""}
            </p>
            <p className="mt-2 text-xs text-zinc-500">
              Paid does not charge anyone by itself yet. Adding it to invoices is a later billing step; until then,
              give it below to each student who pays. Without it, the tutor&apos;s steps and each session&apos;s next
              step still show on the roadmap.
            </p>

            {isOwner ? (
              <div className="mt-4">
                <SetAddOnForm addOn={a} />
              </div>
            ) : (
              <p className="mt-4 text-sm text-zinc-600">Only the owner can change this.</p>
            )}

            {(a.mode === "paid" || list.length > 0) && (
              <>
                <SubHeading>Students who have it</SubHeading>
                {list.length === 0 ? (
                  <Empty>No one yet.</Empty>
                ) : (
                  <Table headings={["Student", "From", "Until", "Note", ""]}>
                    {list.map((m) => (
                      <tr key={m.student_id}>
                        <td>{m.student?.full_name ?? "Unknown"}</td>
                        <td>{shortDate(m.starts_on)}</td>
                        <td>{m.ends_on ? shortDate(m.ends_on) : "Ongoing"}</td>
                        <td className="text-zinc-600">{m.note ?? ""}</td>
                        <td>
                          <form action={endAddOn}>
                            <input type="hidden" name="add_on" value={a.code} />
                            <input type="hidden" name="student_id" value={m.student_id} />
                            <button className="text-xs text-zinc-500 underline">Remove</button>
                          </form>
                        </td>
                      </tr>
                    ))}
                  </Table>
                )}
                <details className="mt-4">
                  <summary className="cursor-pointer text-sm font-medium text-teal-800 underline">
                    Give it to a student, or change their dates
                  </summary>
                  <div className="mt-3">
                    <GiveAddOnForm code={a.code} students={students} />
                  </div>
                </details>
              </>
            )}
          </Card>
        );
      })}
    </>
  );
}
