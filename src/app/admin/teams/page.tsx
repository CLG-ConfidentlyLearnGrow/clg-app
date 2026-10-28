import { RoleTabs } from "@/components/role-tabs";
import { SectionShell } from "@/components/section-shell";
import { Card, Empty, TextLink } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { addDays, currentTime, localToday, sessionWhen } from "@/lib/scheduling";
import { graphConfig } from "@/lib/teams/graph";
import { createClient } from "@/lib/supabase/server";
import { MeetingLinkForm, RunTeamsNowForm, TeamsSettingsForm } from "./forms";

// Teams links (admin only): settings, and the link for each online session.

const SECTIONS = [
  { id: "sessions", label: "Online sessions" },
  { id: "settings", label: "Settings" },
] as const;

type Session = {
  id: string;
  status: string;
  student_name: string;
  tutor_name: string;
  subject: string;
  delivery: string;
  starts_at: string;
  meeting_url: string | null;
};

const STATUS_NOTES: Record<string, string> = {
  making: "Being made",
  made: "Teams link made",
  failed: "Couldn't make it yet",
  removing: "Being deleted",
  removed: "Deleted",
};

export default async function AdminTeamsPage({ searchParams }: PageProps<"/admin/teams">) {
  const viewer = await requireAdmin();
  const params = await searchParams;
  const section = SECTIONS.find((s) => s.id === params.section)?.id ?? "sessions";
  const supabase = await createClient();

  const [settingsRes, sessionsRes, meetingsRes] = await Promise.all([
    supabase.from("teams_settings").select("enabled, organiser_email, days_ahead, last_run_at").maybeSingle(),
    supabase.rpc("list_sessions", { p_from: localToday(), p_to: addDays(localToday(), 28) }),
    supabase.from("teams_meetings").select("session_id, status, last_error, attempts"),
  ]);
  const settings = settingsRes.data;
  const now = currentTime();
  const sessions = ((sessionsRes.data ?? []) as Session[]).filter(
    (s) => s.delivery === "online" && s.status === "scheduled" && new Date(s.starts_at).getTime() > now - 3 * 3600_000,
  );
  const meetingOf = new Map((meetingsRes.data ?? []).map((m) => [m.session_id, m]));
  const failures = sessions.filter((s) => meetingOf.get(s.id)?.status === "failed");
  const connected = Boolean(graphConfig());

  return (
    <>
      <RoleTabs roles={viewer.roles} active="admin" />
      <SectionShell
        basePath="/admin/teams"
        label="Teams links"
        section={section}
        sections={SECTIONS.map((s) => ({ ...s, count: s.id === "sessions" ? failures.length || undefined : undefined }))}
      >
        <p className="text-sm">
          <TextLink href="/admin">Back to admin</TextLink>
        </p>

        {(!connected || !settings?.enabled) && (
          <Card title="Not switched on yet">
            <ul className="list-disc space-y-1 pl-5 text-sm">
              {!connected && (
                <li>
                  The Microsoft app details aren&apos;t in Vercel yet: MS_TENANT_ID, MS_CLIENT_ID and MS_CLIENT_SECRET.
                </li>
              )}
              {!settings?.enabled && <li>Teams links are switched off in Settings.</li>}
            </ul>
            <p className="mt-3 text-sm text-zinc-600">Until then, you can paste a link for any session below.</p>
          </Card>
        )}

        {section === "sessions" && (
          <>
            {connected && settings?.enabled && (
              <Card title="Make links now">
                <RunTeamsNowForm />
                {settings.last_run_at && (
                  <p className="mt-3 text-xs text-zinc-500">Last run {sessionWhen(settings.last_run_at)}.</p>
                )}
              </Card>
            )}
            <Card
              title="Online sessions, next 4 weeks"
              description={`Automatic links are made ${settings?.days_ahead ?? 7} days ahead and deleted when a session is cancelled or an hour after it ends.`}
            >
              {sessions.length === 0 ? (
                <Empty>No online sessions booked.</Empty>
              ) : (
                <ul className="divide-y divide-zinc-100 text-sm">
                  {sessions.map((s) => {
                    const m = meetingOf.get(s.id);
                    const auto = m?.status === "made";
                    return (
                      <li key={s.id} className="py-3 first:pt-0">
                        <details>
                          <summary className="cursor-pointer list-none">
                            <span className="font-medium">{sessionWhen(s.starts_at)}</span>
                            <span className="text-zinc-600">
                              {" "}
                              · {s.student_name} with {s.tutor_name} · {s.subject} ·{" "}
                            </span>
                            {s.meeting_url ? (
                              <span className="text-teal-800">{auto ? "Teams link made" : "Link pasted by hand"}</span>
                            ) : m ? (
                              <span className={m.status === "failed" ? "text-red-700" : "text-zinc-600"}>
                                {STATUS_NOTES[m.status] ?? m.status}
                              </span>
                            ) : (
                              <span className="text-zinc-500">No link yet</span>
                            )}
                          </summary>
                          <div className="mt-3 space-y-3">
                            {m?.status === "failed" && m.last_error && (
                              <p className="text-sm text-red-700">
                                {m.last_error} (tried {m.attempts} time{m.attempts === 1 ? "" : "s"}
                                {m.attempts >= 5 ? "; stopped trying, so paste a link instead" : ""})
                              </p>
                            )}
                            {s.meeting_url && (
                              <p className="text-sm break-all">
                                <a href={s.meeting_url} className="text-teal-800 underline" target="_blank" rel="noreferrer">
                                  {s.meeting_url}
                                </a>
                              </p>
                            )}
                            <MeetingLinkForm sessionId={s.id} url={s.meeting_url} />
                          </div>
                        </details>
                      </li>
                    );
                  })}
                </ul>
              )}
            </Card>
          </>
        )}

        {section === "settings" && (
          <Card
            title="Teams settings"
            description="Every meeting is owned by one CLG Microsoft 365 account. Tutors and families join from the link in the app; nobody needs a CLG Microsoft account."
          >
            <TeamsSettingsForm
              enabled={settings?.enabled ?? false}
              organiser={settings?.organiser_email ?? ""}
              daysAhead={settings?.days_ahead ?? 7}
            />
          </Card>
        )}
      </SectionShell>
    </>
  );
}
