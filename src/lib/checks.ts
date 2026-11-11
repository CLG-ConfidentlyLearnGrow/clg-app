// Summary: names for child safety checks and Australian states, shown in the
// app, plus which checks need a card number and the days of the week.

// The Australian states and territories, as short codes.
export const STATES = ["SA", "NSW", "VIC", "QLD", "WA", "TAS", "ACT", "NT"] as const;
// The allowed state codes, for type checking.
export type AuState = (typeof STATES)[number];

// The full name of each state, shown to people.
export const STATE_NAMES: Record<AuState, string> = {
  SA: "South Australia", // SA's full name.
  NSW: "New South Wales", // NSW's full name.
  VIC: "Victoria", // VIC's full name.
  QLD: "Queensland", // QLD's full name.
  WA: "Western Australia", // WA's full name.
  TAS: "Tasmania", // TAS's full name.
  ACT: "Australian Capital Territory", // ACT's full name.
  NT: "Northern Territory", // NT's full name.
}; // End of the state names.

// Every kind of check a tutor can record (the codes the database uses).
export const CHECK_KINDS = [
  "wwcc_sa", // SA Working With Children Check.
  "wwcc_nsw", // NSW Working With Children Check.
  "wwc_vic", // VIC Working with Children Check.
  "blue_card_qld", // QLD blue card.
  "wwc_wa", // WA Working with Children Check.
  "rwvp_tas", // TAS vulnerable people registration.
  "wwvp_act", // ACT vulnerable people registration.
  "ochre_card_nt", // NT Ochre Card.
  "rrhan_ec_fundamentals", // SA mandatory reporting training, part 1.
  "rrhan_ec_masterclass", // SA mandatory reporting training, part 2.
  "police_check", // Optional national police check.
  "first_aid", // Optional first aid certificate.
] as const; // "as const" keeps the exact codes for type checking.
// The allowed check codes, for type checking.
export type CheckKind = (typeof CHECK_KINDS)[number];

// The name of each check, as shown to people.
export const CHECK_NAMES: Record<CheckKind, string> = {
  wwcc_sa: "SA Working With Children Check", // Shown name for wwcc_sa.
  wwcc_nsw: "NSW Working With Children Check", // Shown name for wwcc_nsw.
  wwc_vic: "VIC Working with Children Check", // Shown name for wwc_vic.
  blue_card_qld: "QLD blue card", // Shown name for blue_card_qld.
  wwc_wa: "WA Working with Children Check", // Shown name for wwc_wa.
  rwvp_tas: "TAS Registration to Work with Vulnerable People", // Shown name for rwvp_tas.
  wwvp_act: "ACT Working with Vulnerable People registration", // Shown name for wwvp_act.
  ochre_card_nt: "NT Working with Children Clearance (Ochre Card)", // Shown name for ochre_card_nt.
  rrhan_ec_fundamentals: "RRHAN-EC Fundamentals", // Shown name for the Fundamentals course.
  rrhan_ec_masterclass: "RRHAN-EC Masterclass", // Shown name for the Masterclass course.
  police_check: "National police check (optional, valid 5 years from issue)", // Shown name for the police check.
  first_aid: "First aid certificate (optional)", // Shown name for first aid.
}; // End of the check names.

// Screening checks carry a card or registration number; training and
// first aid certificates do not need one.
export const NEEDS_REFERENCE: ReadonlySet<CheckKind> = new Set(
  CHECK_KINDS.filter((k) => !k.startsWith("rrhan") && k !== "first_aid"), // Every check except RRHAN-EC courses and first aid.
); // End of the needs-a-number list.

// Turns a check code into its shown name, or shows the code if unknown.
export const checkName = (kind: string) => CHECK_NAMES[kind as CheckKind] ?? kind;

// The days of the week, Monday first, as used across the app.
export const WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
