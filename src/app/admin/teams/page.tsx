// Summary: the admin Teams links page: online sessions with their links, and settings.
//
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty } from "@/components/ui"; // The card and "nothing yet" note.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is an admin.
import { addDays, currentTime, localToday, sessionWhen } from "@/lib/scheduling"; // Date and time helpers.
import { graphConfig } from "@/lib/teams/graph"; // Reads the Microsoft app settings.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { MeetingLinkForm, RunTeamsNowForm, TeamsSettingsForm } from "./forms"; // The forms on this page.

// Teams links (admin only): settings, and the link for each online session.

const SECTIONS = [ // The page's sections:
  { id: "sessions", label: "Online sessions" }, // online sessions,
  { id: "settings", label: "Settings" }, // settings.
] as const; // End of the list (fixed).

// A session as the database gives it.
type Session = {
  id: string; // its id,
  status: string; // its status,
  student_name: string; // the student's name,
  tutor_name: string; // the tutor's name,
  subject: string; // the subject,
  delivery: string; // online or in person,
  starts_at: string; // when it starts,
  meeting_url: string | null; // and its meeting link (if any).
}; // End of the shape.

const STATUS_NOTES: Record<string, string> = { // Words for each link status:
  making: "Being made", // being made,
  made: "Teams link made", // made,
  failed: "Couldn't make it yet", // failed,
  removing: "Being deleted", // being deleted,
  removed: "Deleted", // deleted.
}; // End of the list.

// Shows the Teams links page.
export default async function AdminTeamsPage({ searchParams }: PageProps<"/admin/teams">) {
  const viewer = await requireAdmin(); // Makes sure the person is an admin, and gets who they are.
  const params = await searchParams; // Reads the address settings.
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "sessions"; // The section asked for (sessions by default).
  const supabase = await createClient(); // Connects to the database.

  const [settingsRes, sessionsRes, meetingsRes] = await Promise.all([ // Reads three things at once:
    supabase.from("teams_settings").select("enabled, organiser_email, days_ahead, last_run_at").maybeSingle(), // the Teams settings,
    supabase.rpc("list_sessions", { p_from: localToday(), p_to: addDays(localToday(), 28) }), // the sessions in the next 4 weeks,
    supabase.from("teams_meetings").select("session_id, status, last_error, attempts"), // and each session's meeting status.
  ]); // End of the reads.
  const settings = settingsRes.data; // The settings.
  const now = currentTime(); // The time now.
  const sessions = ((sessionsRes.data ?? []) as Session[]).filter( // The sessions to show:
    (s) => s.delivery === "online" && s.status === "scheduled" && new Date(s.starts_at).getTime() > now - 3 * 3600_000, // online, booked, and not ended more than 3 hours ago.
  ); // (end of the filter)
  const meetingOf = new Map((meetingsRes.data ?? []).map((m) => [m.session_id, m])); // Each session's meeting status, by session.
  const failures = sessions.filter((s) => meetingOf.get(s.id)?.status === "failed"); // Sessions whose link failed.
  const connected = Boolean(graphConfig()); // True if the Microsoft app details are set.

  return ( // Shows:
    <>{/* (a group:) */}
      {/* The dashboard tabs and admin menu, with this page's own sections shown under its tab: */}
      <DashboardFrame // the dashboard frame:
        role="admin" // the admin dashboard,
        roles={viewer.roles} // the person's roles (for the tabs and numbers),
        current="teams" // this page's tab open,
        sub={section} // on the open section,
        items={SECTIONS.map((s) => ({ ...s, href: `/admin/teams?section=${s.id}`, count: s.id === "sessions" ? failures.length || undefined : undefined }))} // with this page's sections (and their numbers) under the tab.
      >{/* (end of the frame's settings) */}
        {(!connected || !settings?.enabled) && ( // If not switched on:
          <Card title="Not switched on yet">{/* a card: */}
            <ul className="list-disc space-y-1 pl-5 text-sm">{/* a bulleted list: */}
              {!connected && ( // if the app details are missing:
                <li>{/* a list item: */}
                  The Microsoft app details aren&apos;t in Vercel yet: MS_TENANT_ID, MS_CLIENT_ID and MS_CLIENT_SECRET.{/* naming the missing details. */}
                </li> // (end of the item)
              )}{/* End of that point. */}
              {!settings?.enabled && <li>Teams links are switched off in Settings.</li>}{/* If links are switched off, says so. */}
            </ul>{/* End of the list. */}
            <p className="mt-3 text-sm text-zinc-600">Until then, you can paste a link for any session below.</p>{/* A note that links can still be pasted. */}
          </Card> // End of the card.
        )}{/* End of that part. */}

        {section === "sessions" && ( // The sessions section:
          <>{/* (a group:) */}
            {connected && settings?.enabled && ( // if switched on:
              <Card title="Make links now">{/* a card: */}
                <RunTeamsNowForm />{/* the "make links now" form, */}
                {settings.last_run_at && ( // when it last ran:
                  <p className="mt-3 text-xs text-zinc-500">Last run {sessionWhen(settings.last_run_at)}.</p> // (the line)
                )}{/* (end of that line) */}
              </Card> // End of the card.
            )}{/* End of that part. */}
            <Card // A card:
              title="Online sessions, next 4 weeks" // titled "Online sessions, next 4 weeks",
              description={`Automatic links are made ${settings?.days_ahead ?? 7} days ahead and deleted when a session is cancelled or an hour after it ends.`} // with how links are made and deleted.
            >{/* (end of the card's settings) */}
              {sessions.length === 0 ? ( // If there are none:
                <Empty>No online sessions booked.</Empty> // says so.
              ) : ( // Otherwise:
                <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                  {sessions.map((s) => { // for each session:
                    const m = meetingOf.get(s.id); // its meeting status,
                    const auto = m?.status === "made"; // true if the link was made automatically.
                    return ( // Shows:
                      <li key={s.id} className="py-3 first:pt-0">{/* a list item: */}
                        <details>{/* a section that opens when clicked: */}
                          <summary className="cursor-pointer list-none">{/* its clickable heading: */}
                            <span className="font-medium">{sessionWhen(s.starts_at)}</span>{/* when it is, */}
                            <span className="text-zinc-600">{/* grey details: */}
                              {" "}{/* (a space) */}
                              · {s.student_name} with {s.tutor_name} · {s.subject} ·{" "}{/* student, tutor and subject, */}
                            </span>{/* (end of the details) */}
                            {s.meeting_url ? ( // if there's a link:
                              <span className="text-teal-800">{auto ? "Teams link made" : "Link pasted by hand"}</span> // whether it was made or pasted,
                            ) : m ? ( // if there's a status:
                              <span className={m.status === "failed" ? "text-red-700" : "text-zinc-600"}>{/* the status, in red if it failed: */}
                                {STATUS_NOTES[m.status] ?? m.status}{/* (the words) */}
                              </span> // (end of the status)
                            ) : ( // otherwise:
                              <span className="text-zinc-500">No link yet</span> // "No link yet".
                            )}{/* End of the choice. */}
                          </summary>{/* End of the heading. */}
                          <div className="mt-3 space-y-3">{/* A block: */}
                            {m?.status === "failed" && m.last_error && ( // if it failed:
                              <p className="text-sm text-red-700">{/* a red line: */}
                                {m.last_error} (tried {m.attempts} time{m.attempts === 1 ? "" : "s"}{/* the error and how many tries, */}
                                {m.attempts >= 5 ? "; stopped trying, so paste a link instead" : ""}){/* and whether it stopped trying. */}
                              </p> // End of the line.
                            )}{/* End of the failure. */}
                            {s.meeting_url && ( // If there's a link:
                              <p className="text-sm break-all">{/* a line: */}
                                <a href={s.meeting_url} className="text-teal-800 underline" target="_blank" rel="noreferrer">{/* a link: */}
                                  {s.meeting_url}{/* (the address) */}
                                </a>{/* (end of the link) */}
                              </p> // End of the line.
                            )}{/* End of the link part. */}
                            <MeetingLinkForm sessionId={s.id} url={s.meeting_url} />{/* The form to paste a link. */}
                          </div>{/* End of the block. */}
                        </details>{/* End of the section. */}
                      </li> // End of the list item.
                    ); // End of what's shown for this session.
                  })}{/* End of the sessions loop. */}
                </ul> // End of the list.
              )}{/* End of the choice. */}
            </Card>{/* End of the card. */}
          </> // (end of the group)
        )}{/* End of the sessions section. */}

        {section === "settings" && ( // The settings section:
          <Card // a card:
            title="Teams settings" // titled "Teams settings",
            description="Every meeting is owned by one CLG Microsoft 365 account. Tutors and families join from the link in the app; nobody needs a CLG Microsoft account." // with how meetings are owned.
          >{/* (end of the card's settings) */}
            <TeamsSettingsForm // The settings form:
              enabled={settings?.enabled ?? false} // on or off,
              organiser={settings?.organiser_email ?? ""} // the meetings account,
              daysAhead={settings?.days_ahead ?? 7} // and days ahead.
            />{/* (end of the form) */}
          </Card> // End of the card.
        )}{/* End of the settings section. */}
      </DashboardFrame>{/* End of the dashboard frame. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of AdminTeamsPage.
