// Names for child safety checks and Australian states, shown in the app.

export const STATES = ["SA", "NSW", "VIC", "QLD", "WA", "TAS", "ACT", "NT"] as const;
export type AuState = (typeof STATES)[number];

export const STATE_NAMES: Record<AuState, string> = {
  SA: "South Australia",
  NSW: "New South Wales",
  VIC: "Victoria",
  QLD: "Queensland",
  WA: "Western Australia",
  TAS: "Tasmania",
  ACT: "Australian Capital Territory",
  NT: "Northern Territory",
};

export const CHECK_KINDS = [
  "wwcc_sa",
  "wwcc_nsw",
  "wwc_vic",
  "blue_card_qld",
  "wwc_wa",
  "rwvp_tas",
  "wwvp_act",
  "ochre_card_nt",
  "rrhan_ec_fundamentals",
  "rrhan_ec_masterclass",
  "police_check",
  "first_aid",
] as const;
export type CheckKind = (typeof CHECK_KINDS)[number];

export const CHECK_NAMES: Record<CheckKind, string> = {
  wwcc_sa: "SA Working With Children Check",
  wwcc_nsw: "NSW Working With Children Check",
  wwc_vic: "VIC Working with Children Check",
  blue_card_qld: "QLD blue card",
  wwc_wa: "WA Working with Children Check",
  rwvp_tas: "TAS Registration to Work with Vulnerable People",
  wwvp_act: "ACT Working with Vulnerable People registration",
  ochre_card_nt: "NT Working with Children Clearance (Ochre Card)",
  rrhan_ec_fundamentals: "RRHAN-EC Fundamentals (SA)",
  rrhan_ec_masterclass: "RRHAN-EC Masterclass (SA)",
  police_check: "National police check (optional, valid 5 years from issue)",
  first_aid: "First aid certificate (optional)",
};

// Screening checks carry a card or registration number; training and
// first aid certificates do not need one.
export const NEEDS_REFERENCE: ReadonlySet<CheckKind> = new Set(
  CHECK_KINDS.filter((k) => !k.startsWith("rrhan") && k !== "first_aid"),
);

export const checkName = (kind: string) => CHECK_NAMES[kind as CheckKind] ?? kind;

export const WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
