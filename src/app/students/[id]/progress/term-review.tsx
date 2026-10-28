import { Card, SubHeading, Table } from "@/components/ui";
import { RECOMMENDATION_NAMES, levelName } from "@/lib/progress";
import { addDays, shortDate } from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";
import { TermReviewForm, TermReviewReplyForm } from "./forms";

export type Review = {
  id: string;
  tutor_id: string | null;
  term_label: string;
  term_ends_on: string;
  summary: string | null;
  next_focus: string | null;
  recommendation: string | null;
  recommendation_note: string | null;
  status: "draft" | "submitted" | "returned" | "approved";
  returned_reason: string | null;
  family_reply: string | null;
  wants_call: boolean;
  family_replied_at: string | null;
};
type GoalRow = {
  goal_id: string;
  goal_title: string;
  subject: string;
  skill: string;
  level_at_start: string;
  level_now: string;
};

export const REVIEW_FIELDS =
  "id, tutor_id, term_label, term_ends_on, summary, next_focus, recommendation, recommendation_note, status, returned_reason, family_reply, wants_call, family_replied_at";

// Each goal's skills at the start of the term and now.
export async function ReviewGoals({ reviewId }: { reviewId: string }) {
  const supabase = await createClient();
  const res = await supabase.rpc("term_review_goals", { p_review: reviewId });
  const rows = (res.data ?? []) as GoalRow[];
  if (rows.length === 0) return <p className="text-sm text-zinc-500">No goals were set this term.</p>;
  return (
    <Table headings={["Goal", "Skill", "Start of term", "Now"]}>
      {rows.map((r, i) => (
        <tr key={`${r.goal_id}-${i}`}>
          <td className="font-medium">{r.goal_title}</td>
          <td>{r.skill}</td>
          <td>{levelName(r.level_at_start)}</td>
          <td className={r.level_now !== r.level_at_start ? "font-semibold text-teal-800" : ""}>
            {levelName(r.level_now)}
          </td>
        </tr>
      ))}
    </Table>
  );
}

export function ReviewText({ review }: { review: Review }) {
  return (
    <div className="space-y-3 text-sm">
      <div>
        <p className="font-medium">How the term went</p>
        <p className="whitespace-pre-line">{review.summary}</p>
      </div>
      <div>
        <p className="font-medium">Focus for next term</p>
        <p className="whitespace-pre-line">{review.next_focus}</p>
      </div>
      {review.recommendation && (
        <p>
          <strong>Recommendation:</strong> {RECOMMENDATION_NAMES[review.recommendation] ?? review.recommendation}
          {review.recommendation_note && `. ${review.recommendation_note}`}
        </p>
      )}
    </div>
  );
}

// On the progress page. The tutor writes their review here; the family
// reads the latest checked review and can reply.
export async function TermReviewCard({
  studentId,
  viewerId,
  isStaff,
  isFamily,
}: {
  studentId: string;
  viewerId: string;
  isStaff: boolean;
  isFamily: boolean;
}) {
  const supabase = await createClient();
  const res = await supabase
    .from("term_reviews")
    .select(REVIEW_FIELDS)
    .eq("student_id", studentId)
    .order("term_ends_on", { ascending: false })
    .limit(5);
  const reviews = (res.data ?? []) as Review[];

  if (isStaff) {
    const mine = reviews.find((r) => r.tutor_id === viewerId && r.status !== "approved");
    if (!mine) return null;
    return (
      <Card
        title={`${mine.term_label} review`}
        description={`Please send it by ${shortDate(addDays(mine.term_ends_on, -14))}, so CLG can check it before the family is asked about next term.`}
      >
        <ReviewGoals reviewId={mine.id} />
        {mine.status === "returned" && mine.returned_reason && (
          <p className="mt-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
            CLG asked for a change: {mine.returned_reason}
          </p>
        )}
        <div className="mt-5">
          {mine.status === "submitted" ? (
            <>
              <p className="mb-3 text-sm text-zinc-600">Sent to CLG to check.</p>
              <ReviewText review={mine} />
            </>
          ) : (
            <TermReviewForm studentId={studentId} review={mine} />
          )}
        </div>
      </Card>
    );
  }

  if (isFamily) {
    const latest = reviews.find((r) => r.status === "approved");
    if (!latest) return null;
    return (
      <Card collapsible title={`${latest.term_label} review`} description="From your tutor, checked by CLG.">
        <ReviewGoals reviewId={latest.id} />
        <div className="mt-5">
          <ReviewText review={latest} />
        </div>
        <SubHeading>Reply</SubHeading>
        {latest.family_replied_at ? (
          <p className="text-sm text-zinc-600">
            Thanks for your reply{latest.wants_call ? ". CLG will be in touch to arrange a call." : "."}
          </p>
        ) : (
          <TermReviewReplyForm studentId={studentId} reviewId={latest.id} />
        )}
      </Card>
    );
  }
  return null;
}
