// Summary: the admin Overview: what needs this admin now, and a quick look
// at CLG for their admin level. Front desk (Owner, Operations, Support) see
// today's and this week's sessions and students waiting for a tutor;
// Owner, Operations and Finance see Billing jobs; Owner and Operations see
// tutors whose child safety checks need renewing. Everything links to the
// page where the job is done.
//
import { Card, Empty, TextLink } from "@/components/ui"; // Shared page parts: a card, an empty-state line and a text link.
import { ADMIN_LEVEL_NAMES, FINANCE, FRONT_DESK, FULL_ADMIN, getAdminLevel, type Role } from "@/lib/auth"; // Admin level names and groups, the level reader, and the role type.
import { getDashboardMenu, sessionsHref } from "@/lib/dashboard-menu"; // The side menu (shared with the page frame), and the Sessions page address.
import { getToDoCounts } from "@/lib/to-do-counts"; // The to-do numbers.
import { attentionLines, plural, weekOfSessions } from "@/lib/home-overview"; // The attention lines, a count with the right word, and the coming week's sessions.
import { checkName } from "@/lib/checks"; // A check's name in words.
import { addDays, localDate, localToday, shortDate } from "@/lib/scheduling"; // Date helpers: add days, a moment's Adelaide date, today, and short dates.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { AttentionCard, Tiles, type Tile } from "./overview-parts"; // The Overview building blocks.

type CheckRow = { tutor_id: string; full_name: string; kind: string; expires_on: string | null; status: string }; // One tutor check that needs renewing: tutor, name, check, expiry and status.

// Tutors whose checks have expired or run out within 60 days, soonest
// first (Owner and Operations only; the database lets only admins read
// other tutors' checks). Gives back up to 6, and how many there are.
async function checksToRenew(): Promise<{ rows: CheckRow[]; total: number }> { // No inputs: it is for the signed-in admin.
  const { data, count } = await (await createClient()) // Reads:
    .from("tutor_check_status") // from each tutor's check standing,
    .select("tutor_id, full_name, kind, expires_on, status", { count: "exact" }) // these details, and how many in all,
    .in("status", ["expired", "expiring_soon"]) // only expired or running out soon,
    .order("expires_on") // soonest first,
    .limit(6); // up to 6.
  return { rows: (data ?? []) as CheckRow[], total: count ?? 0 }; // The rows and the total (none if the read failed).
} // End of checksToRenew.

// Shows the admin Overview.
export async function AdminOverview({ roles }: { roles: Role[] }) { // Takes all of the person's roles.
  const [level, menu, todo] = await Promise.all([getAdminLevel(), getDashboardMenu("admin", roles), getToDoCounts(roles)]); // Their admin level, their admin side menu and the to-do numbers, at once.
  const isDesk = level !== null && FRONT_DESK.includes(level); // Whether they help families and bookings (Owner, Operations, Support).
  const isFull = level !== null && FULL_ADMIN.includes(level); // Whether they are a full admin (Owner or Operations).
  const isFinance = level !== null && FINANCE.includes(level); // Whether they can see billing (Owner, Operations, Finance).
  const [sessions, checks] = await Promise.all([ // Reads, at once:
    isDesk ? weekOfSessions() : Promise.resolve([]), // the coming week's sessions (front desk only),
    isFull ? checksToRenew() : Promise.resolve({ rows: [], total: 0 }), // and tutor checks to renew (full admins only).
  ]); // End of the reads.
  const today = localToday(); // Today's date in Adelaide.
  const weekEnd = addDays(today, 7); // The day after the coming 7 days.
  const going = sessions.filter((s) => s.status !== "cancelled"); // Sessions going ahead (or done).
  const todays = going.filter((s) => localDate(s.starts_at) === today); // Sessions today.
  const week = going.filter((s) => { const d = localDate(s.starts_at); return d >= today && d < weekEnd; }); // Sessions in the coming 7 days.
  const cancelledToday = sessions.filter((s) => s.status === "cancelled" && localDate(s.starts_at) === today).length; // Sessions cancelled for today.

  const tiles: Tile[] = []; // The quick-look tiles for their level.
  if (isDesk) { // Front desk:
    tiles.push({ label: "Sessions today", value: String(todays.length), note: cancelledToday ? `${cancelledToday} cancelled` : undefined, href: sessionsHref("admin") }); // today's sessions (with any cancelled),
    tiles.push({ label: "Next 7 days", value: plural(week.length, "session"), href: sessionsHref("admin") }); // the coming week's sessions,
    const waiting = todo.get("admin", "matching") ?? 0; // Students waiting for a tutor.
    tiles.push({ label: "Waiting for a tutor", value: String(waiting), note: waiting ? "Open Matching" : "Nobody waiting", href: "/matching", warn: waiting > 0 }); // students waiting for a tutor.
  } // End of the front desk tiles.
  if (isFinance) { // Billing levels:
    const paused = todo.get("billing", "families") ?? 0; // Families on hold.
    const invoices = todo.get("billing", "invoices") ?? 0; // Invoices to check or approve.
    const hours = todo.get("billing", "pay") ?? 0; // Hours to approve (and new award rates, when due).
    tiles.push({ label: "Families on hold", value: String(paused), href: "/admin/billing", warn: paused > 0 }); // families on hold,
    tiles.push({ label: "Invoices to approve", value: String(invoices), href: "/admin/billing", warn: invoices > 0 }); // invoices to approve,
    if (!isDesk) tiles.push({ label: "Pay to approve", value: String(hours), href: "/admin/billing", warn: hours > 0 }); // and (for Finance, who have room) hours to approve.
  } // End of the billing tiles.
  if (isFull) tiles.push({ label: "Checks to renew", value: String(checks.total), note: checks.total ? "Expired or due within 60 days" : "All tutor checks current", href: "/admin?section=tutors", warn: checks.total > 0 }); // tutor checks to renew (full admins).

  return ( // Shows:
    <>{/* (a group) */}
      <p className="text-sm text-zinc-600">{/* a grey line: */}
        Your admin level: <strong>{level ? ADMIN_LEVEL_NAMES[level] : "not set"}</strong>{/* their admin level, */}
        {" · "}{/* a dot, */}
        <TextLink href="/admin/staff">Staff directory</TextLink>{/* and a link to the staff directory. */}
      </p>{/* End of the line. */}
      <Tiles tiles={tiles.slice(0, 4)} role="admin" />{/* Up to four quick-look tiles. */}
      <AttentionCard lines={attentionLines("admin", menu, todo)} />{/* What needs them now, from their own admin menu. */}
      {isFull && checks.total > 0 && ( // For full admins, when tutor checks need renewing:
        <Card title="Tutor checks to renew" description="Tutors cannot be matched in a state once their checks for it lapse.">{/* a card, saying why it matters: */}
          {checks.rows.length === 0 ? ( // (none could be read)
            <Empty>No checks to renew.</Empty> // a line saying so.
          ) : ( // Otherwise:
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {checks.rows.map((c) => ( // for each check:
                <li key={`${c.tutor_id}-${c.kind}`} className="flex flex-wrap items-baseline justify-between gap-2 py-2 first:pt-0 last:pb-0">{/* a row: */}
                  <span><span className="font-medium">{c.full_name}</span> · {checkName(c.kind)}</span>{/* the tutor and the check, */}
                  <span className={c.status === "expired" ? "font-medium text-red-700" : "text-amber-800"}>{/* the expiry, red when past: */}
                    {c.status === "expired" ? "Expired" : "Expires"} {c.expires_on ? shortDate(c.expires_on) : ""}{/* "Expired" or "Expires", and the date. */}
                  </span>{/* End of the expiry. */}
                </li> // End of the row.
              ))}{/* End of the checks. */}
            </ul> // End of the list.
          )}{/* End of this part. */}
          <p className="mt-4 text-sm"><TextLink href="/admin?section=tutors">Open Tutors and checks</TextLink>{checks.total > checks.rows.length ? ` to see all ${checks.total}.` : "."}</p>{/* A link to see them all. */}
        </Card> // End of the card.
      )}{/* End of the checks card. */}
    </> // End of the group.
  ); // End of what is shown.
} // End of AdminOverview.
