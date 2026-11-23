// Summary: "Show me how" help for the page someone is on (Carla, 18 Nov
// 2026: "Need to be able to get up the how to use the section if a person
// is needing a refresher"). Every dashboard page has a "Show me how" button
// by its heading. It opens the part of that dashboard's App guide that
// covers the page, so people can get a quick refresher without leaving
// what they are doing or searching the whole guide.
//
// The list below says which App guide parts (and, where a part is broad,
// which of its tasks) belong to each side-menu item. The guide's words stay
// in parent.ts, student.ts, tutor.ts and admin.ts, so the refresher always
// matches the App guide. A guide part that a guide does not have is simply
// skipped, so one list serves every dashboard and admin level.
//
import type { Guide, GuideId, GuidePart } from "./index"; // The guide shapes and ids (for type checking only).
import { getGuide } from "./index"; // Reads a guide into parts and tasks.

// One piece of help for a page: a guide part, and optionally only the tasks
// in it whose headings contain one of the given words (lower case).
type HelpRef = { part: string; tasks?: string[] }; // The part's link id, and the optional task words.

// Which guide parts belong to each side-menu item (by the item's id, as in
// src/lib/dashboard-menu.ts). Parts are listed in the order they show.
const PAGE_HELP: Record<string, HelpRef[]> = { // menu item id -> help:
  // The Overview every dashboard opens on (Carla, 20 Nov 2026).
  overview: [{ part: "getting-around", tasks: ["overview"] }, { part: "getting-started", tasks: ["overview"] }], // Overview: the Overview task in the guide's first part.

  // Admin dashboard sections.
  families: [{ part: "families" }], // Families: the whole Families part.
  matching: [{ part: "matching" }], // Matching: the whole Matching part.
  tutors: [{ part: "tutors-and-checks" }], // Tutors and checks: the whole part.
  progress: [{ part: "progress" }], // Progress (admin): the whole part.
  curriculum: [{ part: "curriculum" }], // Curriculum: the whole part.
  staff: [ // Staff and accounts:
    { part: "staff-leaving-and-records", tasks: ["add staff", "unlock"] }, // adding staff and unlocking accounts,
    { part: "owner-only", tasks: ["admin's level", "invite an admin"] }, // the owner's admin tasks,
    { part: "emergency-owner-access" }, // and asking for emergency owner access (Operations).
  ], // End of Staff and accounts.
  leaving: [ // Leaving:
    { part: "staff-leaving-and-records", tasks: ["leaving"] }, // recording someone leaving,
    { part: "owner-only", tasks: ["leaving"] }, // and the owner's part of staff leaving.
  ], // End of Leaving.
  records: [ // Privacy and records:
    { part: "staff-leaving-and-records", tasks: ["privacy", "records"] }, // privacy requests and records due for deletion,
    { part: "owner-only", tasks: ["records"] }, // and the owner's records tasks.
  ], // End of Privacy and records.
  contracts: [ // Contracts (admin):
    { part: "employment-contracts" }, // sending and following contracts,
    { part: "owner-only", tasks: ["contract templates"] }, // and the owner's contract templates.
  ], // End of Contracts.
  reports: [ // Reports (owner and Operations):
    { part: "owner-only", tasks: ["reports", "goals"] }, // the owner's reports and setting goals,
    { part: "reports-and-goals" }, // Operations admins' reports and goals (Carla, 20 Nov 2026),
    { part: "matching", tasks: ["reports"] }, // and the matching reports.
  ], // End of Reports.
  problems: [{ part: "owner-only", tasks: ["app issues"] }], // App issues: reviewing problem reports.
  applications: [{ part: "tutor-applications" }], // Tutor applications: the whole part.
  "check-ins": [{ part: "other-admin-tools", tasks: ["check-ins"] }], // Check-ins after a new match.
  lateness: [{ part: "other-admin-tools", tasks: ["lateness"] }], // Tutor lateness.
  probation: [{ part: "other-admin-tools", tasks: ["probation"] }], // Staff probation (owner).
  feedback: [{ part: "other-admin-tools", tasks: ["feedback"] }], // App feedback.
  "whats-new": [{ part: "other-admin-tools", tasks: ["what is new"] }], // Writing "What is new" pop-ups.
  teams: [{ part: "other-admin-tools", tasks: ["teams"] }], // Teams links.
  "travel-map": [{ part: "matching", tasks: ["travel map"] }], // The travel map.
  "training-admin": [{ part: "other-admin-tools", tasks: ["training setup"] }], // Training setup.

  // Shared by several dashboards (each guide only has some of these parts).
  sessions: [{ part: "sessions" }, { part: "sessions-and-bookings" }], // Sessions: the family, student or tutor Sessions part, or the admin one.
  billing: [ // Billing:
    { part: "billing" }, // the admin Billing part,
    { part: "staff-pay" }, // and Staff pay (owner and Finance),
    { part: "billing-and-payments" }, // or the parent's billing part,
    { part: "billing-if-you-pay-for-yourself" }, // or the student's.
  ], // End of Billing.
  help: [{ part: "help", tasks: ["help chats", "start a chat", "keep a chat"] }], // Help chats (admin): answering and keeping chats.
  calendar: [{ part: "sessions", tasks: ["your week"] }], // Weekly calendar: seeing the week and adding it to a phone calendar.
  materials: [ // Materials:
    { part: "other-admin-tools", tasks: ["materials"] }, // the admin materials library,
    { part: "students-and-progress", tasks: ["materials"] }, // or finding materials as a tutor.
  ], // End of Materials.
  training: [ // Your own training:
    { part: "your-own-training-handbook-and-pay", tasks: ["training"] }, // for admins,
    { part: "training-handbook-and-pay", tasks: ["training"] }, // or for tutors.
  ], // End of Training.
  handbook: [ // Handbooks:
    { part: "your-own-training-handbook-and-pay", tasks: ["handbook"] }, // for admins,
    { part: "training-handbook-and-pay", tasks: ["handbook"] }, // or for tutors.
  ], // End of Handbooks.
  contract: [ // My contract:
    { part: "your-own-training-handbook-and-pay", tasks: ["contract"] }, // for admins,
    { part: "getting-started", tasks: ["contract"] }, // or for tutors.
  ], // End of My contract.
  decisions: [ // Decision steps (Carla, 22 Nov 2026):
    { part: "your-own-training-handbook-and-pay", tasks: ["decision steps"] }, // for admins,
    { part: "training-handbook-and-pay", tasks: ["decision steps"] }, // or for tutors.
  ], // End of Decision steps.
  pay: [ // My Pay:
    { part: "your-own-training-handbook-and-pay", tasks: ["office hours"] }, // logging office hours (admins),
    { part: "training-handbook-and-pay", tasks: ["pay"] }, // or checking pay and logging extra hours (tutors).
  ], // End of My Pay.

  // Tutor dashboard sections.
  students: [{ part: "students-and-progress" }], // Your students: the whole part.
  teaching: [{ part: "your-profile-checks-subjects-and-hours", tasks: ["what you teach", "where you teach"] }], // What you teach: subjects and places.
  checks: [{ part: "your-profile-checks-subjects-and-hours", tasks: ["check"] }], // Child safety checks: adding or renewing a check.
  hours: [{ part: "your-profile-checks-subjects-and-hours", tasks: ["hours", "availability"] }], // Hours and availability.

  // Parent dashboard sections.
  children: [{ part: "your-children" }], // Your children: the whole part.
  add: [{ part: "your-children", tasks: ["add a child", "after you add"] }], // Add a child: adding one, and what happens next.

  // Student dashboard section.
  learning: [{ part: "your-learning" }], // Your learning: the whole part.
}; // End of the list.

// The parts that welcome people to a guide, used when a page has no help of
// its own (so the button always shows something useful).
const FALLBACK: HelpRef[] = [{ part: "getting-around" }, { part: "getting-started" }]; // The parent and student, or tutor and admin, first part.

// Picks the guide parts (with only the matching tasks, where a part is
// broad) that help with one side-menu item, from one guide. A part the guide
// does not have is skipped. If nothing matches, the guide's welcome part is
// used instead.
export function helpParts(guide: Guide, menuItem: string): GuidePart[] { // Takes the guide and the open menu item's id.
  const pick = (refs: HelpRef[]): GuidePart[] => // Turns a list of help into guide parts:
    refs.flatMap((ref) => { // for each piece of help:
      const part = guide.parts.find((p) => p.id === ref.part); // finds the part in this guide,
      if (!part) return []; // not in this guide: skipped.
      if (!ref.tasks) return [part]; // no task words: the whole part.
      const tasks = part.tasks.filter((t) => ref.tasks!.some((w) => t.title.toLowerCase().includes(w))); // only the tasks whose heading has one of the words,
      return tasks.length ? [{ ...part, blocks: [], tasks }] : []; // shown without the part's intro (which is about the whole part), or skipped if none match.
    }); // End of the pieces.
  const found = pick(PAGE_HELP[menuItem] ?? []); // The help for this page.
  return found.length ? found : pick(FALLBACK).slice(0, 1); // That help, or the guide's welcome part.
} // End of helpParts.

// Gives the refresher for one page of one dashboard: the guide's id and
// title, and the parts to show.
export function pageHelp(id: GuideId, menuItem: string): { id: GuideId; title: string; parts: GuidePart[] } { // Takes the guide id and the open menu item's id.
  const guide = getGuide(id); // The dashboard's guide.
  return { id, title: guide.title, parts: helpParts(guide, menuItem) }; // Its id, title and the parts for this page.
} // End of pageHelp.
