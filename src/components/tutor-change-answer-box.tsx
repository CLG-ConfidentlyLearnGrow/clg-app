// Summary: the "Please confirm a change" box on the Sessions page, for a
// new tutor and for families (Carla, 15 Nov 2026: "A session which has been
// altered needs to be confirmed by the other or all parties before being
// confirmed"). It lists each tutor change CLG has asked them to confirm,
// with the old and new day and time, and lets them confirm or decline (a no
// needs a short reason). Nothing shows when there's nothing to answer.
// It also shows "Session cancelled: please choose what happens" for each
// session cancelled because a change was still waiting (Carla, 23 Nov
// 2026), with three choices: confirm the change, offer other times, or keep
// it cancelled.
//
import { answerChangeCancelledSession, answerTutorChange } from "@/app/actions/change-tutor"; // The server actions that save the answers.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Field } from "@/components/ui"; // The card and the text box.
import { sessionWhen, shortDate } from "@/lib/scheduling"; // A session's time and short dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// One change to answer, as the database gives it.
type ToAnswer = { id: string; answer_as: "tutor" | "family"; student_name: string; subject: string; from_tutor_name: string | null; to_tutor_name: string | null; from_date: string; sessions: number; old_time: string; new_time: string }; // who answers as what, the student, subject, tutors, date, count and times.

// One session cancelled while a change waited, as the database gives it.
type Cancelled = { session_id: string; offer_id: string; answer_as: "tutor" | "family"; student_name: string; subject: string; starts_at: string; from_tutor_name: string | null; to_tutor_name: string | null; change_waiting: boolean; can_confirm: boolean }; // the session, the change, who answers as what, the student, subject, time, tutors, and whether the change can still be confirmed.

// Shows the boxes.
export async function TutorChangeAnswerBox() { // The boxes themselves.
  const supabase = await createClient(); // Connects to the database.
  const [changes, cancelled] = await Promise.all([ // Reads both at once:
    supabase.rpc("my_tutor_changes_to_answer"), // the changes waiting for this person,
    supabase.rpc("my_change_cancelled_sessions"), // and the sessions cancelled while a change waited.
  ]); // End of the reads.
  const rows = (changes.data ?? []) as ToAnswer[]; // The changes.
  const cancelledRows = (cancelled.data ?? []) as Cancelled[]; // The cancelled sessions.
  if (rows.length === 0 && cancelledRows.length === 0) return null; // None: shows nothing.
  return ( // Shows:
    <>{/* both boxes: */}
    {cancelledRows.length > 0 && <CancelledWhileWaiting rows={cancelledRows} />}{/* the cancelled sessions first (they are the most urgent), */}
    {rows.length > 0 && ( // then the changes to confirm, if any:
    <Card title="Please confirm a change" description="CLG would like to change these sessions. Nothing changes until you and the others have confirmed.">{/* a card: */}
      <ul className="space-y-6">{/* the list: */}
        {rows.map((r) => ( // for each change:
          <li key={r.id} className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm">{/* an amber box: */}
            <p className="font-semibold">{/* what's changing: */}
              {r.answer_as === "tutor" ? `Take over ${r.student_name}'s ${r.subject} sessions` : `${r.student_name}'s ${r.subject} sessions with ${r.to_tutor_name ?? "a new tutor"}`}{/* for a tutor, taking over; for a family, the new tutor */}
            </p>{/* End of the heading. */}
            <p className="mt-1">{/* the details: */}
              From {shortDate(r.from_date)}, {r.sessions} session(s) booked.{r.answer_as === "family" && r.from_tutor_name ? ` Currently with ${r.from_tutor_name}.` : ""}{/* the date, how many, and (for families) the current tutor, */}
              {r.new_time ? ` New time: ${r.new_time}${r.old_time ? ` (was ${r.old_time})` : ""}.` : r.old_time ? ` Same time: ${r.old_time}.` : " Same days and times."}{/* and the new or same time. */}
            </p>{/* End of the details. */}
            <div className="mt-3 grid gap-4 sm:grid-cols-2">{/* the two answers side by side: */}
              <ActionForm action={answerTutorChange} submitLabel="Confirm">{/* a yes: */}
                <input type="hidden" name="id" value={r.id} />{/* (which change) */}
                <input type="hidden" name="answer" value="yes" />{/* (yes) */}
              </ActionForm>{/* End of the yes. */}
              <ActionForm action={answerTutorChange} submitLabel="Decline">{/* a no: */}
                <input type="hidden" name="id" value={r.id} />{/* (which change) */}
                <input type="hidden" name="answer" value="no" />{/* (no) */}
                <Field label="Why does not it suit?" name="note" required minLength={2} maxLength={500} placeholder="e.g. Thursdays do not work for us" />{/* the reason box. */}
              </ActionForm>{/* End of the no. */}
            </div>{/* End of the answers. */}
          </li> // End of the box.
        ))}{/* End of the loop. */}
      </ul>{/* End of the list. */}
    </Card> // End of the card.
    )}{/* End of the changes to confirm. */}
    </>/* End of both boxes. */
  ); // End of what's shown.
} // End of TutorChangeAnswerBox.

// The "Session cancelled: please choose what happens" box: one amber box per
// session, with the three choices.
function CancelledWhileWaiting({ rows }: { rows: Cancelled[] }) { // Takes the cancelled sessions.
  return ( // Shows:
    <Card title="Session cancelled: please choose what happens" description="These sessions are cancelled because a change to them is still waiting for confirmation. The first answer counts.">{/* a card: */}
      <ul className="space-y-6">{/* the list: */}
        {rows.map((r) => ( // for each session:
          <li key={r.session_id} className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm">{/* an amber box: */}
            <p className="font-semibold">{r.student_name}: {r.subject}, {sessionWhen(r.starts_at)}</p>{/* which session, */}
            <p className="mt-1">{/* what has happened: */}
              {r.answer_as === "tutor" // for the new tutor:
                ? "This session is cancelled because the change to you is still waiting for confirmation." // why,
                : `This session${r.from_tutor_name ? ` with ${r.from_tutor_name}` : ""} is cancelled because the change to ${r.to_tutor_name ?? "a new tutor"} is still waiting for confirmation. There is no charge for it.`}{/* for the family: why, and the money. */}
            </p>{/* End of what has happened. */}
            <div className="mt-3 grid gap-4 sm:grid-cols-3">{/* the three choices side by side: */}
              {r.can_confirm ? ( // they can still confirm the change:
                <ActionForm action={answerTutorChange} submitLabel="Confirm the change">{/* confirm: */}
                  <input type="hidden" name="id" value={r.offer_id} />{/* (which change) */}
                  <input type="hidden" name="answer" value="yes" />{/* (yes) */}
                  <p className="text-xs text-neutral-600">If everyone confirms in time, this session comes back with the new tutor.</p>{/* what happens. */}
                </ActionForm> // End of confirm.
              ) : ( // they have already confirmed (or the change is closed):
                <p className="text-xs text-neutral-600">{r.change_waiting ? "You have confirmed the change. If the others confirm in time, this session comes back." : "The change is no longer waiting. Please offer other times or keep it cancelled."}</p> // where it is up to.
              )}{/* End of confirm. */}
              <ActionForm action={answerChangeCancelledSession} submitLabel="Offer other times">{/* other times: */}
                <input type="hidden" name="session" value={r.session_id} />{/* (which session) */}
                <input type="hidden" name="choice" value="other_times" />{/* (other times) */}
                <Field label="Which days and times suit?" name="note" required minLength={2} maxLength={1000} placeholder="e.g. Friday after 4pm" />{/* the times box. */}
              </ActionForm>{/* End of other times. */}
              <ActionForm action={answerChangeCancelledSession} submitLabel="Keep it cancelled">{/* keep cancelled: */}
                <input type="hidden" name="session" value={r.session_id} />{/* (which session) */}
                <input type="hidden" name="choice" value="kept_cancelled" />{/* (keep it cancelled) */}
                <p className="text-xs text-neutral-600">{r.answer_as === "family" ? "The session stays cancelled, with no charge." : "The session stays cancelled."}</p>{/* what happens. */}
              </ActionForm>{/* End of keep cancelled. */}
            </div>{/* End of the choices. */}
          </li> // End of the box.
        ))}{/* End of the loop. */}
      </ul>{/* End of the list. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of CancelledWhileWaiting.
