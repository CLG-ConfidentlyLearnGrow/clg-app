# Teams links for online sessions

Requested by Carla, 2026-10-28. Part of scheduling's "automatic from
booking to session" plan (scheduling brief:
https://claude.ai/artifact/VKHnZFR36UFzbxvFi5jezV): once a booking is
confirmed, the Teams link appears by itself.

## What it's for

Today each family has a Teams team and each student a channel, set up by
hand. Tutors have personal email addresses, not CLG Microsoft accounts.
The app now makes one Teams meeting for each online session, owned by one
CLG Microsoft 365 account, and shows a "Join" button on the session for the
student, their parents and the tutor. Nobody needs a CLG Microsoft account
or has to find the right channel.

## What the evidence says

- **Tutoring works online when it is reliable.** One-to-one and small
  group tuition are among the highest-impact, best-evidenced approaches
  (Evidence for Learning Toolkit: one-to-one tuition about +5 months,
  small group tuition about +4 months:
  https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/one-to-one-tuition).
  The EEF's rapid evidence assessment of remote learning found that the
  quality of teaching matters more than how lessons are delivered, and
  that making sure pupils can get into lessons is a precondition
  (https://educationendowmentfoundation.org.uk/education-evidence/evidence-reviews/remote-learning).
- **Lost minutes are lost learning.** The EEF's online tuition pilot
  (2020–21) found online tuition workable and well received, with joining
  and technology problems the main early barrier
  (https://educationendowmentfoundation.org.uk/projects-and-evaluation/projects/online-tuition-pilot).
  A link that is always in the same place, ready before the session,
  removes the "which link?" problem.
- **Consistency supports the tutoring relationship**, which the toolkit
  names as part of why tuition works; the link sits beside the same tutor
  and time every week.

## How the design follows the evidence

- A link is made automatically for every scheduled online session in the
  next 7 days (admin can change 1–28), so it is ready well before the
  reminders go out (48 hr and 1 hr before).
- The link shows as "Join" on the session in the app, the one place
  families already look. No emails, no calendar invites.
- If Microsoft is down or the setup is incomplete, the admin page shows
  the problem in plain words, and an admin can paste any link by hand.
- The job runs every morning, after any booking or cancellation, and when
  people open their schedule (at most every 5 minutes), so links appear
  and disappear quickly without needing a paid Vercel plan.

## How we'll know it works

- Share of online sessions with a link 24 hr before start (aim: all).
- Meetings that failed to be made (admin page, "Couldn't make it yet").
- Later, from session feedback: "couldn't join" or late starts.

## Privacy and child safety

**Data sent to Microsoft:** the session's subject and start and end
times, with the title "CLG session: <subject>". No names, year levels or
other details. People joining type their own display name in Teams.
Microsoft 365 is already CLG's email and Teams provider. Microsoft stores
Australian tenants' Teams data in Australia (APP 8, cross-border; check
the tenant's data location in the Microsoft 365 admin centre).

**Who sees the link:** only the student, their parents, the tutor and CLG
admins (database rules on sessions; list_sessions). The teams_meetings
table is visible to admins only and written only by the server.

**Child safety choices (National Principles for Child Safe Organisations,
Principle 8, safe online environments; SA Child Safe Environments; CLG
child safe policy and code of conduct):**
- Each meeting is deleted when the session is cancelled, and one hour
  after it ends, so a CLG link can't be used for contact outside booked
  times.
- Recording and transcription are off. Recording a private conversation
  needs everyone's consent under the Surveillance Devices Act 2016 (SA);
  if CLG wants recordings later, that needs a consent process first.
- Joining and leaving are announced and names can't be changed, so the
  tutor and student always know who is present.
- Everyone with the link joins without a waiting room. Tutors join as
  guests and couldn't admit the student from a waiting room; the link's
  only holders are the people above.
- Meeting chat stays on (tutors share questions and links). It is kept in
  the organiser account's mailbox, so CLG holds a record if a concern is
  raised.
- The Microsoft app may make meetings only for the one organiser account:
  an application access policy limits it, rather than allowing every
  CLG mailbox.

**Laws touched:** Privacy Act 1988 and APPs 1, 6, 8 and 11; the Children's
Online Privacy Code (OAIC, due December 2026: data minimisation and
default settings that favour the child); Children and Young People
(Safety) Act 2017 (SA); Surveillance Devices Act 2016 (SA). For later:
UK GDPR and the ICO Children's Code, and EU GDPR (Microsoft as processor
under its data protection addendum).

**Retention:** meetings are deleted in Teams after the session. The
teams_meetings rows (no personal details beyond the session id) are kept
with the session and go when the session is deleted.

## Built

- Migration `20261029000100_scheduling_meeting_link.sql` (scheduling):
  `set_session_meeting_url`, the one way to set a session's link (server
  and admins only).
- Migration `20261029000200_teams.sql` (this module): `teams_settings`,
  `teams_meetings`, and server-only functions that hand out work and
  record results. Tests: `supabase/tests/teams.test.sql`.
- Server code: `src/lib/teams` (Microsoft Graph, the job),
  `/api/teams/cron` (daily, 5:30am Adelaide), admin page `/admin/teams`.

## Microsoft 365 setup (once)

1. Choose the organiser account. It needs a Teams licence. A dedicated
   account (for example sessions@clgtutoring.com) keeps meetings separate
   from personal mail; an existing account works too.
2. In portal.azure.com > Microsoft Entra ID > App registrations, register
   an app ("CLG app Teams links"), single tenant, no redirect address.
   Note the Directory (tenant) ID and Application (client) ID.
3. API permissions > Add > Microsoft Graph > Application permissions >
   OnlineMeetings.ReadWrite.All, then "Grant admin consent".
4. Certificates & secrets > New client secret (24 months). Copy its Value.
5. Application access policy, in PowerShell with the MicrosoftTeams module
   (`Install-Module MicrosoftTeams`, `Connect-MicrosoftTeams`):
   `New-CsApplicationAccessPolicy -Identity CLG-App-Teams -AppIds "<client id>" -Description "CLG app Teams links"`
   then
   `Grant-CsApplicationAccessPolicy -PolicyName CLG-App-Teams -Identity "<organiser's object ID>"`.
   It can take up to 30 minutes to start working.
6. In Vercel, add MS_TENANT_ID, MS_CLIENT_ID and MS_CLIENT_SECRET, and
   redeploy.
7. In the app, Admin > Teams links > Settings: enter the organiser email
   and switch on. Then "Make links now" to test.

The client secret expires; renew it before then (put a reminder in the
calendar).
