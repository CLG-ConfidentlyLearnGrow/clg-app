// Summary: the fixed words the concerning-words pages show: the names of
// each kind of risk, each review decision, and each place in the app where
// text is checked. Kept in one file so the flags page and the word list
// use the same words. The checking itself happens in the database (see
// supabase/migrations/20261114100100_safety_watch_words.sql).

// The kinds of risk a word can point to, in the order the list shows them.
export const CATEGORY_LABELS: Record<string, string> = { // Each kind's database name and its plain name:
  self_harm: "Self-harm or suicide", // self-harm,
  abuse: "Abuse or neglect", // abuse,
  grooming: "Grooming signs (secrets, photos, being alone)", // grooming,
  off_platform: "Contact outside CLG", // moving contact off CLG,
  bullying: "Bullying", // bullying,
  violence: "Violence or weapons", // violence,
  sexual: "Sexual content", // sexual content,
  other: "Other", // anything else.
}; // End of the list.

// The decisions a reviewer can record on a flag.
export const FLAG_STATUS_LABELS: Record<string, string> = { // Each decision's database name and its plain name:
  new: "Not reviewed yet", // nobody has looked,
  following_up: "Following up", // being looked into,
  no_concern: "No concern (checked)", // checked, nothing wrong,
  raised_concern: "Raised as a child safety concern", // turned into a concern.
}; // End of the list.

// The places in the app where text is checked: table name, then box name.
const SOURCE_LABELS: Record<string, { place: string; fields: Record<string, string> }> = { // Each table's plain name and its boxes:
  session_notes: { place: "Session summary", fields: { went_well: "What went well", next_step: "Next step", homework: "Homework" } }, // session summaries,
  session_staff_notes: { place: "Staff note on a session", fields: { body: "Note" } }, // private staff notes,
  student_reflections: { place: "Student reflection", fields: { what_was_hard: "What was hard", what_i_will_try: "What I will try" } }, // student reflections,
  family_notes: { place: "Family note", fields: { body: "Note" } }, // family notes,
  learning_evidence: { place: "Uploaded work", fields: { title: "Title", note: "Note", tutor_comment: "Tutor comment" } }, // uploaded work,
  session_requests: { place: "Session request", fields: { note: "Family note", staff_note: "Staff note" } }, // requests for extra sessions,
  bookings: { place: "Booking", fields: { family_note: "Family note", tutor_note: "Tutor note" } }, // bookings,
  term_reviews: { place: "Term review", fields: { summary: "Summary", next_focus: "Next focus", recommendation_note: "Recommendation note", returned_reason: "Reason sent back", family_reply: "Family reply" } }, // term reviews,
  waitlist: { place: "Waitlist", fields: { note: "Note" } }, // the waitlist,
  student_sensitive: { place: "Learning needs", fields: { learning_needs: "Learning needs", support_strategies: "Support strategies" } }, // learning needs.
}; // End of the list.

// Says in words where a flagged piece of text was written, e.g. "Session summary, Next step".
export function sourceLabel(table: string, field: string): string { // Takes the table and box names.
  const source = SOURCE_LABELS[table]; // The table's plain names, if known.
  if (!source) return `${table}, ${field}`; // Unknown table: shows the database names.
  return `${source.place}, ${source.fields[field] ?? field}`; // The place and the box.
} // End of sourceLabel.
