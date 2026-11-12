// Summary: the admin "Leaving" section: a table of why people left, and the form to record it.
//
import { Card, Empty, Table } from "@/components/ui"; // The card, "nothing yet" note and table.
import { localToday, shortDate } from "@/lib/scheduling"; // Today's date, and dates in short form.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { LeavingForm } from "./leaving-form"; // The form to record someone leaving.
import { LEAVING_REASONS } from "./leaving-reasons"; // The list of reasons.

// One leaving record as the database gives it.
type Row = {
  id: string; // its id,
  who: string; // tutor or family,
  name: string; // their name,
  left_on: string; // the day they left,
  reason: string; // the reason's code,
  details: string | null; // any details,
  left_happy: boolean | null; // whether they left happy (or not sure),
  review_asked: boolean; // and whether a review was asked for.
}; // End of the shape.

// Why families and tutors leave, so CLG can see patterns over time.
export async function LeavingSection() {
  const supabase = await createClient(); // Connects to the database.
  const [rowsRes, familiesRes, tutorsRes] = await Promise.all([ // Reads three things at once:
    supabase.rpc("list_leaving_records"), // the leaving records,
    supabase.from("families").select("id, name").order("name"), // the families, by name,
    supabase.from("tutor_profiles").select("account_id, account:accounts(full_name)"), // and the tutors with their names.
  ]); // End of the reads.
  const rows = (rowsRes.data ?? []) as Row[]; // The leaving records.
  const people = [ // The people to choose from in the form:
    ...((familiesRes.data ?? []) as { id: string; name: string }[]).map((f) => ({ value: `family:${f.id}`, label: `Family: ${f.name}` })), // each family,
    ...((tutorsRes.data ?? []) as unknown as { account_id: string; account: { full_name: string } | null }[]).map((t) => ({ // each tutor:
      value: `tutor:${t.account_id}`, // (their code)
      label: `Tutor: ${t.account?.full_name ?? "Tutor"}`, // and their name.
    })), // (end of each tutor)
  ]; // End of the people.
  return ( // Shows:
    <>{/* (a group:) */}
      <Card // a card:
        title="Why people left" // titled "Why people left",
        description="Record why each family or tutor leaves CLG. For families who leave happy, ask for a testimonial or Google review." // with a short explanation.
      >{/* (end of the card's settings) */}
        {rows.length === 0 ? ( // If nothing is recorded:
          <Empty>Nothing recorded yet.</Empty> // says so.
        ) : ( // Otherwise:
          <Table headings={["Left", "Who", "Reason", "Happy?", "Review asked"]}>{/* a table with these headings: */}
            {rows.map((r) => ( // for each record:
              <tr key={r.id}>{/* a row: */}
                <td>{shortDate(r.left_on)}</td>{/* the day they left, */}
                <td>{/* a cell: */}
                  {r.who === "tutor" ? "Tutor" : "Family"}: {r.name}{/* tutor or family, and their name. */}
                </td>{/* End of the cell. */}
                <td>{/* A cell: */}
                  {LEAVING_REASONS[r.reason] ?? r.reason}{/* the reason's words, */}
                  {r.details && <span className="block text-zinc-600">{r.details}</span>}{/* and the details below, if any. */}
                </td>{/* End of the cell. */}
                <td>{r.left_happy === null ? "Not sure" : r.left_happy ? "Yes" : "No"}</td>{/* Happy: not sure, yes or no. */}
                <td>{r.review_asked ? "Yes" : "No"}</td>{/* Review asked: yes or no. */}
              </tr> // End of the row.
            ))}{/* End of the records loop. */}
          </Table> // End of the table.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}
      <Card collapsible defaultOpen={false} title="Record someone leaving">{/* A closed card for recording someone leaving: */}
        <LeavingForm people={people} today={localToday()} />{/* the form, with today's date. */}
      </Card>{/* End of the card. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of LeavingSection.
