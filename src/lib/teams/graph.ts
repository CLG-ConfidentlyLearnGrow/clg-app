// Summary: talks to Microsoft Graph, the service behind Microsoft 365, to
// make and delete Teams meetings. Uses an app registered in CLG's Microsoft
// 365 (Microsoft Entra) with the "OnlineMeetings.ReadWrite.All" permission,
// limited by an application access policy to the one organiser account.

// Stops this file ever being sent to the browser, because it uses Microsoft secrets.
import "server-only";

// The three settings needed to sign in to Microsoft.
export type GraphConfig = { tenantId: string; clientId: string; clientSecret: string };

// The three Vercel secret settings. Missing ones mean Teams links are not
// set up yet; the rest of the app works as normal.
export function graphConfig(): GraphConfig | null {
  const tenantId = process.env.MS_TENANT_ID; // CLG's Microsoft 365 organisation id.
  const clientId = process.env.MS_CLIENT_ID; // The registered app's id.
  const clientSecret = process.env.MS_CLIENT_SECRET; // The registered app's password.
  if (!tenantId || !clientId || !clientSecret) return null; // Any missing means Teams isn't set up.
  return { tenantId, clientId, clientSecret }; // Hands back all three.
} // End of graphConfig.

// A Microsoft problem with a plain message, so callers can show it to admins.
export class GraphError extends Error {}

// The last sign-in pass from Microsoft and when it runs out, kept to avoid signing in every time.
let cached: { token: string; expires: number } | null = null;

// Gets a sign-in pass (access token) from Microsoft, reusing the last one if still fresh.
async function accessToken(config: GraphConfig): Promise<string> {
  if (cached && cached.expires > Date.now() + 60_000) return cached.token; // Still good for over a minute, so reuses it.
  const res = await fetch(`https://login.microsoftonline.com/${encodeURIComponent(config.tenantId)}/oauth2/v2.0/token`, { // Asks Microsoft's sign-in service for a pass:
    method: "POST", // as a new request,
    headers: { "content-type": "application/x-www-form-urlencoded" }, // sent as form data,
    body: new URLSearchParams({ // containing:
      grant_type: "client_credentials", // "sign in as the app itself, not a person",
      client_id: config.clientId, // the app's id,
      client_secret: config.clientSecret, // the app's password,
      scope: "https://graph.microsoft.com/.default", // and "use the permissions the app was given".
    }), // End of the form data.
    cache: "no-store", // Never reuses an old saved reply.
  }); // End of the request.
  const body = (await res.json().catch(() => ({}))) as { access_token?: string; expires_in?: number; error_description?: string }; // Reads Microsoft's reply (empty if unreadable).
  if (!res.ok || !body.access_token) { // Sign-in failed:
    throw new GraphError( // Stops with a plain message, including the first line of Microsoft's reason.
      `Microsoft didn't accept the app's sign-in. Check MS_TENANT_ID, MS_CLIENT_ID and MS_CLIENT_SECRET (the secret may have expired). ${body.error_description?.split("\r\n")[0] ?? ""}`.trim(),
    ); // End of the error.
  } // End of the failure check.
  cached = { token: body.access_token, expires: Date.now() + (body.expires_in ?? 3600) * 1000 }; // Keeps the pass and when it runs out (1 hr if not said).
  return cached.token; // Hands back the pass.
} // End of accessToken.

// Sends one request to Microsoft Graph, signed in.
async function graph(config: GraphConfig, method: string, path: string, body?: unknown): Promise<Response> {
  const token = await accessToken(config); // Gets a sign-in pass.
  return fetch(`https://graph.microsoft.com/v1.0${path}`, { // Sends the request to this Graph address:
    method, // using this action (GET, POST, DELETE),
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, // with the pass, as JSON,
    body: body === undefined ? undefined : JSON.stringify(body), // with the content, if any, as JSON text,
    cache: "no-store", // never reusing an old saved reply.
  }); // End of the request.
} // End of graph.

// Turns Microsoft's error into a plain sentence for the admin page.
async function plainProblem(res: Response, doing: string): Promise<string> {
  const body = (await res.json().catch(() => ({}))) as { error?: { code?: string; message?: string } }; // Reads Microsoft's error reply.
  const message = body.error?.message ?? ""; // Microsoft's own message (blank if none).
  if (/application access policy/i.test(message)) { // The access policy step isn't finished:
    return `${doing}: Microsoft 365 hasn't allowed the app to make meetings for this account yet. Finish the access policy step (it can take 30 minutes to work).`; // explains what to do.
  } // End of the access policy case.
  if (/valid GUID/i.test(message)) { // Microsoft was given an email where it needs the Object ID:
    return `${doing}: Microsoft needs the organiser account's Object ID, not its email. Add it in Teams links > Settings.`; // explains what to do.
  } // End of the Object ID case.
  if (res.status === 404) return `${doing}: Microsoft couldn't find the organiser account. Check the Object ID in the Teams settings.`; // Account not found.
  if (res.status === 401 || res.status === 403) { // Not allowed:
    return `${doing}: Microsoft refused (${res.status}). Check the app has the OnlineMeetings.ReadWrite.All permission with admin consent. ${message}`.trim(); // explains the permission needed.
  } // End of the not-allowed case.
  if (res.status === 429 || res.status >= 500) return `${doing}: Microsoft was busy (${res.status}). It will try again next run.`; // Too busy or down.
  return `${doing}: Microsoft said ${res.status}. ${message}`.trim(); // Anything else, with Microsoft's message.
} // End of plainProblem.

// A meeting that was made: its Microsoft id and its join link.
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
  config: GraphConfig, // The Microsoft settings.
  organiser: string, // The Microsoft account that owns the meeting.
  m: { subject: string; startsAt: string; endsAt: string }, // The meeting's title, start and end.
): Promise<MadeMeeting> {
  const res = await graph(config, "POST", `/users/${encodeURIComponent(organiser)}/onlineMeetings`, { // Asks Microsoft to make the meeting:
    subject: m.subject, // title,
    startDateTime: new Date(m.startsAt).toISOString(), // start time in standard format,
    endDateTime: new Date(m.endsAt).toISOString(), // end time in standard format,
    allowRecording: false, // no recording,
    allowTranscription: false, // no transcripts,
    recordAutomatically: false, // never starts recording by itself,
    allowedPresenters: "everyone", // anyone can share their screen,
    lobbyBypassSettings: { scope: "everyone", isDialInBypassEnabled: false }, // everyone with the link skips the waiting room (phone dial-in doesn't),
    isEntryExitAnnounced: true, // joining and leaving are announced,
    allowParticipantsToChangeName: false, // names can't be changed,
    allowMeetingChat: "enabled", // and the chat is on.
  }); // End of the meeting settings.
  if (!res.ok) throw new GraphError(await plainProblem(res, "Making a meeting")); // Stops with a plain message if refused.
  const body = (await res.json()) as { id?: string; joinWebUrl?: string; joinUrl?: string }; // Reads Microsoft's reply.
  const joinUrl = body.joinWebUrl ?? body.joinUrl; // The join link (Microsoft uses either name).
  if (!body.id || !joinUrl?.startsWith("https://")) throw new GraphError("Making a meeting: Microsoft sent no join link."); // Checks we got a proper link.
  return { id: body.id, joinUrl }; // Hands back the meeting id and link.
} // End of createMeeting.

// Deletes a meeting so its link stops working. Already gone counts as done.
export async function deleteMeeting(config: GraphConfig, organiser: string, meetingId: string): Promise<void> {
  const res = await graph( // Asks Microsoft to delete:
    config, // using the Microsoft settings,
    "DELETE", // the delete action,
    `/users/${encodeURIComponent(organiser)}/onlineMeetings/${encodeURIComponent(meetingId)}`, // this organiser's meeting.
  ); // End of the request.
  if (res.ok || res.status === 404) return; // Deleted, or already gone: done.
  throw new GraphError(await plainProblem(res, "Deleting a meeting")); // Otherwise stops with a plain message.
} // End of deleteMeeting.
