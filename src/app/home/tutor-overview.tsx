// Summary: the tutor Overview: what needs the tutor now (notes, reviews,
// session times to answer, checks, training), their week at a glance, the
// next sessions, and each child safety check that is missing, expired or
// due to renew. Only the tutor's own sessions, students and checks are
// shown (need-to-know: no family billing or contact details).
//
import { Card, TextLink } from "@/components/ui"; // Shared page parts: a card and a text link.
import type { Role } from "@/lib/auth"; // The role type (for type checking only).
import { getDashboardMenu, sessionsHref } from "@/lib/dashboard-menu"; // The side menu (shared with the page frame), and the Sessions page address.
import { getToDoCounts } from "@/lib/to-do-counts"; // The to-do numbers.
import { attentionLines, comingUp, plural, totalMinutes, weekOfSessions } from "@/lib/home-overview"; // Overview helpers.
import { checkName } from "@/lib/checks"; // A check's name in words.
import { currentTime, lengthLabel, sessionWhen, shortDate } from "@/lib/scheduling"; // The time now, lengths in hours, session times and short dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { AttentionCard, ComingUpCard, Tiles, type Tile } from "./overview-parts"; // The Overview building blocks.

type CheckStatus = { kind: string; expires_on: string | null; status: string }; // One of the tutor's checks: which, when it expires, and its standing.

// The words for each check standing.
const STANDING: Record<string, string> = { expired: "Expired", expiring_soon: "Renew soon", missing: "Missing", current: "Current" }; // standing -> words.

// Shows the tutor Overview.
export async function TutorOverview({ viewerId, roles }: { viewerId: string; roles: Role[] }) { // Takes the tutor's id and all of their roles.
  const supabase = await createClient(); // Connects to the database.
  const [menu, todo, sessions, checksRes, studentsRes] = await Promise.all([ // Reads, at once:
    getDashboardMenu("tutor", roles), // their tutor side menu (already built for the page frame),
    getToDoCounts(roles), // the to-do numbers,
    weekOfSessions(), // the coming week's sessions,
    supabase.from("tutor_check_status").select("kind, expires_on, status").eq("tutor_id", viewerId), // their own checks' standing,
    supabase.from("tutor_assignments").select("student_id").eq("tutor_id", viewerId), // and which students they are matched with.
  ]); // End of the reads.
  const mine = sessions.filter((s) => s.tutor_id === viewerId); // Only their own sessions (an admin who also tutors can see others).
  const next = comingUp(mine, currentTime()); // Their sessions still to come in the next 7 days.
  const minutes = totalMinutes(next); // How long those add up to.
  const checks = (checksRes.data ?? []) as CheckStatus[]; // Their checks.
  const needsAction = checks.filter((c) => c.status !== "current").sort((a, b) => (a.expires_on ?? "").localeCompare(b.expires_on ?? "")); // Checks missing, expired or due within 60 days, soonest first.
  const nextExpiry = checks.filter((c) => c.expires_on).sort((a, b) => a.expires_on!.localeCompare(b.expires_on!))[0]; // The check that expires soonest.
  const studentCount = new Set((studentsRes.data ?? []).map((r) => r.student_id)).size; // How many students they are matched with.

  const tiles: Tile[] = [ // The quick-look tiles:
    { label: "Next 7 days", value: plural(next.length, "session"), note: minutes ? lengthLabel(minutes) : undefined, href: "/dashboard/tutor/calendar" }, // sessions and hours in the coming week,
    { label: "Next session", value: next[0] ? sessionWhen(next[0].starts_at) : "None booked", note: next[0] ? `${next[0].student_name}, ${next[0].subject}` : undefined, href: sessionsHref("tutor") }, // the next session,
    { label: "Your students", value: String(studentCount), href: "/dashboard/tutor?section=students" }, // how many students,
    { label: "Child safety checks", value: needsAction.length ? `${needsAction.length} to fix` : "All current", note: !needsAction.length && nextExpiry?.expires_on ? `Next expiry ${shortDate(nextExpiry.expires_on)}` : undefined, href: "/dashboard/tutor?section=checks", warn: needsAction.length > 0 }, // and their checks.
  ]; // End of the tiles.

  return ( // Shows:
    <>{/* (a group) */}
      <Tiles tiles={tiles} role="tutor" />{/* the quick-look tiles, */}
      <AttentionCard lines={attentionLines("tutor", menu, todo)} />{/* what needs them now, */}
      <ComingUpCard sessions={next} show="student" sessionsHref={sessionsHref("tutor")} empty="No sessions in the coming week." />{/* their next sessions, */}
      {needsAction.length > 0 && ( // If any check needs action:
        <Card title="Child safety checks to sort out" description="You cannot be matched with students in a state until your checks for it are current.">{/* a card, saying why it matters: */}
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {needsAction.map((c) => ( // for each check:
              <li key={c.kind} className="flex flex-wrap items-baseline justify-between gap-2 py-2 first:pt-0 last:pb-0">{/* a row: */}
                <span className="font-medium">{checkName(c.kind)}</span>{/* the check's name, */}
                <span className={c.status === "expiring_soon" ? "text-amber-800" : "font-medium text-red-700"}>{/* its standing (amber when due soon, red when expired or missing): */}
                  {STANDING[c.status] ?? c.status}{c.expires_on ? `, ${shortDate(c.expires_on)}` : ""}{/* the words, and the expiry date (if any). */}
                </span>{/* End of the standing. */}
              </li> // End of the row.
            ))}{/* End of the checks. */}
          </ul>{/* End of the list. */}
          <p className="mt-4 text-sm"><TextLink href="/dashboard/tutor?section=checks">Add or renew a check</TextLink></p>{/* A link to add or renew them. */}
        </Card> // End of the card.
      )}{/* End of the checks card. */}
    </> // End of the group.
  ); // End of what is shown.
} // End of TutorOverview.
