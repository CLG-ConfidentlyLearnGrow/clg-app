// Summary: words used on the help chat pages (Carla, 16 Nov 2026), kept in
// one place so every page names topics, stages and missing details the same
// way. The database holds the same lists (see the help chat migration).

// What a chat can be about. The topic decides which admins answer it:
// billing and staff pay go to owner, operations and finance admins; the rest
// go to owner, operations and support admins.
export const HELP_TOPICS: Record<string, string> = { // topic id -> words on screen:
  missing_info: "Missing information", // a detail CLG needs (school, year level and so on),
  sessions: "Sessions and bookings", // session times, changes and bookings,
  matching: "Finding a tutor", // being matched with a tutor,
  billing: "Billing and payments", // invoices and payments,
  pay: "My pay (CLG staff)", // pay questions from tutors and staff,
  app: "Using the app", // how to do something in the app,
  other: "Something else", // anything else.
}; // End of the topics.

// The topics each kind of person sees first in the drop-down. Staff pay is
// only offered to tutors and staff.
export function topicsFor(isStaff: boolean): string[] { // Takes whether the person is a tutor or admin.
  return Object.keys(HELP_TOPICS).filter((t) => t !== "pay" || isStaff); // Every topic, leaving out staff pay for families.
} // End of topicsFor.

// Where a chat is up to, in words. "You" means the family or person asking;
// the admin pages use the CLG words instead.
export const HELP_STATUS_FOR_MEMBER: Record<string, string> = { // stage id -> words for the person asking:
  waiting_on_clg: "Waiting for CLG to reply", // their turn is done,
  waiting_on_you: "CLG has replied", // CLG has answered,
  closed: "Closed", // finished.
}; // End of the member words.
export const HELP_STATUS_FOR_CLG: Record<string, string> = { // stage id -> words for CLG's admins:
  waiting_on_clg: "Waiting for CLG", // CLG needs to reply,
  waiting_on_you: "Waiting for them", // waiting for the person,
  closed: "Closed", // finished.
}; // End of the CLG words.

// The missing details the matching page can ask a family about. The keys
// match the "item" in /help/new?student=...&item=... links.
export const MISSING_ITEMS: Record<string, string> = { // item id -> words on screen:
  year_level: "Year level", // the child's year level,
  school: "School", // the child's school,
  session_places: "Session places", // where sessions can happen,
  booking_length: "How long to book", // how long to book sessions for.
}; // End of the missing details.

// True when the text is one of the missing detail keys above.
export function isMissingItem(item: string | undefined | null): item is string { // Takes the text from the address.
  return !!item && Object.prototype.hasOwnProperty.call(MISSING_ITEMS, item); // Yes only for a known key.
} // End of isMissingItem.

// One chat in the list, as the database gives it.
export type HelpChatRow = { // Its fields:
  id: string; // its id,
  subject: string; // its title,
  topic: string; // what it is about,
  status: string; // whose turn it is, or closed,
  student_name: string | null; // the student it is about (if any),
  missing_item: string | null; // the missing detail (if any),
  started_by_name: string; // who started it,
  started_by_clg: boolean; // whether CLG started it,
  assigned_name: string | null; // the admin looking after it (help desk list only),
  created_at: string; // when it was started,
  last_message_at: string; // when the latest message was written,
  unread: boolean; // whether there is a message they have not read.
}; // End of the shape.
