// Summary: shared words and rules for problem reports (the "Report a
// problem" form and the reviewers' queue): status and priority names, the
// screenshot limits, and a helper that takes ids out of a page address
// before anything is sent outside CLG.
//

// Where a report is up to, in the order reviewers usually move it.
export const PROBLEM_STATUSES = ["new", "checking", "approved", "fixed", "closed"] as const; // The five statuses (fixed list).
export type ProblemStatus = (typeof PROBLEM_STATUSES)[number]; // One of those statuses (for type checking).

// The words shown for each status.
export const PROBLEM_STATUS_LABELS: Record<ProblemStatus, string> = { // Each status and its words:
  new: "New", // just sent, nobody has looked yet,
  checking: "Being checked", // a reviewer is looking into it,
  approved: "Approved to fix", // a reviewer agrees it needs fixing,
  fixed: "Fixed", // the fix is live,
  closed: "Closed (no change)", // not a problem, a duplicate, or won't be changed.
}; // End of the status words.

// How soon a report needs attention.
export const PROBLEM_PRIORITIES = ["urgent", "normal", "low"] as const; // The three priorities (fixed list).
export type ProblemPriority = (typeof PROBLEM_PRIORITIES)[number]; // One of those priorities (for type checking).

// The words shown for each priority.
export const PROBLEM_PRIORITY_LABELS: Record<ProblemPriority, string> = { // Each priority and its words:
  urgent: "Urgent (privacy, safety or money)", // needs attention today,
  normal: "Normal", // the usual,
  low: "Low", // nice to fix some time.
}; // End of the priority words.

// The most screenshots one report can have (the database checks this too).
export const MAX_SCREENSHOTS = 6; // Six pictures.

// The largest one screenshot may be once it reaches the server. The form
// shrinks pictures before sending, so they're usually far smaller. Six at
// this size stay under the 4 MB limit for one form.
export const MAX_SCREENSHOT_BYTES = 600 * 1024; // 600 KB.

// The longest side a screenshot is shrunk to before sending. Big enough to
// read text on a computer screenshot, small enough to send quickly.
export const SCREENSHOT_MAX_SIDE = 1600; // 1600 pixels.

// A problem report as reviewers see it.
export type ProblemReport = { // The report's details:
  id: string; // its id,
  reporter_name: string; // who sent it,
  what_happened: string; // what went wrong,
  trying_to: string | null; // what they were trying to do (if given),
  page: string | null; // the page they were on (if known),
  device: string | null; // their browser and device (if known),
  status: ProblemStatus; // where it's up to,
  priority: ProblemPriority; // how soon it needs attention,
  reply: string | null; // the reply the reporter sees (if any),
  reviewer_notes: string | null; // reviewers' private notes (if any),
  fix_summary: string | null; // the fix for the developer, with no personal details (if written),
  github_issue_url: string | null; // the GitHub issue made from it (if any),
  created_at: string; // when it was sent,
  updated_at: string; // when a reviewer last changed it,
}; // End of the shape.

// Takes ids (long codes like 3f2b...-...) and anything after "?" out of a
// page address, so a GitHub issue never carries a link to a real student or
// family. "/students/3f2b.../progress?tab=x" becomes "/students/[id]/progress".
export function pageWithoutIds(page: string | null): string { // Takes the page address (or nothing).
  if (!page) return "(not known)"; // No page: says so.
  return page // Starting from the address:
    .split("?")[0] // keeps only the part before "?" (the settings after it can name people),
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, "[id]"); // and swaps every id for "[id]".
} // End of pageWithoutIds.
