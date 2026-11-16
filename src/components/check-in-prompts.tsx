// Summary: the check-in cards at the top of the tutor, parent and student
// dashboards (Carla, 16 Nov 2026). After a new match, each person is asked
// how it is going 1 week, 2 weeks and 6 weeks after the first session, and
// how it went (and how the ending was handled) once the match ends. A
// card shows only while a check-in is waiting for them (never during quiet
// hours, 9pm to 5am their time), and disappears once they answer or skip it.
// The answers are private: only the owner and operations admins read them.
// See docs/features/match-check-ins.md.
//
import { answerCheckIn } from "@/app/actions/check-ins"; // The server action that saves an answer or a skip.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Select, TextArea } from "@/components/ui"; // The card, drop-down and multi-line box.
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import { CHECK_IN_FIT, CHECK_IN_RATINGS, CHECK_IN_STAGES, ENDING_RATINGS, checkInQuestions, type CheckInKind } from "@/lib/check-ins"; // The check-in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// One waiting check-in, as the database gives it.
type Waiting = { // Its fields:
  tutor_id: string; // the tutor in the match,
  student_id: string; // the learner in the match,
  stage: number; // which check-in (0 for the end of a match, or 1, 2 or 6),
  respondent_kind: CheckInKind; // the role the person answers in,
  tutor_first_name: string; // the tutor's first name,
  student_first_name: string; // the learner's first name.
}; // End of the shape.

// Shows a card for each check-in waiting for the signed-in person on this
// dashboard. Admin dashboards have none, so nothing is shown there.
export async function CheckInPrompts({ role }: { role: Role }) { // Takes the dashboard.
  if (role === "admin") return null; // Admins are not asked (they read the answers instead).
  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase.rpc("my_check_ins", { p_as: role }); // Asks for this dashboard's waiting check-ins.
  if (error || !data || data.length === 0) return null; // None (or a problem reading them): shows nothing, so the dashboard still works.
  const waiting = data as Waiting[]; // The waiting check-ins.
  return ( // Shows:
    <div className="mb-6 space-y-4">{/* a column of cards above the page, with space under it: */}
      {waiting.map((w) => { // for each waiting check-in:
        const q = checkInQuestions(w.respondent_kind, w.tutor_first_name, w.student_first_name, w.stage); // the questions in the right words,
        const key = `${w.tutor_id}-${w.student_id}-${w.stage}`; // a key that is the same each time for this check-in,
        return ( // shows:
          <Card key={key} title={q.heading} description={`${CHECK_IN_STAGES[w.stage] ?? "Check-in"}. It takes less than a minute. Only CLG's office team sees your answers.`}>{/* a card with the heading and a short explanation: */}
            <ActionForm action={answerCheckIn} submitLabel="Send">{/* the answer form: */}
              <input type="hidden" name="tutor" value={w.tutor_id} />{/* (which tutor) */}
              <input type="hidden" name="student" value={w.student_id} />{/* (which learner) */}
              <input type="hidden" name="stage" value={String(w.stage)} />{/* (which check-in) */}
              <Select label={q.rating} name="rating" defaultValue="" required>{/* the rating drop-down: */}
                <option value="" disabled>Choose one</option>{/* a starting prompt, */}
                {CHECK_IN_RATINGS.map((r) => ( // then each rating:
                  <option key={r.value} value={r.value}>{r.label}</option> // as an option.
                ))}{/* End of the ratings. */}
              </Select>{/* End of the drop-down. */}
              {w.stage === 0 ? ( // At the end of a match:
                <Select label={q.ending} name="ending" defaultValue="" required>{/* the ending drop-down: */}
                  <option value="" disabled>Choose one</option>{/* a starting prompt, */}
                  {ENDING_RATINGS.map((r) => ( // then each rating:
                    <option key={r.value} value={r.value}>{r.label}</option> // as an option.
                  ))}{/* End of the ratings. */}
                </Select> // End of the drop-down.
              ) : ( // Otherwise (1, 2 or 6 weeks):
                <Select label={q.fit} name="fit" defaultValue="" required>{/* the fit drop-down: */}
                  <option value="" disabled>Choose one</option>{/* a starting prompt, */}
                  {Object.entries(CHECK_IN_FIT).map(([value, label]) => ( // then each answer:
                    <option key={value} value={value}>{label}</option> // as an option.
                  ))}{/* End of the answers. */}
                </Select> // End of the drop-down.
              )}{/* End of the choice. */}
              <TextArea label="Anything else you would like to tell us? (optional)" name="comment" maxLength={2000} rows={2} />{/* the comment box, */}
              <label className="flex items-start gap-2 text-sm">{/* a tick box with its words: */}
                <input type="checkbox" name="contact" value="yes" className="mt-1" />{/* the tick box, */}
                <span>Please contact me about this</span>{/* and its words. */}
              </label>{/* End of the tick box. */}
              <p className="text-xs text-red-700">If you are worried about a child&apos;s safety, please use <strong>Child safety</strong> at the top of the page instead, so the right person sees it straight away.</p>{/* where child safety worries go, in red. */}
            </ActionForm>{/* End of the answer form. */}
            <div className="mt-3">{/* the skip form, a little apart: */}
              <ActionForm action={answerCheckIn} submitLabel="Skip this check-in">{/* skipping: */}
                <input type="hidden" name="tutor" value={w.tutor_id} />{/* (which tutor) */}
                <input type="hidden" name="student" value={w.student_id} />{/* (which learner) */}
                <input type="hidden" name="stage" value={String(w.stage)} />{/* (which check-in) */}
                <input type="hidden" name="skip" value="yes" />{/* (marks it as a skip) */}
              </ActionForm>{/* End of the skip form. */}
            </div>{/* End of the skip area. */}
          </Card> // End of the card.
        ); // End of what is shown for this check-in.
      })}{/* End of the check-ins. */}
    </div> // End of the column.
  ); // End of what is shown.
} // End of CheckInPrompts.
