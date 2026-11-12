// Summary: the admin add-ons section: each add-on's settings and the students who have it.
//
import { endAddOn } from "@/app/actions/add-ons"; // The server action that takes an add-on away from a student.
import { Card, Empty, SubHeading, Table } from "@/components/ui"; // The card, "nothing yet" note, small heading and table.
import { dollars } from "@/lib/billing/money"; // Money written as dollars.
import { shortDate } from "@/lib/scheduling"; // Dates in short form.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { GiveAddOnForm, SetAddOnForm, type AddOn } from "./add-on-forms"; // The add-on forms, and the add-on type.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while sending.

// A student who has an add-on, as the database gives it.
type Member = {
  add_on: string; // which add-on,
  student_id: string; // which student,
  starts_on: string; // from when,
  ends_on: string | null; // until when (if set),
  note: string | null; // a note (if any),
  student: { full_name: string } | null; // and the student's name.
}; // End of the shape.

const MODE_NAMES = { free: "Free for everyone", paid: "Paid", off: "Off" } as const; // Each mode's words.

// Add-ons such as study plans: extras on top of tutoring. Free while they
// are being tested; later the owner switches them to paid and admins give
// them to the students who pay.
export async function AddOnsSection({ isOwner }: { isOwner: boolean }) {
  const supabase = await createClient(); // Connects to the database.
  const [addOnsRes, membersRes, studentsRes] = await Promise.all([ // Reads three things at once:
    supabase // the add-ons:
      .from("add_ons") // (from the add-ons table)
      .select("code, name, description, mode, price_cents, price_period, gst_applies") // with their settings,
      .order("name"), // by name;
    supabase // the students who have them:
      .from("add_on_members") // (from the add-on members table)
      .select("add_on, student_id, starts_on, ends_on, note, student:students(full_name)") // with their dates, note and name,
      .order("starts_on"), // by start date;
    supabase.from("students").select("id, full_name").order("full_name"), // and every student, by name.
  ]); // End of the reads.
  const addOns = (addOnsRes.data ?? []) as AddOn[]; // The add-ons.
  const members = (membersRes.data ?? []) as unknown as Member[]; // The students who have them.
  const students = (studentsRes.data ?? []) as { id: string; full_name: string }[]; // Every student.

  return ( // Shows:
    <>{/* (a group:) */}
      {addOns.map((a) => { // for each add-on:
        const list = members.filter((m) => m.add_on === a.code); // the students who have this one.
        return ( // Shows:
          <Card // a card:
            key={a.code} // (its key)
            title={`Add-on: ${a.name}`} // titled with the add-on's name,
            description={a.description ?? undefined} // with its description (if any).
          >{/* (end of the card's settings) */}
            <p className="text-sm">{/* A line: */}
              Now: <strong>{MODE_NAMES[a.mode]}</strong>{/* its mode in bold, */}
              {a.price_cents ? ` · ${dollars(a.price_cents)} a ${a.price_period}${a.gst_applies ? " incl. GST" : ""}` : ""}{/* and its price, if set. */}
            </p>{/* End of the line. */}
            <p className="mt-2 text-xs text-zinc-500">{/* A small grey note: */}
              Paid does not charge anyone by itself yet. Adding it to invoices is a later billing step; until then,
              give it below to each student who pays. Without it, the tutor&apos;s steps and each session&apos;s next
              step still show on the roadmap.{/* that paid doesn't charge anyone yet. */}
            </p>{/* End of the note. */}

            {isOwner ? ( // For the owner:
              <div className="mt-4">{/* a block: */}
                <SetAddOnForm addOn={a} />{/* the settings form. */}
              </div> // End of the block.
            ) : ( // For other admins:
              <p className="mt-4 text-sm text-zinc-600">Only the owner can change this.</p> // a note that only the owner can change it.
            )}{/* End of the choice. */}

            {(a.mode === "paid" || list.length > 0) && ( // If it's paid, or anyone has it:
              <>{/* (a group:) */}
                <SubHeading>Students who have it</SubHeading>{/* a small heading, */}
                {list.length === 0 ? ( // if nobody has it:
                  <Empty>No one yet.</Empty> // says so.
                ) : ( // Otherwise:
                  <Table headings={["Student", "From", "Until", "Note", ""]}>{/* a table with these headings: */}
                    {list.map((m) => ( // for each student:
                      <tr key={m.student_id}>{/* a row: */}
                        <td>{m.student?.full_name ?? "Unknown"}</td>{/* their name, */}
                        <td>{shortDate(m.starts_on)}</td>{/* from when, */}
                        <td>{m.ends_on ? shortDate(m.ends_on) : "Ongoing"}</td>{/* until when (or "Ongoing"), */}
                        <td className="text-zinc-600">{m.note ?? ""}</td>{/* the note, */}
                        <td>{/* a cell: */}
                          <form action={endAddOn}>{/* a form that removes it: */}
                            <input type="hidden" name="add_on" value={a.code} />{/* which add-on (hidden), */}
                            <input type="hidden" name="student_id" value={m.student_id} />{/* which student (hidden), */}
                            <BusyButton className="text-xs text-zinc-500 underline">Remove</BusyButton>{/* and a "Remove" button. */}
                          </form>{/* End of the form. */}
                        </td>{/* End of the cell. */}
                      </tr> // End of the row.
                    ))}{/* End of the students loop. */}
                  </Table> // End of the table.
                )}{/* End of the choice. */}
                <details className="mt-4">{/* A section that opens when clicked: */}
                  <summary className="cursor-pointer text-sm font-medium text-teal-800 underline">{/* its clickable heading: */}
                    Give it to a student, or change their dates{/* "Give it to a student". */}
                  </summary>{/* End of the heading. */}
                  <div className="mt-3">{/* A block: */}
                    <GiveAddOnForm code={a.code} students={students} />{/* the form to give it. */}
                  </div>{/* End of the block. */}
                </details>{/* End of the section. */}
              </> // (end of the group)
            )}{/* End of the students part. */}
          </Card> // End of the card.
        ); // End of what's shown for this add-on.
      })}{/* End of the add-ons loop. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of AddOnsSection.
