// Summary: shared words and limits for tutor applications: where each
// application is up to, the reasons for declining, how people can teach,
// the check answers, the privacy notice version, and the spam limits. Used
// by the public "Apply to tutor" form and the admin queue. See
// docs/features/tutor-applications.md.

// Where an application is up to, in the order the admin queue shows them.
export const APPLICATION_STATUSES = ["new", "shortlisted", "approved", "declined", "withdrawn"] as const; // The fixed list (matches the database).
export type ApplicationStatus = (typeof APPLICATION_STATUSES)[number]; // One of those (for type checking).

// Each status in words.
export const APPLICATION_STATUS_NAMES: Record<ApplicationStatus, string> = { // status -> words:
  new: "New", // just arrived,
  shortlisted: "Shortlisted", // being interviewed and checked,
  approved: "Approved", // invited to join,
  declined: "Declined", // not this time,
  withdrawn: "Withdrawn", // the person pulled out (or stopped replying).
}; // End of the names.

// Reasons for declining (matches the database's list). Kept private to admins.
export const DECLINE_REASONS = ["not_needed", "location_times", "experience", "referees", "child_safety", "no_reply", "other"] as const; // The fixed list.
export type DeclineReason = (typeof DECLINE_REASONS)[number]; // One of those (for type checking).

// Each decline reason in words.
export const DECLINE_REASON_NAMES: Record<DeclineReason, string> = { // reason -> words:
  not_needed: "Subjects or year levels not needed right now", // no demand for what they teach,
  location_times: "Location or availability doesn't suit", // wrong place or times,
  experience: "Experience or qualifications don't match what we need", // not the right background,
  referees: "Referee checks", // referees raised concerns,
  child_safety: "Child safety screening", // a child safety concern (talk to the Child Safety Officer),
  no_reply: "Didn't reply or attend the interview", // went quiet,
  other: "Other (see note)", // anything else.
}; // End of the reason names.

// How someone can teach.
export const TEACH_MODES = ["in_person", "online", "both"] as const; // The fixed list (matches the database).
export const TEACH_MODE_NAMES: Record<(typeof TEACH_MODES)[number], string> = { // mode -> words:
  in_person: "In person", // face to face,
  online: "Online", // over Teams,
  both: "In person and online", // either.
}; // End of the mode names.

// Working with Children Check answers.
export const WWCC_STATUSES = ["held", "applied", "not_yet"] as const; // The fixed list (matches the database).
export const WWCC_STATUS_NAMES: Record<(typeof WWCC_STATUSES)[number], string> = { // answer -> words:
  held: "I have one", // already holds a check,
  applied: "I've applied", // waiting for it,
  not_yet: "Not yet", // hasn't applied.
}; // End of the check answer names.

// RRHAN-EC training answers.
export const RRHAN_STATUSES = ["done", "not_yet"] as const; // The fixed list (matches the database).
export const RRHAN_STATUS_NAMES: Record<(typeof RRHAN_STATUSES)[number], string> = { done: "Done", not_yet: "Not yet" }; // answer -> words.

// First aid answers.
export const FIRST_AID_STATUSES = ["current", "not_yet"] as const; // The fixed list (matches the database).
export const FIRST_AID_STATUS_NAMES: Record<(typeof FIRST_AID_STATUSES)[number], string> = { current: "Current", not_yet: "Not yet" }; // answer -> words.

// The version of the collection notice on the form. Change it when the notice changes.
export const APPLICATION_NOTICE_VERSION = "2026-11-16";

// Spam limits: the form must be open at least this long before sending
// (people take minutes; bots take a second), and no longer than this
// (an old form page might be a copied one).
export const MIN_FILL_SECONDS = 20; // At least 20 seconds.
export const MAX_FILL_HOURS = 24; // At most 24 hr.

// The largest CV accepted: 3.5MB, the same as other uploads (server actions take up to 4MB in total).
export const MAX_CV_BYTES = 3.5 * 1024 * 1024;

// Child-safe interview questions for admins to use, based on South
// Australia's Child Safe Environments safe recruitment guidance and the
// National Principles for Child Safe Organisations (Principle 5). They ask
// about real past behaviour, which says more than "what would you do".
export const INTERVIEW_QUESTIONS = [ // The questions:
  "Why do you want to work with children and young people?", // motivation,
  "Tell us about a time you helped a student who was stuck or losing confidence. What did you do?", // teaching practice,
  "What do you think are appropriate boundaries between a tutor and a student, in person and online?", // boundaries,
  "Tell us about a time you had to deal with a young person's challenging behaviour. What happened?", // behaviour,
  "If a student told you something that worried you about their safety, what would you do?", // responding to disclosure,
  "Tell us about a time you saw a colleague do something you felt was not right. What did you do?", // speaking up,
  "How would you keep a parent informed about their child's progress?", // working with families,
  "Is there anything we should know that might affect your suitability to work with children?", // direct suitability question.
] as const; // End of the questions (fixed).

// Questions to ask each referee (ideally by phone).
export const REFEREE_QUESTIONS = [ // The questions:
  "How do you know the applicant, and for how long?", // relationship,
  "Have you seen them work with children or young people? How did they go?", // direct experience,
  "Did you ever have any concerns about their behaviour around children or young people?", // direct child safety question,
  "Would you employ them again in a role working with children? Why or why not?", // re-employ question,
] as const; // End of the referee questions (fixed).
