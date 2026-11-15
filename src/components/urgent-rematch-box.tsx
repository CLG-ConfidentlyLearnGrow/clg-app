// Summary: the red "Urgent: needs a new tutor" box at the top of the
// Matching page (Carla, 15 Nov 2026). It lists children whose match with a
// tutor was ended while they still had sessions booked, many already paid
// for, so they need a new tutor first. It never says why the match ended:
// that stays with the people handling the concern. An admin marks each one
// sorted once the sessions are moved, with a short note.
//
import Link from "next/link"; // The Next.js link, for moving between pages without a full reload.
import { markRematchSorted } from "@/app/actions/child-safety"; // The server action that marks a flag sorted.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field } from "@/components/ui"; // The text box.
import { shortDate } from "@/lib/scheduling"; // Short dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// One urgent flag, as the database gives it.
type Urgent = { id: string; student_id: string; student_name: string; tutor_name: string | null; subjects: string; upcoming_sessions: number; paid_sessions: number; first_session: string | null; upcoming_bookings: number }; // the child, current tutor, subjects, counts and first date.

// Shows the box (nothing at all when there are no urgent flags).
export async function UrgentRematchBox() { // The box itself.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("urgent_rematches"); // The open urgent flags (only matching admins get any).
  const rows = (data ?? []) as Urgent[]; // The flags.
  if (rows.length === 0) return null; // None: shows nothing.
  return ( // Shows:
    <section aria-labelledby="urgent-rematch" className="rounded-2xl border-2 border-red-700 bg-red-50 p-5 text-red-950">{/* a red box: */}
      <h2 id="urgent-rematch" className="text-lg font-bold">Urgent: needs a new tutor ({rows.length})</h2>{/* its heading and count, */}
      <p className="mt-1 text-sm">{/* what to do: */}
        These students can no longer have sessions with their tutor, but still have sessions booked, often already paid for.
        Please find a new tutor first, use &quot;Move sessions to a new tutor&quot; below, then mark it sorted. Don&apos;t contact the tutor about why.{/* the steps, and not to ask the tutor. */}
      </p>{/* End of the explanation. */}
      <ul className="mt-4 space-y-4">{/* the list: */}
        {rows.map((r) => ( // for each flag:
          <li key={r.id} className="rounded-xl border border-red-200 bg-white p-4 text-sm text-zinc-900">{/* a white box: */}
            <p className="font-semibold">{r.student_name}{r.subjects ? `: ${r.subjects}` : ""}</p>{/* the child and subjects, */}
            <p className="mt-1">{/* the counts: */}
              {r.paid_sessions} paid session(s) of {r.upcoming_sessions} booked{r.first_session ? `, first on ${shortDate(r.first_session)}` : ""}{r.upcoming_bookings ? `; ${r.upcoming_bookings} weekly booking(s) to move` : ""}. Currently booked with {r.tutor_name ?? "a former tutor"}.{/* paid, booked, first date, bookings and the current tutor. */}
            </p>{/* End of the counts. */}
            <p className="mt-2"><Link href={`/schedule/change-tutor?student=${r.student_id}`} className="font-medium text-red-900 underline underline-offset-4">Move sessions to a new tutor</Link></p>{/* a link to move this child's sessions. */}
            <div className="mt-3 max-w-md">{/* the form: */}
              <ActionForm action={markRematchSorted} submitLabel="Mark sorted">{/* marking it sorted: */}
                <input type="hidden" name="id" value={r.id} />{/* (which flag) */}
                <Field label="What was done?" name="note" required minLength={2} maxLength={1000} placeholder="e.g. Moved to Jack from 20 Nov" />{/* the note box. */}
              </ActionForm>{/* End of the form. */}
            </div>{/* End of the form area. */}
          </li> // End of the box.
        ))}{/* End of the loop. */}
      </ul>{/* End of the list. */}
    </section> // End of the red box.
  ); // End of what's shown.
} // End of UrgentRematchBox.
