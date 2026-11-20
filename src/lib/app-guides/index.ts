// Summary: the app guides ("how to use the app" handbooks), one for each
// kind of account: parents, students, tutors, and each admin level (Owner,
// Operations, Support, Finance). Carla asked for these on 16 Nov 2026: each
// account sees only the guide(s) for its own roles and admin level.
//
// The guides' words live in the files next to this one (parent.ts,
// student.ts, tutor.ts, admin.ts), written in a simple text layout that
// this file turns into parts, tasks and steps for the App guide page. The
// words describe the app, so they change in the same pull request as the
// feature they describe. They hold no personal information, so who sees
// which guide is decided here rather than by a database rule.
//
import type { AdminLevel, Role } from "@/lib/auth"; // The admin level and role types (for type checking only).
import { PARENT_GUIDE } from "./parent"; // The parent guide's words.
import { STUDENT_GUIDE } from "./student"; // The student guide's words.
import { TUTOR_GUIDE } from "./tutor"; // The tutor guide's words.
import { ADMIN_GUIDES } from "./admin"; // The four admin guides' words.

// Every guide's id: one per profile, and one per admin level.
export const GUIDE_IDS = ["parent", "student", "tutor", "owner", "operations", "support", "finance"] as const; // The fixed list of ids.
export type GuideId = (typeof GUIDE_IDS)[number]; // One of those ids (for type checking).

// One piece of a task or a part: a paragraph, a tip, numbered steps, or bullet points.
export type GuideBlock = // Each block is one of:
  | { kind: "text"; text: string } // a plain paragraph,
  | { kind: "tip"; text: string } // a tip, shown in a soft box,
  | { kind: "steps"; items: string[] } // numbered steps, done in order,
  | { kind: "bullets"; items: string[] }; // or bullet points.

// One "how to" task inside a part, such as "Cancel a session".
export type GuideTask = { title: string; blocks: GuideBlock[] }; // Its heading and its steps.

// One part of a guide, such as "Sessions": a short intro, then its tasks.
export type GuidePart = { id: string; heading: string; blocks: GuideBlock[]; tasks: GuideTask[] }; // Its link id, heading, intro and tasks.

// A whole guide, ready to show.
export type Guide = { id: GuideId; title: string; who: string; parts: GuidePart[] }; // Its id, title, who it's for, and its parts.

// The raw words of one guide, as written in its file.
export type GuideSource = { title: string; who: string; text: string }; // Its title, who it's for, and its text.

// Each guide's raw words, by id.
const SOURCES: Record<GuideId, GuideSource> = { // id -> words:
  parent: PARENT_GUIDE, // parents and carers,
  student: STUDENT_GUIDE, // students with their own login,
  tutor: TUTOR_GUIDE, // tutors,
  owner: ADMIN_GUIDES.owner, // the owner,
  operations: ADMIN_GUIDES.operations, // operations admins,
  support: ADMIN_GUIDES.support, // support admins,
  finance: ADMIN_GUIDES.finance, // finance admins.
}; // End of the sources.

// Turns a heading into a short id for a link on the page, e.g. "Your sessions" -> "your-sessions".
function slug(heading: string): string { // Takes the heading.
  return heading.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""); // Lowercase, words joined by dashes, no dashes at the ends.
} // End of slug.

// Reads a guide's text into parts, tasks and blocks. The layout is:
//   "## Heading"  starts a new part (listed in the guide's contents),
//   "### Task"    starts a new task in that part (a fold-out on the page),
//   "1. Step"     a numbered step (any number, followed by a full stop),
//   "- Point"     a bullet point,
//   "Tip: ..."    a tip,
//   anything else is a paragraph. A blank line ends a paragraph or list.
export function parseGuide(id: GuideId, source: GuideSource): Guide { // Takes the guide's id and words.
  const parts: GuidePart[] = []; // The parts read so far.
  let blocks: GuideBlock[] = []; // Where new blocks go: the current part's intro or the current task.
  let para: string[] = []; // Lines waiting to become one paragraph.
  const flushPara = () => { // Turns waiting lines into a paragraph or tip:
    if (!para.length) return; // nothing waiting: nothing to do.
    const text = para.join(" "); // joins the lines with spaces,
    if (text.startsWith("Tip: ")) blocks.push({ kind: "tip", text: text.slice(5) }); // a tip (without the word "Tip:"),
    else blocks.push({ kind: "text", text }); // or a plain paragraph,
    para = []; // and nothing is waiting now.
  }; // End of flushPara.
  const addItem = (kind: "steps" | "bullets", item: string) => { // Adds a step or bullet point:
    flushPara(); // ends any paragraph before it,
    const last = blocks[blocks.length - 1]; // looks at the block before,
    if (last && last.kind === kind) last.items.push(item); // the same kind of list: adds to it,
    else blocks.push({ kind, items: [item] }); // otherwise starts a new list.
  }; // End of addItem.
  for (const raw of source.text.split(/\r?\n/)) { // For each line of the words:
    const line = raw.trim(); // without spaces at the ends.
    if (line === "") { flushPara(); continue; } // A blank line: ends a paragraph.
    if (line.startsWith("## ")) { // A new part:
      flushPara(); // ends what came before,
      const heading = line.slice(3).trim(); // its heading,
      parts.push({ id: slug(heading), heading, blocks: [], tasks: [] }); // adds the part,
      blocks = parts[parts.length - 1].blocks; // and new blocks go into its intro.
      continue; // On to the next line.
    } // End of a new part.
    if (line.startsWith("### ")) { // A new task:
      flushPara(); // ends what came before,
      if (!parts.length) parts.push({ id: "start", heading: "Getting started", blocks: [], tasks: [] }); // a task before any part gets a "Getting started" part,
      const task: GuideTask = { title: line.slice(4).trim(), blocks: [] }; // the task with its heading,
      parts[parts.length - 1].tasks.push(task); // added to the current part,
      blocks = task.blocks; // and new blocks go into the task.
      continue; // On to the next line.
    } // End of a new task.
    const step = line.match(/^\d+\.\s+(.*)$/); // Checks for a numbered step ("1. ...").
    if (step) { addItem("steps", step[1]); continue; } // A step: added to the steps.
    if (line.startsWith("- ")) { addItem("bullets", line.slice(2)); continue; } // A bullet point: added to the bullets.
    if (para.length === 0 && blocks.length && (blocks[blocks.length - 1].kind === "steps" || blocks[blocks.length - 1].kind === "bullets") && raw.startsWith("   ")) { // An indented line straight after a list item:
      const list = blocks[blocks.length - 1] as { items: string[] }; // the list,
      list.items[list.items.length - 1] += ` ${line}`; // carries on its last item.
      continue; // On to the next line.
    } // End of the carried-on line.
    para.push(line); // Anything else: waits to join a paragraph.
  } // End of the lines.
  flushPara(); // Ends anything still waiting.
  return { id, title: source.title, who: source.who, parts }; // Hands back the whole guide.
} // End of parseGuide.

// Gives one guide, ready to show.
export function getGuide(id: GuideId): Guide { // Takes the guide's id.
  return parseGuide(id, SOURCES[id]); // Reads its words into parts and tasks.
} // End of getGuide.

// The guide that belongs to a dashboard: the role's own guide, or for the
// admin dashboard, the guide for the person's admin level.
export function ownGuide(role: Role, level: AdminLevel | null): GuideId | null { // Takes the dashboard and admin level.
  if (role === "admin") return level; // Admin dashboard: the level's guide (none without a level).
  return role; // Otherwise: the parent, student or tutor guide.
} // End of ownGuide.

// Every guide this person may open, in the order to list them. Everyone
// gets the guide for each of their own roles (and their admin level).
// Admins who help families and tutors (Owner, Operations, Support) can also
// open the parent, student and tutor guides, so they can talk people
// through the app. Operations can open the Support guide (to train office
// help), and the owner can open every guide.
export function guidesFor(roles: Role[], level: AdminLevel | null): GuideId[] { // Takes the person's roles and admin level.
  const ids = new Set<GuideId>(); // The guides they may open (no repeats).
  if (roles.includes("admin") && level) { // An admin with a level:
    ids.add(level); // their own level's guide,
    if (level === "owner") GUIDE_IDS.forEach((g) => ids.add(g)); // the owner: every guide,
    if (level === "operations") ids.add("support"); // operations: the Support guide too,
    if (level === "owner" || level === "operations" || level === "support") { // admins who help families and tutors:
      ids.add("parent"); // the parent guide,
      ids.add("student"); // the student guide,
      ids.add("tutor"); // and the tutor guide.
    } // End of the helpers' extras.
  } // End of the admin guides.
  if (roles.includes("tutor")) ids.add("tutor"); // Tutors: the tutor guide.
  if (roles.includes("parent")) ids.add("parent"); // Parents: the parent guide.
  if (roles.includes("student")) ids.add("student"); // Students: the student guide.
  return GUIDE_IDS.filter((g) => ids.has(g)); // Hands them back in the fixed order.
} // End of guidesFor.

// Each guide's short name, for the list of other guides.
export const GUIDE_NAMES: Record<GuideId, string> = { // id -> name:
  parent: "Family", // the Family profile (parents and carers),
  student: "Students", // students,
  tutor: "Tutors", // tutors,
  owner: "Admin: Owner", // the owner,
  operations: "Admin: Operations", // operations,
  support: "Admin: Support", // support,
  finance: "Admin: Finance", // finance.
}; // End of the names.

// Whether some text is one of the guide ids (for reading the page address safely).
export function isGuideId(value: unknown): value is GuideId { // Takes anything.
  return typeof value === "string" && (GUIDE_IDS as readonly string[]).includes(value); // True only for a known id.
} // End of isGuideId.
