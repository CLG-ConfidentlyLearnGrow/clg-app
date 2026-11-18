// Summary: the Tutor lateness page for the owner and operations admins
// (Carla, 18 Nov 2026). It shows:
//   * late starts waiting for review (a tutor who signed on more than
//     5 minutes after the start, or who sent a "Running late" notice), with
//     a form to mark each reviewed with a private note;
//   * how many late starts each tutor has had in the last 90 days, so a
//     pattern is easy to see;
//   * every late start from the last 6 months.
// Only full admins can read the record; the database enforces that.
// See docs/features/tutor-work-rules.md.
//
import { reviewLateness } from "@/app/actions/lateness"; // The server action that marks a late start reviewed.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, Table, TextArea } from "@/components/ui"; // Shared page parts: card, empty note, table and multi-line box.
import { FULL_ADMIN, requireAdminLevel } from "@/lib/auth"; // The owner-and-operations group, and the admin check.
import { currentTime, sessionWhen } from "@/lib/scheduling"; // The time now, and a session's day and time in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// One late start, as the database gives it.
type Line = { // Its fields:
  id: string; // its id,
  tutor_id: string; // the tutor,
  tutor_name: string; // the tutor's name,
  student_first_name: string; // the learner's first name,
  subject: string; // the subject,
  starts_at: string; // when the session was booked to start,
  told_at: string | null; // when the tutor said they were running late (if they did),
  told_minutes: number | null; // about how late they said,
  told_reason: string | null; // why (CLG only),
  told_count: number; // how many notices they sent,
  told_before_start: boolean | null; // whether the first notice was before the start,
  signed_on_late_minutes: number | null; // how many minutes late they signed on (if more than 5),
  review_status: string; // "open" or "reviewed",
  review_note: string | null; // the admins' private note,
  reviewed_at: string | null; // when it was reviewed,
  counts_as_late: boolean; // whether it counts as a late start.
}; // End of the shape.

// A short line saying what happened.
function what(l: Line): string { // Takes the line.
  const parts: string[] = []; // The parts being built.
  if (l.signed_on_late_minutes != null) parts.push(`Signed on ${l.signed_on_late_minutes} minutes after the start`); // how late they signed on,
  if (l.told_minutes != null) parts.push(`Gave notice ${l.told_before_start ? "before" : "after"} the start: about ${l.told_minutes} minutes${l.told_count > 1 ? ` (${l.told_count} notices)` : ""}`); // the notice they gave,
  else parts.push("No notice given"); // or that they gave none.
  if (l.told_reason) parts.push(`Reason: ${l.told_reason}`); // and the reason, if any.
  return parts.join(" · "); // Joined with dots.
} // End of what.

// Shows the page (owner and operations admins only).
export default async function LatenessPage() { // The page itself.
  const viewer = await requireAdminLevel(FULL_ADMIN); // Must be the owner or an operations admin, with two-step sign-in.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("list_session_lateness", { p_days: 180 }); // Reads open lines and the last 6 months.
  const lines = ((data ?? []) as Line[]).filter((l) => l.counts_as_late); // Only real late starts (not a notice followed by an on-time sign-on).
  const open = lines.filter((l) => l.review_status === "open"); // Lines waiting for review.
  const since90 = currentTime() - 90 * 24 * 3600 * 1000; // 90 days ago.
  const perTutor = new Map<string, { name: string; n: number; noNotice: number }>(); // Late starts in the last 90 days, by tutor.
  for (const l of lines) { // For each line:
    if (new Date(l.starts_at).getTime() < since90) continue; // older than 90 days: skips it.
    const t = perTutor.get(l.tutor_id) ?? { name: l.tutor_name, n: 0, noNotice: 0 }; // the tutor's counts so far,
    t.n += 1; // one more late start,
    if (l.told_minutes == null || !l.told_before_start) t.noNotice += 1; // and one more without notice before the start, if so.
    perTutor.set(l.tutor_id, t); // saves the counts.
  } // End of the loop.
  const tutors = [...perTutor.values()].sort((a, b) => b.n - a.n); // Most late starts first.

  // Shows one line, with the review form while it is open.
  const item = (l: Line) => ( // Takes the line:
    <li key={l.id} className="rounded-xl border border-zinc-200 p-3">{/* a bordered box: */}
      <p className="text-sm">{/* its heading line: */}
        <strong>{l.tutor_name}</strong>{/* the tutor, */}
        <span className="text-zinc-500"> · {sessionWhen(l.starts_at)} · {l.student_first_name} · {l.subject}</span>{/* when, the learner and the subject. */}
      </p>{/* End of the heading line. */}
      <p className="mt-1 text-sm">{what(l)}</p>{/* What happened. */}
      {l.review_status === "reviewed" ? ( // Already reviewed:
        <p className="mt-1 text-xs text-zinc-600">Reviewed{l.review_note ? `: ${l.review_note}` : ""}</p> // the note.
      ) : ( // Otherwise:
        <div className="mt-2">{/* the form: */}
          <ActionForm action={reviewLateness} submitLabel="Mark reviewed">{/* marking it reviewed: */}
            <input type="hidden" name="id" value={l.id} />{/* (which line) */}
            <TextArea label="Private note (the tutor cannot see this)" name="note" required minLength={3} maxLength={1000} rows={2} placeholder="For example: talked with the tutor about leaving earlier" />{/* the note box. */}
          </ActionForm>{/* End of the form. */}
        </div> // End of the form area.
      )}{/* End of the choice. */}
    </li> // End of the item.
  ); // End of item.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="lateness">{/* the dashboard frame, */}
      <div className="space-y-6">{/* the page's parts, with space between: */}
        <Card title="Tutor lateness" description="Late starts by tutors, so CLG can follow up early and fairly. Only the owner and operations admins see this page.">{/* an explanation card: */}
          <p className="text-sm">A late start is recorded when a tutor signs on more than 5 minutes after the booked start, or sends a &ldquo;Running late&rdquo; notice from their Sessions page. The family gets the notice (without the reason); CLG sees it here.</p>{/* what is recorded, */}
          <p className="mt-2 text-sm">Session pay already starts from when the tutor signed on, so time not worked is not paid. Tutors see their own late starts, but not your notes.</p>{/* pay and what tutors see. */}
        </Card>{/* End of the explanation. */}

        <Card title={`Waiting for review (${open.length})`} description="Check what happened, talk with the tutor if needed, then mark it reviewed with a short note.">{/* the open lines: */}
          {open.length === 0 ? <Empty>Nothing is waiting for review.</Empty> : <ul className="space-y-2">{open.map(item)}</ul>}{/* "Nothing" or the list. */}
        </Card>{/* End of the open lines. */}

        <Card title="Late starts in the last 90 days, by tutor" collapsible defaultOpen>{/* the counts: */}
          {tutors.length === 0 ? ( // none:
            <Empty>No late starts in the last 90 days.</Empty> // says so,
          ) : ( // otherwise:
            <Table headings={["Tutor", "Late starts", "Without notice before the start"]}>{/* a table: */}
              {tutors.map((t) => ( // each tutor:
                <tr key={t.name}>{/* a row: */}
                  <td>{t.name}</td>{/* the tutor, */}
                  <td>{t.n}</td>{/* how many late starts, */}
                  <td>{t.noNotice}</td>{/* and how many without notice before the start. */}
                </tr> // End of the row.
              ))}{/* End of the rows. */}
            </Table> // End of the table.
          )}{/* End of the choice. */}
        </Card>{/* End of the counts. */}

        <Card title="All late starts (last 6 months)" collapsible defaultOpen={false}>{/* every line: */}
          {lines.length === 0 ? <Empty>No late starts recorded.</Empty> : <ul className="space-y-2">{lines.map(item)}</ul>}{/* "None" or the list. */}
        </Card>{/* End of every line. */}
      </div>{/* End of the page's parts. */}
    </DashboardFrame> // End of the frame.
  ); // End of what is shown.
} // End of LatenessPage.
