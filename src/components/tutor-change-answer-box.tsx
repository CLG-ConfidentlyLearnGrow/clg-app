// Summary: the "Please confirm a change" box on the Sessions page, for a
// new tutor and for families (Carla, 15 Nov 2026: "A session which has been
// altered needs to be confirmed by the other or all parties before being
// confirmed"). It lists each tutor change CLG has asked them to confirm,
// with the old and new day and time, and lets them confirm or decline (a no
// needs a short reason). Nothing shows when there's nothing to answer.
//
import { answerTutorChange } from "@/app/actions/change-tutor"; // The server action that saves the answer.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Field } from "@/components/ui"; // The card and the text box.
import { shortDate } from "@/lib/scheduling"; // Short dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// One change to answer, as the database gives it.
type ToAnswer = { id: string; answer_as: "tutor" | "family"; student_name: string; subject: string; from_tutor_name: string | null; to_tutor_name: string | null; from_date: string; sessions: number; old_time: string; new_time: string }; // who answers as what, the student, subject, tutors, date, count and times.

// Shows the box.
export async function TutorChangeAnswerBox() { // The box itself.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("my_tutor_changes_to_answer"); // The changes waiting for this person.
  const rows = (data ?? []) as ToAnswer[]; // The changes.
  if (rows.length === 0) return null; // None: shows nothing.
  return ( // Shows:
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
                <Field label="Why doesn't it suit?" name="note" required minLength={2} maxLength={500} placeholder="e.g. Thursdays don't work for us" />{/* the reason box. */}
              </ActionForm>{/* End of the no. */}
            </div>{/* End of the answers. */}
          </li> // End of the box.
        ))}{/* End of the loop. */}
      </ul>{/* End of the list. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of TutorChangeAnswerBox.
