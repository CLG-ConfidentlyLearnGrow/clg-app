import "server-only";

// Talks to Microsoft Graph, the service behind Microsoft 365, to make and
// delete Teams meetings. Uses an app registered in CLG's Microsoft 365
// (Microsoft Entra) with the "OnlineMeetings.ReadWrite.All" permission,
// limited by an application access policy to the one organiser account.

export type GraphConfig = { tenantId: string; clientId: string; clientSecret: string };

// The three Vercel secret settings. Missing ones mean Teams links are not
// set up yet; the rest of the app works as normal.
export function graphConfig(): GraphConfig | null {
  const tenantId = process.env.MS_TENANT_ID;
  const clientId = process.env.MS_CLIENT_ID;
  const clientSecret = process.env.MS_CLIENT_SECRET;
  if (!tenantId || !clientId || !clientSecret) return null;
  return { tenantId, clientId, clientSecret };
}

export class GraphError extends Error {}

let cached: { token: string; expires: number } | null = null;

async function accessToken(config: GraphConfig): Promise<string> {
  if (cached && cached.expires > Date.now() + 60_000) return cached.token;
  const res = await fetch(`https://login.microsoftonline.com/${encodeURIComponent(config.tenantId)}/oauth2/v2.0/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: config.clientId,
      client_secret: config.clientSecret,
      scope: "https://graph.microsoft.com/.default",
    }),
    cache: "no-store",
  });
  const body = (await res.json().catch(() => ({}))) as { access_token?: string; expires_in?: number; error_description?: string };
  if (!res.ok || !body.access_token) {
    throw new GraphError(
      `Microsoft didn't accept the app's sign-in. Check MS_TENANT_ID, MS_CLIENT_ID and MS_CLIENT_SECRET (the secret may have expired). ${body.error_description?.split("\r\n")[0] ?? ""}`.trim(),
    );
  }
  cached = { token: body.access_token, expires: Date.now() + (body.expires_in ?? 3600) * 1000 };
  return cached.token;
}

async function graph(config: GraphConfig, method: string, path: string, body?: unknown): Promise<Response> {
  const token = await accessToken(config);
  return fetch(`https://graph.microsoft.com/v1.0${path}`, {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: "no-store",
  });
}

// Turns Microsoft's error into a plain sentence for the admin page.
async function plainProblem(res: Response, doing: string): Promise<string> {
  const body = (await res.json().catch(() => ({}))) as { error?: { code?: string; message?: string } };
  const message = body.error?.message ?? "";
  if (/application access policy/i.test(message)) {
    return `${doing}: Microsoft 365 hasn't allowed the app to make meetings for this account yet. Finish the access policy step (it can take 30 minutes to work).`;
  }
  if (res.status === 404) return `${doing}: Microsoft couldn't find the organiser account. Check the email address in the Teams settings.`;
  if (res.status === 401 || res.status === 403) {
    return `${doing}: Microsoft refused (${res.status}). Check the app has the OnlineMeetings.ReadWrite.All permission with admin consent. ${message}`.trim();
  }
  if (res.status === 429 || res.status >= 500) return `${doing}: Microsoft was busy (${res.status}). It will try again next run.`;
  return `${doing}: Microsoft said ${res.status}. ${message}`.trim();
}

export type MadeMeeting = { id: string; joinUrl: string };

// A standalone Teams meeting owned by the organiser. It doesn't appear in
// anyone's calendar and sends no emails: the app shows the link.
//   - Recording and transcription off: recording a private conversation
//     needs everyone's consent (Surveillance Devices Act 2016 (SA)).
//   - Everyone with the link joins straight in. The tutor joins as a guest
//     and couldn't let the student in from a waiting room, and only the
//     student, their parents and the tutor can see the link in the app.
//   - Join and leave are announced, and names can't be changed, so the
//     tutor always knows who is in the meeting.
export async function createMeeting(
  config: GraphConfig,
  organiser: string,
  m: { subject: string; startsAt: string; endsAt: string },
): Promise<MadeMeeting> {
  const res = await graph(config, "POST", `/users/${encodeURIComponent(organiser)}/onlineMeetings`, {
    subject: m.subject,
    startDateTime: new Date(m.startsAt).toISOString(),
    endDateTime: new Date(m.endsAt).toISOString(),
    allowRecording: false,
    allowTranscription: false,
    recordAutomatically: false,
    allowedPresenters: "everyone",
    lobbyBypassSettings: { scope: "everyone", isDialInBypassEnabled: false },
    isEntryExitAnnounced: true,
    allowParticipantsToChangeName: false,
    allowMeetingChat: "enabled",
  });
  if (!res.ok) throw new GraphError(await plainProblem(res, "Making a meeting"));
  const body = (await res.json()) as { id?: string; joinWebUrl?: string; joinUrl?: string };
  const joinUrl = body.joinWebUrl ?? body.joinUrl;
  if (!body.id || !joinUrl?.startsWith("https://")) throw new GraphError("Making a meeting: Microsoft sent no join link.");
  return { id: body.id, joinUrl };
}

// Deletes a meeting so its link stops working. Already gone counts as done.
export async function deleteMeeting(config: GraphConfig, organiser: string, meetingId: string): Promise<void> {
  const res = await graph(
    config,
    "DELETE",
    `/users/${encodeURIComponent(organiser)}/onlineMeetings/${encodeURIComponent(meetingId)}`,
  );
  if (res.ok || res.status === 404) return;
  throw new GraphError(await plainProblem(res, "Deleting a meeting"));
}
