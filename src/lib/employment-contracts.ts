// Summary: shared words and helpers for employment contracts (Carla, 17 Nov
// 2026). The kinds of contract, where a contract is up to, and the gap
// reader that finds the [gaps] in a template, so the send form can show a box
// for each gap an admin needs to type. The database fills the gaps for real
// when a contract is sent (see supabase/migrations/20261121200100_employment_contracts.sql);
// this file only mirrors its rules for the screens.
// See docs/features/employment-contracts.md.

// The kinds of contract the app knows.
export const CONTRACT_TYPES = ["tutor_casual", "tutor_permanent", "admin_casual", "admin_permanent"] as const; // Tutor casual, tutor part-time or full-time, and the two for admin-only staff.
export type ContractType = (typeof CONTRACT_TYPES)[number]; // One of those kinds.

// Each kind of contract in words.
export const CONTRACT_TYPE_NAMES: Record<ContractType, string> = { // The words for each kind:
  tutor_casual: "Tutor, casual", // casual tutors,
  tutor_permanent: "Tutor, part-time or full-time", // part-time and full-time tutors,
  admin_casual: "Admin staff, casual", // casual admin-only staff (template to come),
  admin_permanent: "Admin staff, part-time or full-time", // part-time and full-time admin-only staff (template to come).
}; // End of the words.

// The employment types, and their words.
export const EMPLOYMENT_NAMES = { casual: "Casual", part_time: "Part-time", full_time: "Full-time" } as const; // Casual, part-time, full-time.
export type Employment = keyof typeof EMPLOYMENT_NAMES; // One of those types.

// Which employment types each kind of contract can be sent for.
export function employmentsFor(type: ContractType): Employment[] { // Takes the kind of contract.
  return type.endsWith("_casual") ? ["casual"] : ["part_time", "full_time"]; // Casual contracts are casual; the others are part-time or full-time.
} // End of employmentsFor.

// The role a kind of contract is for (the person must hold it).
export function roleFor(type: ContractType): "tutor" | "admin" { // Takes the kind of contract.
  return type.startsWith("tutor") ? "tutor" : "admin"; // Tutor contracts need the tutor role; admin ones the admin role.
} // End of roleFor.

// Where a sent contract is up to, in words.
export const CONTRACT_STATUS_NAMES = { // The words for each status:
  sent: "Waiting to be signed", // sent, not signed yet,
  signed: "Signed, documents to acknowledge", // signed, but documents still to acknowledge,
  complete: "Complete", // signed and every document acknowledged,
  withdrawn: "Withdrawn", // withdrawn or replaced.
} as const; // End of the words.
export type ContractStatus = keyof typeof CONTRACT_STATUS_NAMES; // One of those statuses.

// Where a template version is up to, in words.
export const TEMPLATE_STATUS_NAMES = { draft: "Draft", published: "In use", retired: "Replaced" } as const; // Draft, in use, replaced.

// The gaps that fill in by themselves, by key, with what they show. Any of
// these words can be put in square brackets in a template.
export const AUTO_GAPS: Record<string, string> = { // Each automatic gap's key and description:
  tutor_name: "their full name", // [Tutor name]
  staff_name: "their full name", // [Staff name]
  employee_name: "their full name", // [Employee name]
  full_name: "their full name", // [Full name]
  first_name: "their first name", // [First name]
  last_name: "their last name", // [Last name]
  email: "their app email", // [Email]
  tutor_email: "their app email", // [Tutor email]
  staff_email: "their app email", // [Staff email]
  app_email: "their app email", // [App email]
  phone: "their phone number", // [Phone]
  employment_type: "casual, part-time or full-time", // [Employment type]
  full_time_or_part_time: "casual, part-time or full-time", // [Full-time or Part-time]
  part_time_or_full_time: "casual, part-time or full-time", // [Part-time or Full-time]
  date_sent: "the date it is sent", // [Date sent]
  clg_name: "CLG Tutoring", // [CLG name]
  clg_abn: "CLG's ABN", // [CLG ABN]
  clg_signatory: "Carla Gore, Director", // [CLG signatory]
}; // End of the automatic gaps.

// One gap found in a template.
export type Gap = { // Its fields:
  key: string; // its key (lower case words joined by underscores), shared by every copy of the gap,
  label: string; // its words as written (without any ", or ..." ending), for the box's label,
  fallback: string | null; // what it shows when left empty (null when it must be filled in),
  auto: boolean; // whether it fills in by itself.
}; // End of the shape.

// Turns a gap's words into its key, the same way the database does.
export function gapKey(words: string): string { // Takes the words inside the brackets.
  const key = words.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, ""); // Lower case; anything else becomes one underscore; underscores trimmed from the ends.
  return key || "gap"; // "gap" if nothing is left.
} // End of gapKey.

// The pattern for a gap: {{words}}, or [words] (also \[words\] from a
// Markdown export), but not [words] straight before "(" (that is a link).
const GAP_PATTERN = /\{\{\s*([^{}]+?)\s*\}\}|\\?\[([^\][\\]+?)\\?\](?!\()/g; // Matches either kind of gap.

// Finds every different gap in a template's title and wording, in order.
export function findGaps(text: string): Gap[] { // Takes the template text.
  const found = new Map<string, Gap>(); // The gaps found so far, by key (each once).
  for (const m of text.matchAll(GAP_PATTERN)) { // Goes through each gap:
    let words = (m[1] ?? m[2] ?? "").trim(); // its words, from whichever kind of brackets,
    let fallback: string | null = null; // required unless shown otherwise,
    if (/\?$/.test(words)) { // ending with "?":
      fallback = "Not applicable"; // optional, showing "Not applicable",
      words = words.replace(/\?$/, "").trim(); // without the "?".
    } else { // Otherwise:
      const or = words.match(/,\s*or\s+(\S.*)$/i); // looks for a ", or ..." ending,
      if (or) { // and if there is one:
        fallback = or[1].trim(); // optional, showing the words after "or",
        words = words.slice(0, or.index).trim(); // keeping the words before it.
      } // End of the ", or" check.
    } // End of the optional checks.
    const key = gapKey(words); // Its key.
    if (!found.has(key)) found.set(key, { key, label: words, fallback, auto: key in AUTO_GAPS }); // Keeps the first copy of each gap.
  } // End of the loop.
  return [...found.values()]; // Hands back the gaps, in the order first seen.
} // End of findGaps.

// The ending of a contract record's address, for links.
export const contractHref = (id: string) => `/contract?id=${id}`; // The staff member's own page for one contract.
