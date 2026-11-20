// Summary: the information behind each dashboard's Overview page (Carla,
// 20 Nov 2026: "a quick look at all the important things for that
// particular person's role"). It turns the side menu's to-do numbers into
// plain "needs your attention" lines, and reads the coming week's sessions
// once for every card on the page. See docs/features/home-overview.md.
//
import "server-only"; // Makes sure this file only ever runs on the server.
import { cache } from "react"; // Remembers a result for the rest of one page load.
import type { Section } from "@/components/section-shell"; // The shape of one side-menu item (for type checking only).
import type { Role } from "@/lib/auth"; // The type for a role (for type checking only).
import type { ToDoCounts } from "@/lib/to-do-counts"; // The to-do numbers' shape (for type checking only).
import { addDays, localToday } from "@/lib/scheduling"; // Date helpers: add days to a date, and today's date in Adelaide.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// One line in "Needs your attention": how many, what it is, why, and where
// to go to deal with it.
export type AttentionLine = { // Each line has:
  id: string; // a short id (the menu item's id, or the extra item's),
  count: number; // how many things are waiting,
  label: string; // the name of the page it is on,
  detail: string; // a plain sentence saying what is waiting,
  href: string; // and the address of the page that deals with it.
  urgent?: boolean; // Whether it is about child safety (shown in red).
}; // End of AttentionLine.

// What each side-menu item's number means, in plain words, so the Overview
// can say it as a sentence. Items not listed get a general sentence.
const MEANING: Record<string, string> = { // menu item id -> what its number counts:
  families: "Children to check, or possible double-ups to sort out.", // Families (admin).
  matching: "Students waiting for a tutor.", // Matching (admin).
  tutors: "Tutor checks waiting for you to confirm.", // Tutors and checks (admin).
  progress: "Term reviews to check, or session notes overdue.", // Progress (admin).
  curriculum: "Curriculum to confirm.", // Curriculum (admin).
  staff: "Staff invitations that ran out before they were used.", // Staff and accounts (admin).
  records: "Records due for deletion, privacy requests or breaches.", // Privacy and records (admin).
  sessions: "Session times to answer, notices to read, or bookings to check.", // Sessions (every dashboard).
  contracts: "Signed contracts that still need the Xero invite.", // Contracts (admin).
  help: "Help chats waiting for a reply from CLG.", // Help chats (admin help desk).
  reports: "New reports to read.", // Reports (owner).
  problems: "New app issues reported.", // App issues (owner and reviewers).
  applications: "New tutor applications.", // Tutor applications (Owner and Operations).
  "check-ins": "Check-in answers to follow up.", // Check-ins (Owner and Operations).
  lateness: "Tutor late starts to review.", // Tutor lateness (Owner and Operations).
  probation: "Staff probation reviews due.", // Staff probation (owner).
  training: "Training modules to do.", // Training (tutors and admins).
  contract: "Your employment contract is waiting for you.", // My contract (staff).
  students: "Session notes, term reviews or family uploads to look at.", // Your students (tutor).
  teaching: "Add what you teach, so CLG can match you with students.", // What you teach (tutor).
  checks: "Child safety checks missing, expired or due to renew.", // Child safety checks (tutor).
  children: "Children's details to finish.", // Your children (parent).
  learning: "Steps that are overdue.", // Your learning (student).
}; // End of MEANING.

// Billing means different things on the admin dashboard and on a family's.
const ADMIN_BILLING = "Families on hold, invoices to approve, or hours to approve."; // Admin Billing.
const FAMILY_BILLING = "Billing to set up: a plan, the payment terms or automatic payment."; // Family Billing (payers only).

// Turns the side menu's numbers into "needs your attention" lines. Because
// it reads the same menu the person sees, it only ever lists pages their
// role and admin level can open (for example Billing only for payers).
// Child safety and help chat replies, shown in the top bar, are added too.
export function attentionLines(role: Role, menu: Section[], todo: ToDoCounts): AttentionLine[] { // Takes the dashboard, its menu and the to-do numbers.
  const lines: AttentionLine[] = []; // The lines being built.
  const concerns = todo.get("safety", "concerns") ?? 0; // New child safety concerns sent to this person.
  const flags = todo.get("safety", "word_flags") ?? 0; // Flagged words to review (Child Safety Officer and Deputy only).
  if (concerns > 0) lines.push({ id: "safety-concerns", count: concerns, label: "Child safety", detail: "New child safety concerns to read.", href: "/safety/concerns", urgent: true }); // New concerns come first, in red.
  if (flags > 0) lines.push({ id: "safety-flags", count: flags, label: "Child safety", detail: "Flagged words in messages to review.", href: "/safety/flags", urgent: true }); // Then flagged words, in red.
  for (const item of menu) { // For each side-menu item:
    if (item.id === "overview" || !item.count || !item.href) continue; // skips the Overview itself, items with nothing waiting, and items without their own page.
    const billing = item.id === "billing" ? (role === "admin" ? ADMIN_BILLING : FAMILY_BILLING) : null; // Billing's meaning depends on the dashboard.
    lines.push({ id: item.id, count: item.count, label: item.label, detail: billing ?? MEANING[item.id] ?? "Something is waiting for you here.", href: item.href }); // Adds its line.
  } // End of the menu items.
  const unread = todo.get("help", "unread") ?? 0; // Help chats with a reply the person has not read.
  if (unread > 0) lines.push({ id: "help-unread", count: unread, label: "Help chat", detail: "Help chats with a new reply for you.", href: "/help" }); // Adds a line for them.
  return lines; // Hands back the lines.
} // End of attentionLines.

// One session as the database lists it (only the details the Overview uses).
export type OverviewSession = { // Each session has:
  id: string; // its id,
  status: string; // its status (scheduled, completed, cancelled, no_show),
  student_id: string; // the student,
  student_name: string; // the student's name,
  tutor_id: string; // the tutor,
  tutor_name: string; // the tutor's name,
  subject: string; // the subject,
  delivery: string; // where it happens (online, library, home, school),
  library_name: string | null; // the library's name (if any),
  starts_at: string; // when it starts,
  ends_at: string; // and when it ends.
}; // End of OverviewSession.

// The sessions the person can see from yesterday to 8 days ahead, read once
// per page however many cards use them. The database decides what each
// person may see; each card then keeps only that dashboard's own sessions
// (a tutor's own, a parent's own children's, a student's own).
export const weekOfSessions = cache(async (): Promise<OverviewSession[]> => { // No inputs: it is for the signed-in person.
  const today = localToday(); // Today's date in Adelaide.
  const { data } = await (await createClient()).rpc("list_sessions", { p_from: addDays(today, -1), p_to: addDays(today, 8) }); // One read for the coming week (a day either side, because the database works in universal time).
  return (data ?? []) as OverviewSession[]; // The sessions (none if the read failed).
}); // End of weekOfSessions.

// The sessions still to come in the next 7 days that are going ahead, from
// a list already kept to one dashboard's own sessions. Soonest first.
export function comingUp(sessions: OverviewSession[], now: number): OverviewSession[] { // Takes the sessions and the time now (in milliseconds).
  const until = now + 7 * 24 * 3600 * 1000; // 7 days from now.
  return sessions // From the sessions:
    .filter((s) => s.status === "scheduled") // keeps the booked ones (not cancelled or already done),
    .filter((s) => { const t = new Date(s.starts_at).getTime(); return t >= now && t < until; }) // that start from now until 7 days ahead,
    .sort((a, b) => a.starts_at.localeCompare(b.starts_at)); // soonest first.
} // End of comingUp.

// How long some sessions add up to, in minutes.
export function totalMinutes(sessions: OverviewSession[]): number { // Takes the sessions.
  return sessions.reduce((t, s) => t + (new Date(s.ends_at).getTime() - new Date(s.starts_at).getTime()) / 60000, 0); // Adds up each one's length.
} // End of totalMinutes.

// "1 session" or "3 sessions": a count with the right word.
export function plural(n: number, word: string, many = `${word}s`): string { // Takes the number, the word, and (optionally) its plural.
  return `${n} ${n === 1 ? word : many}`; // The number and the word that fits.
} // End of plural.
