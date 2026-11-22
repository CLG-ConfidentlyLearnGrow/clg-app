// Summary: the Student Success Program box for a family (Carla, 22 Nov
// 2026), shown under each child on the family dashboard, and on an adult
// learner's own dashboard. It explains the program and shows where the
// student is up to: ask about it (a tick box), request waiting (cancel it),
// place offered (pay the $500 deposit in Billing; only the person who pays
// sees the due date and the link), or in the program. The database decides
// what this person may see and do.
//
import { Card, TextLink } from "@/components/ui"; // A card and a text link.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { SspAskForm, SspCancelForm } from "./ssp-family-forms"; // The family's forms.

// What the database gives back about the student's place.
type Status = { // The row:
  status: string | null; // where they are up to (nothing if never asked),
  can_ask: boolean; // whether this person can ask or cancel,
  requested_at: string | null; // when they asked,
  decline_reason: string | null; // any reason CLG gave,
  enrolled_at: string | null; // when they joined,
  is_payer: boolean; // whether this person pays for the family,
  deposit_due_on: string | null; // when the deposit is due (payers only).
}; // End of the type.

// A date as "22 November 2026" in Adelaide.
function longDate(iso: string): string { // Takes a date or time.
  return new Intl.DateTimeFormat("en-AU", { day: "numeric", month: "long", year: "numeric", timeZone: "Australia/Adelaide" }).format(new Date(iso.length === 10 ? `${iso}T12:00:00Z` : iso)); // Formats it (a plain date is read as midday, so it never slips a day).
} // End of longDate.

// The box for one student.
export async function SspFamilyBox({ studentId, name, self = false, inCard = false }: { studentId: string; name: string; self?: boolean; inCard?: boolean }) { // Takes the student, their first name, whether the reader is the student, and whether to wrap it in its own card.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("ssp_family_status", { p_student: studentId }); // Reads where they are up to (nothing if this person may not see it).
  const s = ((data ?? []) as Status[])[0]; // The one row.
  if (!s) return null; // Not theirs to see: shows nothing.
  if (!s.status && !s.can_ask) return null; // Never asked, and this person cannot ask: shows nothing.
  const who = self ? "you" : name; // "you" for an adult learner, otherwise the student's name.
  const about = ( // The plain explanation of the program:
    <p className="text-zinc-600">{/* grey words: */}
      The Student Success Program is a planned run of sessions with a study plan, each term review included, and priority when CLG finds a tutor. Places are limited. CLG looks at each request, and a $500 deposit confirms a place.{/* what it is. */}
    </p> // End of the words.
  ); // End of the explanation.
  const box = ( // The box:
    <div className="space-y-3 text-sm">{/* a block: */}
      {s.status === "enrolled" && ( // In the program:
        <p className="rounded-lg bg-violet-50 p-3 text-violet-900">{/* a violet box: */}
          {self ? "You are" : `${name} is`} in the Student Success Program{s.enrolled_at ? ` (since ${longDate(s.enrolled_at)})` : ""}.{/* that they are in it, and since when. */}
        </p> // End of the box.
      )}{/* End of this part. */}
      {s.status === "approved" && ( // A place offered, waiting for the deposit:
        <p className="rounded-lg bg-amber-50 p-3 text-amber-900">{/* an amber box: */}
          CLG has offered {who} a place in the Student Success Program. To confirm the place, the $500 deposit needs to be paid{s.deposit_due_on ? ` by ${longDate(s.deposit_due_on)}` : ""}.{" "}{/* the offer and due date (payers only), */}
          {s.is_payer ? <TextLink href="/billing">Pay the deposit in Billing</TextLink> : "The person who pays for your family's sessions can pay it in Billing."}{/* where to pay. */}
        </p> // End of the box.
      )}{/* End of this part. */}
      {s.status === "requested" && ( // A request waiting:
        <>{/* (a group) */}
          <p>You asked about the Student Success Program{s.requested_at ? ` on ${longDate(s.requested_at)}` : ""}. CLG will look at your request and let you know.</p>{/* when they asked and what happens next, */}
          {s.can_ask && <SspCancelForm studentId={studentId} />}{/* and the cancel button. */}
        </>  // End of the group.
      )}{/* End of this part. */}
      {(!s.status || ["declined", "withdrawn", "left"].includes(s.status)) && s.can_ask && ( // No request or place now:
        <>{/* (a group) */}
          {s.status === "declined" && <p>CLG was not able to offer a place last time{s.decline_reason ? `: ${s.decline_reason}` : "."} You are welcome to ask again.</p>}{/* the last answer, */}
          {s.status === "left" && <p>{self ? "You have" : `${name} has`} left the Student Success Program. You are welcome to ask again.</p>}{/* that they left, */}
          {about}{/* what the program is, */}
          <SspAskForm studentId={studentId} name={self ? "myself" : name} />{/* and the tick box. */}
        </>  // End of the group.
      )}{/* End of this part. */}
    </div> // End of the block.
  ); // End of the box.
  return inCard ? ( // Wrapped in its own fold-up card when asked (so nothing at all shows when there is nothing to show):
    <Card title="Student Success Program" collapsible defaultOpen={s.status === "approved"}>{/* open while a deposit is waiting, */}
      {box}{/* with the box inside. */}
    </Card> // End of the card.
  ) : box; // Otherwise just the box.
} // End of SspFamilyBox.
