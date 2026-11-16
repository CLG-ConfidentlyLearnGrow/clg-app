// Summary: the first-time app tours (Carla, 16 Nov 2026). Each dashboard
// has a short, step-by-step tour that opens the first time someone uses it:
// parents, students, tutors, and each admin level (Owner, Operations,
// Support, Finance). Each step says what a part of the app is, why it
// matters, and where to find it. The detailed "how to" steps stay in the
// App guide (src/lib/app-guides), and the tour points people there.
//
// The tours' words live in the files next to this one (parent.ts,
// student.ts, tutor.ts, admin.ts), written in a simple text layout that
// this file turns into steps. A tour uses the same ids as the App guides,
// so the tour for a dashboard is the guide id for that dashboard.
//
// To show a tour to everyone again after a big change to the app, raise
// its version number below. People who saw the old version get the new one
// the next time they open that dashboard.
//
import type { GuideId } from "@/lib/app-guides"; // The guide ids, which the tours share (for type checking only).
import { PARENT_TOUR } from "./parent"; // The parent tour's words.
import { STUDENT_TOUR } from "./student"; // The student tour's words.
import { TUTOR_TOUR } from "./tutor"; // The tutor tour's words.
import { ADMIN_TOURS } from "./admin"; // The four admin tours' words.

// The raw words of one tour, as written in its file.
export type TourSource = { title: string; text: string }; // Its title and its text.

// One step of a tour, ready to show.
export type TourStep = { // A step has:
  title: string; // a short heading,
  text: string[]; // one or more short paragraphs saying what it is,
  why: string | null; // why it matters (or nothing, for the welcome and last steps),
  where: string | null; // where to find it in the app (or nothing).
}; // End of the step shape.

// A whole tour, ready to show.
export type Tour = { id: GuideId; version: number; title: string; steps: TourStep[] }; // Its id, edition, title and steps.

// Each tour's edition. Raise a number to show that tour to everyone again.
export const TOUR_VERSIONS: Record<GuideId, number> = { // id -> edition:
  parent: 1, // parents,
  student: 1, // students,
  tutor: 1, // tutors,
  owner: 1, // the owner,
  operations: 1, // operations admins,
  support: 1, // support admins,
  finance: 1, // finance admins.
}; // End of the editions.

// Each tour's raw words, by id.
const SOURCES: Record<GuideId, TourSource> = { // id -> words:
  parent: PARENT_TOUR, // parents and carers,
  student: STUDENT_TOUR, // students with their own login,
  tutor: TUTOR_TOUR, // tutors,
  owner: ADMIN_TOURS.owner, // the owner,
  operations: ADMIN_TOURS.operations, // operations admins,
  support: ADMIN_TOURS.support, // support admins,
  finance: ADMIN_TOURS.finance, // finance admins.
}; // End of the sources.

// Reads a tour's text into steps. The layout is:
//   "## Heading"   starts a new step,
//   "Why: ..."     says why this part matters,
//   "Where: ..."   says where to find it,
//   anything else is a paragraph. A blank line ends a paragraph.
// Words in **stars** are shown in bold (the names of buttons and menu items).
export function parseTour(id: GuideId, source: TourSource): Tour { // Takes the tour's id and words.
  const steps: TourStep[] = []; // The steps read so far.
  let para: string[] = []; // Lines waiting to become one paragraph.
  const current = () => steps[steps.length - 1]; // The step being read (the last one started).
  const flushPara = () => { // Turns waiting lines into a paragraph, a "why" or a "where":
    if (!para.length || !current()) { para = []; return; } // nothing waiting (or no step yet): nothing to do.
    const text = para.join(" "); // joins the lines with spaces,
    if (text.startsWith("Why: ")) current().why = text.slice(5); // a "why" (without the label),
    else if (text.startsWith("Where: ")) current().where = text.slice(7); // a "where" (without the label),
    else current().text.push(text); // or a plain paragraph,
    para = []; // and nothing is waiting now.
  }; // End of flushPara.
  for (const raw of source.text.split(/\r?\n/)) { // For each line of the words:
    const line = raw.trim(); // without spaces at the ends.
    if (line === "") { flushPara(); continue; } // A blank line: ends a paragraph.
    if (line.startsWith("## ")) { // A new step:
      flushPara(); // ends what came before,
      steps.push({ title: line.slice(3).trim(), text: [], why: null, where: null }); // and starts the step with its heading.
      continue; // On to the next line.
    } // End of a new step.
    if (line.startsWith("Why: ") || line.startsWith("Where: ")) flushPara(); // A label starts its own paragraph.
    para.push(line); // The line waits to join a paragraph.
  } // End of the lines.
  flushPara(); // Ends anything still waiting.
  return { id, version: TOUR_VERSIONS[id], title: source.title, steps }; // Hands back the whole tour.
} // End of parseTour.

// Gives one tour, ready to show.
export function getTour(id: GuideId): Tour { // Takes the tour's id.
  return parseTour(id, SOURCES[id]); // Reads its words into steps.
} // End of getTour.
