// Summary: the fixed facts the child safety concern pages show: each
// state's child protection reporting line, the documents people need, and
// the words for each stage of a concern. Kept in one file so they are easy
// to check and update. Phone numbers were checked on 13 Nov 2026 against the
// SA Department for Child Protection and the Australian Institute of Family
// Studies (AIFS) pages linked below. Check them again every 6 months.

// The date the numbers below were last checked, shown on the page.
export const LINES_CHECKED_ON = "13 November 2026"; // Shown under the list of other states.

// One phone number on a reporting line.
export type Phone = { // A label and a number:
  label: string; // What the number is for, e.g. "24 hours, 7 days".
  number: string; // The number as people read it, e.g. "13 14 78".
}; // End of the shape.

// One state's or territory's child protection reporting line.
export type ReportingLine = { // The details of one line:
  state: string; // The state's short code, matching the database (e.g. "SA").
  stateName: string; // Its full name.
  service: string; // The name of the service that takes reports.
  phones: Phone[]; // Its phone numbers.
  online?: { label: string; url: string }; // An online way to report, if there is one.
  notes?: string; // Anything else people need to know.
  source: string; // Where the details came from.
}; // End of the shape.

// The AIFS page that lists every state's reporting line.
const AIFS = "https://www.aifs.gov.au/resources/resource-sheets/reporting-child-abuse-and-neglect";

// Every state's and territory's reporting line, with South Australia first
// because all of CLG's students live there.
export const REPORTING_LINES: ReportingLine[] = [ // The list:
  { // South Australia:
    state: "SA", // its code,
    stateName: "South Australia", // its name,
    service: "Child Abuse Report Line (CARL), Department for Child Protection", // the service,
    phones: [{ label: "24 hours, 7 days", number: "13 14 78" }], // its number,
    online: { label: "e-CARL (non-urgent reports by mandated notifiers only)", url: "https://ecarl.sa.gov.au/" }, // the online form,
    notes: // what to know:
      "Serious concerns must be phoned, not sent online: a child in danger of serious harm, a current injury, chronic neglect, an injured baby, a child left alone, a threat to kill or seriously harm a child, or sexual abuse where the child will see the person within 24 hours.", // when to phone,
    source: "https://childprotection.sa.gov.au/report-suspected-harm/process-for-mandated-notifiers", // where this came from.
  }, // End of South Australia.
  { // Victoria:
    state: "VIC", // its code,
    stateName: "Victoria", // its name,
    service: "Child Protection (by area); After Hours Child Protection Emergency Service", // the service,
    phones: [ // its numbers:
      { label: "North and West (metro), 8:45am to 5pm weekdays", number: "1300 664 977" }, // north and west metro,
      { label: "South, 8:45am to 5pm weekdays", number: "1300 655 795" }, // south,
      { label: "East, 8:45am to 5pm weekdays", number: "1300 360 391" }, // east,
      { label: "West (rural and regional), 8:45am to 5pm weekdays", number: "1800 075 599" }, // west rural,
      { label: "After hours, weekends and public holidays", number: "13 12 78" }, // after hours.
    ], // End of the numbers.
    source: AIFS, // where this came from.
  }, // End of Victoria.
  { // New South Wales:
    state: "NSW", // its code,
    stateName: "New South Wales", // its name,
    service: "Child Protection Helpline", // the service,
    phones: [{ label: "24 hours, 7 days", number: "13 21 11" }], // its number,
    source: AIFS, // where this came from.
  }, // End of New South Wales.
  { // Queensland:
    state: "QLD", // its code,
    stateName: "Queensland", // its name,
    service: "Child Safety (Regional Intake Services)", // the service,
    phones: [ // its numbers:
      { label: "Business hours", number: "1800 811 810" }, // business hours,
      { label: "After hours and weekends", number: "1800 177 135" }, // after hours.
    ], // End of the numbers.
    source: AIFS, // where this came from.
  }, // End of Queensland.
  { // Western Australia:
    state: "WA", // its code,
    stateName: "Western Australia", // its name,
    service: "Central Intake Team; Crisis Care after hours", // the service,
    phones: [ // its numbers:
      { label: "Central Intake Team", number: "1800 273 889" }, // business hours,
      { label: "Crisis Care, after hours", number: "1800 199 008" }, // after hours.
    ], // End of the numbers.
    source: AIFS, // where this came from.
  }, // End of Western Australia.
  { // Tasmania:
    state: "TAS", // its code,
    stateName: "Tasmania", // its name,
    service: "Child Safety Service", // the service,
    phones: [{ label: "24 hours", number: "1800 000 123" }], // its number,
    source: AIFS, // where this came from.
  }, // End of Tasmania.
  { // The ACT:
    state: "ACT", // its code,
    stateName: "Australian Capital Territory", // its name,
    service: "Child and Youth Protection Services", // the service,
    phones: [ // its numbers:
      { label: "24 hours, 7 days (harm by family or a guardian)", number: "1300 556 729" }, // family harm,
      { label: "ACT Policing (harm by someone outside the family)", number: "131 444" }, // police.
    ], // End of the numbers.
    source: AIFS, // where this came from.
  }, // End of the ACT.
  { // The Northern Territory:
    state: "NT", // its code,
    stateName: "Northern Territory", // its name,
    service: "Child Protection Hotline", // the service,
    phones: [{ label: "24 hours, 7 days", number: "1800 700 250" }], // its number,
    source: AIFS, // where this came from.
  }, // End of the Northern Territory.
]; // End of the list.

// Finds a state's reporting line, or South Australia's if the state is unknown.
export function lineFor(state: string | null | undefined): ReportingLine { // Takes a state code, gives back its line.
  return REPORTING_LINES.find((l) => l.state === state) ?? REPORTING_LINES[0]; // The matching line, or SA (first in the list).
} // End of lineFor.

// Turns a phone number into a link that dials it on a phone, e.g. "tel:131478".
export const telHref = (number: string) => `tel:${number.replace(/\s+/g, "")}`; // Removes the spaces.

// Support lines for children and young people themselves.
export const SUPPORT_LINES: Phone[] = [ // The list:
  { label: "Kids Helpline (ages 5 to 25), 24 hours", number: "1800 55 1800" }, // Kids Helpline,
  { label: "Lifeline, 24 hours", number: "13 11 14" }, // Lifeline.
]; // End of the list.

// The documents people need, which the concern page links to. CLG's own
// policies are drafts in Claude Docs: people need to be given access to
// open them until the approved versions are published in the app.
export const SAFETY_DOCUMENTS: { label: string; url: string; note: string }[] = [ // The list:
  { label: "CLG Child Safe Policy", url: "https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC", note: "How CLG keeps children safe and handles concerns." }, // the child safe policy,
  { label: "CLG Staff Code of Conduct", url: "https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz", note: "What CLG expects of everyone who works with children." }, // the code of conduct,
  { label: "Reporting suspected harm (SA Department for Child Protection)", url: "https://childprotection.sa.gov.au/report-suspected-harm", note: "How to report, and what happens next." }, // the SA reporting page,
  { label: "Process for mandated notifiers (SA)", url: "https://childprotection.sa.gov.au/report-suspected-harm/process-for-mandated-notifiers", note: "When to phone and when to use e-CARL." }, // the mandated notifier process,
  { label: "Children and Young People (Safety) Act 2017 (SA), sections 30 and 31", url: "https://www.legislation.sa.gov.au/lz?path=/c/a/children%20and%20young%20people%20(safety)%20act%202017", note: "The law that says who must report and when." }, // the Act,
]; // End of the list.

// Words for each stage of a concern.
export const STATUS_LABELS: Record<string, string> = { // The words:
  new: "New (not opened yet)", // new,
  in_progress: "Being dealt with", // in progress,
  closed: "Closed", // closed.
}; // End of the words.

// Words for each answer to "Have you reported this to the line?".
export const REPORTED_LABELS: Record<string, string> = { // The words:
  yes: "Yes, already reported", // yes,
  no: "Not yet", // no,
  not_sure: "Not sure if it needs reporting", // not sure.
}; // End of the words.

// Words for each child safety job.
export const CONTACT_ROLE_LABELS: Record<string, string> = { // The words:
  officer: "Child Safety Officer", // the officer,
  deputy: "Deputy Child Safety Officer", // the deputy.
}; // End of the words.
