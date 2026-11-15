// Summary: words used on the feedback pages, and the sums behind the
// overview (counts, average rating and change since the period before), kept
// here so both pages use the same ones.

// The three groups feedback is sorted into.
export const FEEDBACK_GROUPS = { app: "The app", service: "CLG's service", people: "People at CLG" } as const; // group id -> name on screen.

// The three kinds of feedback, with a symbol for each.
export const FEEDBACK_KINDS: Record<string, { label: string; icon: string }> = { // kind id -> words and symbol:
  praise: { label: "Praise: something going well", icon: "👍" }, // going well,
  idea: { label: "An idea to make it better", icon: "💡" }, // an idea,
  worry: { label: "A worry: something not working", icon: "⚠️" }, // needs work.
}; // End of the kinds.

// Where a piece of feedback is up to, in words.
export const FEEDBACK_STATUS: Record<string, string> = { new: "Not read yet", read: "Read", acting: "Being acted on", done: "Done" }; // stage id -> words.

// One piece of feedback, as the overview needs it.
export type FeedbackForSums = { kind: string; rating: number | null; created_at: string }; // its kind, rating and date.

// The sums for one area over a period.
export type FeedbackSums = { praise: number; idea: number; worry: number; total: number; avgRating: number | null }; // the counts and the average rating.

// Adds up a list of feedback: how many of each kind, and the average rating.
export function sumFeedback(rows: FeedbackForSums[]): FeedbackSums { // Takes the feedback; gives back the sums.
  const rated = rows.filter((r) => r.rating !== null); // Only the ones with a rating.
  return { // Hands back:
    praise: rows.filter((r) => r.kind === "praise").length, // how many praise,
    idea: rows.filter((r) => r.kind === "idea").length, // how many ideas,
    worry: rows.filter((r) => r.kind === "worry").length, // how many worries,
    total: rows.length, // how many in all,
    avgRating: rated.length ? Math.round((rated.reduce((t, r) => t + (r.rating ?? 0), 0) / rated.length) * 10) / 10 : null, // and the average rating to one decimal place (none if nobody rated).
  }; // End of the sums.
} // End of sumFeedback.

// Splits feedback into "this period" (the last `days` days) and "the period before" (the same length before that).
export function splitByPeriod<T extends { created_at: string }>(rows: T[], days: number, now = Date.now()): { current: T[]; previous: T[] } { // Takes the feedback and the period length.
  const dayMs = 24 * 60 * 60 * 1000; // One day in milliseconds.
  const start = now - days * dayMs; // When this period started.
  const prevStart = start - days * dayMs; // When the period before started.
  return { // Hands back:
    current: rows.filter((r) => Date.parse(r.created_at) >= start), // feedback in this period,
    previous: rows.filter((r) => { const t = Date.parse(r.created_at); return t >= prevStart && t < start; }), // and in the period before.
  }; // End of the split.
} // End of splitByPeriod.

// Says in words how the share of worries changed between two periods, so admins can see if an area is getting better.
export function trendWords(current: FeedbackSums, previous: FeedbackSums): string { // Takes this period's and the last period's sums.
  if (current.total === 0) return "No feedback in this period"; // Nothing to compare.
  if (previous.total === 0) return "New this period"; // Nothing before to compare with.
  const now = current.worry / current.total; // This period's share of worries.
  const before = previous.worry / previous.total; // The last period's share of worries.
  if (now < before - 0.1) return "Getting better (fewer worries than before)"; // Clearly fewer worries.
  if (now > before + 0.1) return "Needs attention (more worries than before)"; // Clearly more worries.
  return "About the same as before"; // Little change.
} // End of trendWords.

// The date and time a number of days ago, in the form the database expects.
export function periodStart(days: number, now = Date.now()): string { // Takes how many days back.
  return new Date(now - days * 24 * 60 * 60 * 1000).toISOString(); // That moment, written as an ISO date and time.
} // End of periodStart.
