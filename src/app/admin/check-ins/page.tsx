// Summary: the Check-ins page for the owner and operations admins (Carla,
// 16 Nov 2026). After a new match, the tutor, the parents and a learner with
// their own login are each asked how it is going 1 week, 2 weeks and 6 weeks
// after the first session. This page shows:
//   * answers flagged for follow-up (rated 1 or 2, "not a good fit", or
//     asking CLG to make contact), with a form to mark each followed up;
//   * each new match's check-ins: who was asked, who answered, and the
//     average rating;
//   * the latest answers in full.
// Only full admins can read the answers; the database enforces that.
// See docs/features/match-check-ins.md.
//
import type { ReactNode } from "react"; // The type for "anything that can be shown".
import { followUpCheckIn } from "@/app/actions/check-ins"; // The server action that marks an answer followed up.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, Select, Table, TextArea } from "@/components/ui"; // Shared page parts: card, empty note, drop-down, table and multi-line box.
import { FULL_ADMIN, requireAdminLevel } from "@/lib/auth"; // The owner-and-operations group, and the admin check.
import { CHECK_IN_FIT, CHECK_IN_STAGES, CHECK_IN_WHO, checkInSince } from "@/lib/check-ins"; // The check-in words, and the start of "recent".
import { shortDate } from "@/lib/scheduling"; // Shows a date in a short, friendly way.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// One answer, as the database gives it.
type Answer = { // Its fields:
  id: string; // its id,
  tutor_id: string; // the tutor in the match,
  student_id: string; // the learner in the match,
  stage: number; // which check-in,
  respondent_kind: string; // the role they answered in,
  respondent_name: string; // who answered,
  tutor_name: string; // the tutor's name,
  student_name: string; // the learner's name,
  skipped: boolean; // whether they skipped it,
  rating: number | null; // the rating (if answered),
  fit: string | null; // the fit (if answered),
  wants_contact: boolean; // whether they asked CLG to contact them,
  comment: string | null; // their comment (if any),
  follow_up: string; // "none", "open" or "done",
  follow_up_note: string | null; // the admins' private note,
  followed_up_at: string | null; // when it was followed up,
  created_at: string; // when they answered.
}; // End of the shape.

// One check-in for one match, from the overview.
type Row = { // Its fields:
  tutor_id: string; // the tutor,
  student_id: string; // the learner,
  tutor_name: string; // the tutor's name,
  student_name: string; // the learner's name,
  stage: number; // which check-in,
  opens_at: string; // when it opens,
  closes_at: string; // when it closes,
  is_closed: boolean; // whether it has closed,
  asked: number; // how many people were asked,
  answered: number; // how many answered,
  skipped: number; // how many skipped.
}; // End of the shape.

// A short line saying what one person answered.
function summary(a: Answer): ReactNode { // Takes the answer.
  if (a.skipped) return a.wants_contact ? "Skipped the questions, but asked CLG to make contact" : "Skipped"; // A skip (with or without a contact request).
  const parts = [`Rated ${a.rating}/5`, `Good fit: ${CHECK_IN_FIT[a.fit ?? ""] ?? "Not given"}`]; // The rating and the fit,
  if (a.wants_contact) parts.push("Asked CLG to make contact"); // and a contact request, if any.
  return parts.join(" · "); // Joined with dots.
} // End of summary.

// Why an answer was flagged, in words.
function reasons(a: Answer): string { // Takes the answer.
  const out: string[] = []; // The reasons being built.
  if (!a.skipped && a.rating !== null && a.rating <= 2) out.push(`a low rating (${a.rating}/5)`); // a low rating,
  if (!a.skipped && a.fit === "no") out.push("not a good fit"); // not a good fit,
  if (a.wants_contact) out.push("asked CLG to make contact"); // a contact request.
  return out.length ? `Flagged for ${out.join(", ")}.` : ""; // The sentence, or nothing.
} // End of reasons.

// Shows the page (owner and operations admins only).
export default async function CheckInsPage() { // The page itself.
  const viewer = await requireAdminLevel(FULL_ADMIN); // Must be the owner or an operations admin, with two-step sign-in.
  const supabase = await createClient(); // Connects to the database.
  const since = checkInSince(); // About four months ago (long enough to cover a whole 6-week cycle and more).
  const [answersRes, overviewRes] = await Promise.all([ // Reads two things at once:
    supabase.from("match_check_ins").select("*").or(`follow_up.eq.open,created_at.gte.${since}`).order("created_at", { ascending: false }).limit(300), // open flags (however old) and recent answers,
    supabase.rpc("check_in_overview"), // and every new match's check-ins.
  ]); // End of the reads.
  const answers = (answersRes.data ?? []) as Answer[]; // The answers.
  const overview = (overviewRes.data ?? []) as Row[]; // The check-ins that have opened so far.
  const open = answers.filter((a) => a.follow_up === "open"); // Answers waiting for follow-up.
  const recent = answers.filter((a) => a.created_at >= since); // Recent answers.

  // Shows one answer, with the follow-up form when it was flagged.
  const item = (a: Answer) => ( // Takes the answer:
    <li key={a.id} className="rounded-xl border border-zinc-200 p-3">{/* a bordered box: */}
      <p className="text-sm">{/* its heading line: */}
        <strong>{a.student_name} with {a.tutor_name}</strong>{/* the match, */}
        <span className="text-zinc-500"> · {CHECK_IN_STAGES[a.stage] ?? "Check-in"} · {CHECK_IN_WHO[a.respondent_kind] ?? a.respondent_kind}: {a.respondent_name} · {shortDate(a.created_at)}</span>{/* the check-in, who answered and when. */}
      </p>{/* End of the heading line. */}
      <p className="mt-1 text-sm">{summary(a)}</p>{/* What they answered. */}
      {a.comment && <p className="mt-1 whitespace-pre-wrap text-sm text-zinc-700">&ldquo;{a.comment}&rdquo;</p>}{/* Their comment, if any. */}
      {a.follow_up !== "none" && ( // If it was flagged:
        <details className="mt-2" open={a.follow_up === "open"}>{/* an open-and-close box for following it up (open while waiting): */}
          <summary className="cursor-pointer text-sm text-teal-800">{a.follow_up === "open" ? `Needs follow-up. ${reasons(a)}` : `Followed up${a.followed_up_at ? ` ${shortDate(a.followed_up_at)}` : ""}${a.follow_up_note ? ": has a note" : ""}`}</summary>{/* where it is up to, */}
          <div className="mt-2">{/* the form: */}
            <ActionForm action={followUpCheckIn} submitLabel="Save">{/* following it up: */}
              <input type="hidden" name="id" value={a.id} />{/* (which answer) */}
              <Select label="Has this been followed up?" name="done" defaultValue="yes">{/* the drop-down (saving usually means it has been followed up): */}
                <option value="yes">Yes, followed up</option>{/* followed up, */}
                <option value="no">No, still needs follow-up</option>{/* or still waiting. */}
              </Select>{/* End of the drop-down. */}
              <TextArea label="Private note (the family and the tutor cannot see this)" name="note" defaultValue={a.follow_up_note ?? ""} maxLength={2000} rows={2} />{/* the note box. */}
            </ActionForm>{/* End of the form. */}
          </div>{/* End of the form area. */}
        </details> // End of the follow-up box.
      )}{/* End of the flagged part. */}
    </li> // End of the item.
  ); // End of item.

  // The average rating given for one check-in of one match (or a dash when none).
  const average = (r: Row) => { // Takes the overview row.
    const rated = answers.filter((a) => a.tutor_id === r.tutor_id && a.student_id === r.student_id && a.stage === r.stage && a.rating !== null); // Its rated answers.
    if (rated.length === 0) return "–"; // None yet.
    return (rated.reduce((t, a) => t + (a.rating ?? 0), 0) / rated.length).toFixed(1); // The average, to one decimal place.
  }; // End of average.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="check-ins">{/* the dashboard frame, */}
      <div className="space-y-6">{/* the page's parts, with space between: */}
        <Card title="Check-ins after a new match" description="The tutor, the parents and the learner (if they have their own login) are each asked how it is going 1 week, 2 weeks and 6 weeks after their first session. Answers are only seen by the owner and operations admins.">{/* an explanation card: */}
          <p className="text-sm">An answer is flagged for follow-up when it is rated 1 or 2, says it is not a good fit, or asks CLG to make contact.</p>{/* what gets flagged. */}
        </Card>{/* End of the explanation. */}

        <Card title={`Needs follow-up (${open.length})`} description="Contact the person, then mark it followed up with a short note.">{/* the flagged answers: */}
          {open.length === 0 ? <Empty>Nothing needs follow-up.</Empty> : <ul className="space-y-2">{open.map(item)}</ul>}{/* "Nothing" or the list. */}
        </Card>{/* End of the flagged answers. */}

        <Card title="New matches" description="Each check-in that has opened so far, with how many people answered." collapsible defaultOpen>{/* the overview: */}
          {overview.length === 0 ? ( // none yet:
            <Empty>No new matches have reached a check-in yet.</Empty> // says so,
          ) : ( // otherwise:
            <Table headings={["Match", "Check-in", "Opened", "Answered", "Average rating"]}>{/* a table: */}
              {overview.map((r) => ( // each check-in:
                <tr key={`${r.tutor_id}-${r.student_id}-${r.stage}`}>{/* a row: */}
                  <td>{r.student_name} with {r.tutor_name}</td>{/* the match, */}
                  <td>{CHECK_IN_STAGES[r.stage] ?? r.stage}</td>{/* the check-in, */}
                  <td>{shortDate(r.opens_at)}{r.is_closed ? " (closed)" : ""}</td>{/* when it opened, and whether it has closed, */}
                  <td>{r.answered} of {r.asked}{r.skipped ? ` (${r.skipped} skipped)` : ""}</td>{/* how many answered, */}
                  <td>{average(r)}</td>{/* the average rating. */}
                </tr> // End of the row.
              ))}{/* End of the rows. */}
            </Table> // End of the table.
          )}{/* End of the choice. */}
        </Card>{/* End of the overview. */}

        <Card title="Latest answers" description="Every answer from about the last four months, newest first." collapsible defaultOpen={false}>{/* the latest answers: */}
          {recent.length === 0 ? <Empty>No answers yet.</Empty> : <ul className="space-y-2">{recent.map(item)}</ul>}{/* "None" or the list. */}
        </Card>{/* End of the latest answers. */}
      </div>{/* End of the page's parts. */}
    </DashboardFrame> // End of the frame.
  ); // End of what is shown.
} // End of CheckInsPage.
