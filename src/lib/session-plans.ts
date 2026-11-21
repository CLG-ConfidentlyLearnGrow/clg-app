// Summary: fixed values for the session summary and the plan for the next
// session (Carla, 21 Nov 2026), shared by the forms (in the browser) and the
// server. Tutors are paid 15 minutes after each session: about 5 minutes
// for the summary and about 10 minutes to plan the next session.

export const SUMMARY_MINUTES = 5; // Minutes guided for writing the session summary.
export const PLAN_MINUTES = 10; // Minutes guided for planning the next session.
export const AFTER_SESSION_MINUTES = SUMMARY_MINUTES + PLAN_MINUTES; // The 15 paid minutes in total.
export const MAX_SESSION_FILES = 10; // The most files one session can have (the database checks this too).
export const MAX_PLAN_MATERIALS = 10; // The most materials one plan can link (the database checks this too).
export const SESSION_CHANGE_DAYS = 7; // Days after a summary when the tutor can still correct it, its plan and its files.
