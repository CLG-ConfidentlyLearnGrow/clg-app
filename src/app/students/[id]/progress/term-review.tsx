// Summary: the term review card: the tutor writes a review, CLG checks it, and the family reads and replies.
//
import { Card, SubHeading, Table } from "@/components/ui"; // The card, small heading and table.
import { RECOMMENDATION_NAMES, levelName } from "@/lib/progress"; // Recommendation names, and skill level names.
import { addDays, localToday, shortDate } from "@/lib/scheduling"; // Adds days to a date, today's date, and dates in short form.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { dollars } from "@/lib/billing/money"; // Shows cents as dollars.
import { TermReviewForm, TermReviewOfferForm, TermReviewReplyForm } from "./forms"; // The forms for writing a review, answering an offer, and replying.

// A term review as the database gives it.
export type Review = {
  id: string; // its id,
  tutor_id: string | null; // the tutor who writes it,
  term_label: string; // the term's name,
  term_ends_on: string; // the term's last day,
  due_on: string | null; // when the tutor should send it (blank for older reviews),
  summary: string | null; // how the term went,
  next_focus: string | null; // the focus for next term,
  recommendation: string | null; // the recommendation,
  recommendation_note: string | null; // a note on it,
  status: "draft" | "submitted" | "returned" | "approved"; // where it's up to,
  returned_reason: string | null; // why CLG sent it back (if it did),
  family_reply: string | null; // the family's reply,
  wants_call: boolean; // whether they want a call,
  family_replied_at: string | null; // and when they replied.
}; // End of the shape.
// One skill in a goal: its level at the start of term and now.
type GoalRow = {
  goal_id: string; // the goal's id,
  goal_title: string; // the goal's title,
  subject: string; // the subject,
  skill: string; // the skill,
  level_at_start: string; // the level at the start,
  level_now: string; // the level now.
}; // End of the shape.

export const REVIEW_FIELDS = // The review fields to read:
  "id, tutor_id, term_label, term_ends_on, due_on, summary, next_focus, recommendation, recommendation_note, status, returned_reason, family_reply, wants_call, family_replied_at"; // (the list).

// Each goal's skills at the start of the term and now.
export async function ReviewGoals({ reviewId }: { reviewId: string }) {
  const supabase = await createClient(); // Connects to the database.
  const res = await supabase.rpc("term_review_goals", { p_review: reviewId }); // Reads the goals for this review.
  const rows = (res.data ?? []) as GoalRow[]; // The rows.
  if (rows.length === 0) return <p className="text-sm text-zinc-500">No goals were set this term.</p>; // None: says so.
  return ( // Shows:
    <Table headings={["Goal", "Skill", "Start of term", "Now"]}>{/* a table with these headings: */}
      {rows.map((r, i) => ( // for each row:
        <tr key={`${r.goal_id}-${i}`}>{/* a row: */}
          <td className="font-medium">{r.goal_title}</td>{/* the goal, */}
          <td>{r.skill}</td>{/* the skill, */}
          <td>{levelName(r.level_at_start)}</td>{/* the level at the start, */}
          <td className={r.level_now !== r.level_at_start ? "font-semibold text-teal-800" : ""}>{/* the level now, in bold teal if it changed: */}
            {levelName(r.level_now)}{/* (the level's name) */}
          </td>{/* (end of the cell) */}
        </tr> // End of the row.
      ))}{/* End of the loop. */}
    </Table> // End of the table.
  ); // End of what's shown.
} // End of ReviewGoals.

// Shows the words of a review.
export function ReviewText({ review }: { review: Review }) {
  return ( // Shows:
    <div className="space-y-3 text-sm">{/* a block with space between parts: */}
      <div>{/* a group: */}
        <p className="font-medium">How the term went</p>{/* the heading "How the term went", */}
        <p className="whitespace-pre-line">{review.summary}</p>{/* and the words, keeping line breaks. */}
      </div>{/* End of the group. */}
      <div>{/* A group: */}
        <p className="font-medium">Focus for next term</p>{/* the heading "Focus for next term", */}
        <p className="whitespace-pre-line">{review.next_focus}</p>{/* and the words, keeping line breaks. */}
      </div>{/* End of the group. */}
      {review.recommendation && ( // If there's a recommendation:
        <p>{/* a line: */}
          <strong>Recommendation:</strong> {RECOMMENDATION_NAMES[review.recommendation] ?? review.recommendation}{/* the recommendation in words, */}
          {review.recommendation_note && `. ${review.recommendation_note}`}{/* and the note, if any. */}
        </p> // End of the line.
      )}{/* End of the recommendation. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of ReviewText.

// On the progress page. The tutor writes their review here; the family
// reads the latest checked review and can reply.
export async function TermReviewCard({
  studentId, // the student,
  viewerId, // who is looking,
  isStaff, // whether they're staff,
  isFamily, // whether they're family.
}: { // (their types:)
  studentId: string; // an id,
  viewerId: string; // an id,
  isStaff: boolean; // true or false,
  isFamily: boolean; // true or false.
}) { // (end of the settings)
  const supabase = await createClient(); // Connects to the database.
  const res = await supabase // Reads the reviews:
    .from("term_reviews") // from the term reviews table,
    .select(REVIEW_FIELDS) // with their fields,
    .eq("student_id", studentId) // for this student,
    .order("term_ends_on", { ascending: false }) // latest term first,
    .limit(5); // at most 5.
  const reviews = (res.data ?? []) as Review[]; // The reviews.

  if (isStaff) { // For staff:
    const mine = reviews.find((r) => r.tutor_id === viewerId && r.status !== "approved"); // this tutor's review that isn't approved yet.
    if (!mine) return null; // None: shows nothing.
    return ( // Shows:
      <Card // a card:
        title={`${mine.term_label} review`} // titled with the term,
        description={`Please send it by ${shortDate(mine.due_on ?? addDays(mine.term_ends_on, -14))}, so CLG can check it before it goes to the family.`} // with the date it's due by (its own due date, or 2 weeks before the end for older reviews).
      >{/* (end of the card's settings) */}
        <ReviewGoals reviewId={mine.id} />{/* The goals table, */}
        {mine.status === "returned" && mine.returned_reason && ( // if CLG sent it back:
          <p className="mt-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">{/* an amber note: */}
            CLG asked for a change: {mine.returned_reason}{/* with CLG's reason. */}
          </p> // End of the note.
        )}{/* End of that part. */}
        <div className="mt-5">{/* A block: */}
          {mine.status === "submitted" ? ( // if it's been sent:
            <>{/* (a group:) */}
              <p className="mb-3 text-sm text-zinc-600">Sent to CLG to check.</p>{/* a note that it's with CLG, */}
              <ReviewText review={mine} />{/* and the words. */}
            </> // (end of the group)
          ) : ( // Otherwise:
            <TermReviewForm studentId={studentId} review={mine} /> // the review form.
          )}{/* End of the choice. */}
        </div>{/* End of the block. */}
      </Card> // End of the card.
    ); // End of what's shown.
  } // End of the staff case.

  if (isFamily) { // For family:
    const latest = reviews.find((r) => r.status === "approved"); // the latest approved review.
    if (!latest) return null; // None: shows nothing.
    return ( // Shows:
      <Card collapsible title={`${latest.term_label} review`} description="From your tutor, checked by CLG.">{/* a card titled with the term: */}
        <ReviewGoals reviewId={latest.id} />{/* the goals table, */}
        <div className="mt-5">{/* a block: */}
          <ReviewText review={latest} />{/* the review's words. */}
        </div>{/* End of the block. */}
        <SubHeading>Reply</SubHeading>{/* A small heading "Reply", */}
        {latest.family_replied_at ? ( // if they've replied:
          <p className="text-sm text-zinc-600">{/* a thank-you line: */}
            Thanks for your reply{latest.wants_call ? ". CLG will be in touch to arrange a call." : "."}{/* mentioning the call if they asked for one. */}
          </p> // End of the line.
        ) : ( // Otherwise:
          <TermReviewReplyForm studentId={studentId} reviewId={latest.id} /> // the reply form.
        )}{/* End of the choice. */}
      </Card> // End of the card.
    ); // End of what's shown.
  } // End of the family case.
  return null; // Anyone else: shows nothing.
} // End of TermReviewCard.

// An offer of a paid term review, as the database gives it.
type Offer = {
  id: string; // its id,
  period_label: string; // what it's the end of, for example "Term 4 2026",
  period_ends_on: string; // the last day (also the last day to answer),
  price_cents: number; // the price, including any GST,
  gst_applies: boolean; // whether that price includes GST,
  answer: "waiting" | "yes" | "no"; // the answer so far.
}; // End of the shape.

// On the progress page, for the family member who answers (a managing
// parent, or a student who manages their own account): the latest offer of
// a paid term review that is still open, with the price and a yes or no.
// The database shows offers only to them and CLG admins, never to tutors.
export async function TermReviewOfferCard({ studentId, isFamily }: { studentId: string; isFamily: boolean }) {
  if (!isFamily) return null; // Only in the family view.
  const supabase = await createClient(); // Connects to the database.
  const res = await supabase // Reads the offer:
    .from("term_review_offers") // from the offers table,
    .select("id, period_label, period_ends_on, price_cents, gst_applies, answer") // with its details,
    .eq("student_id", studentId) // for this student,
    .gte("period_ends_on", localToday()) // still open (not past its end),
    .order("period_ends_on", { ascending: false }) // latest first,
    .limit(1) // just one,
    .maybeSingle(); // (or none).
  const offer = res.data as Offer | null; // The offer, if any.
  if (!offer) return null; // None: shows nothing.
  const price = `${dollars(offer.price_cents)}${offer.gst_applies ? " including GST" : ""}`; // The price in words.
  return ( // Shows:
    <Card title={`Term review for ${offer.period_label}?`} description={`A written review from your tutor. ${price}.`}>{/* a card with the period and price: */}
      <p className="mb-4 text-sm text-zinc-700">{/* a line saying what's in it: */}
        It covers how it went, each goal&apos;s skills at the start and now, and what to focus on next. CLG checks it
        before you see it, and you can reply or ask for a call.{/* (what the review includes) */}
      </p>{/* End of the line. */}
      {offer.answer === "yes" ? ( // If they've said yes:
        <p className="text-sm text-zinc-600">Booked. Your tutor is writing it, and you&apos;ll see it here once CLG has checked it.</p> // says it's booked.
      ) : ( // Otherwise:
        <>{/* (a group:) */}
          {offer.answer === "no" && ( // if they said no:
            <p className="mb-3 text-sm text-zinc-600">You said no thanks. You can change your mind until {shortDate(offer.period_ends_on)}.</p> // says they can still change their mind,
          )}{/* (end of that line) */}
          <p className="mb-3 text-sm text-zinc-600">{/* a line: */}
            Please answer by {shortDate(offer.period_ends_on)}. If you don&apos;t answer, no review is written and nothing is charged.{/* the last day, and that silence costs nothing. */}
          </p>{/* End of the line. */}
          <TermReviewOfferForm studentId={studentId} offerId={offer.id} staff={false} />{/* The yes or no form. */}
        </> // (end of the group)
      )}{/* End of the choice. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of TermReviewOfferCard.
