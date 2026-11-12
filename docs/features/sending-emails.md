# Sending emails

Requested by Carla, 2026-10-29. Until now, reminders, booking notices and
progress updates only showed inside the app, and Supabase's sign-in emails
(password reset, invitations) used Supabase's limited test sender.

## What it's for

- **Sign-in emails that arrive.** Password resets, sign-up confirmations
  and invitations come from `noreply@clgtutoring.com`, look like CLG, and
  work from any browser (the `supabase/templates` emails).
- **Reminders people actually see.** The 48 hr and 1 hr session reminders,
  booking confirmed or declined, cancellations, and progress updates go to
  each person's email as well as the app, so a busy parent doesn't need to
  open the app to know what's on.
- **Tutors hear about pauses.** When a family's sessions go on hold (or
  come back on), the tutor is emailed. No money details.

## What the evidence says

- **Regular, specific messages to parents help learning.** The EEF's
  guidance report *Working with Parents to Support Children's Learning*
  recommends communicating with parents regularly, with specific and
  positive messages about what their child is learning, and using simple,
  low-effort channels
  (https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/supporting-parents).
  Evidence for Learning rates parental engagement at about +4 months
  (https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/parental-engagement).
- **Short messages work.** The EEF's *Texting Parents* trial found short,
  regular messages about tests, homework and what was being taught gave
  about one month's extra progress in maths and reduced absence, at very
  low cost
  (https://educationendowmentfoundation.org.uk/projects-and-evaluation/projects/texting-parents).
- **Attendance comes first.** One-to-one and small group tuition only
  works if the sessions happen (Evidence for Learning Toolkit, one-to-one
  tuition about +5 months). Reminders before each session reduce missed
  and late sessions.

## How the design follows the evidence

- Each email is the same short text the app shows, plus one button to open
  the app. No long newsletters.
- Quiet hours apply: nothing between 9pm and 5am in the person's own local
  time (see "Quiet hours" below).
- Each person can turn email off in their reminder settings (Schedule
  page). Notices still show in the app. The tutor pause email ignores this
  setting, because it is the only way a tutor hears about a pause.
- A notice is emailed once. If Resend is down, it is tried again every
  5 minutes. A notice more than 12 hr late (for example from before email
  was set up) stays in the app only, and a session reminder is never sent
  after the session has started or been cancelled.

## How it works

- Each module offers its own two server-only functions: one hands over the
  notices due by email and marks them sent, one puts them back if sending
  failed. The sender never writes a module's tables directly.
  - scheduling: `session_notice_emails_claim` / `_release`
  - progress: `progress_notice_emails_claim` / `_release`
  - billing: `billing_tutor_notice_emails_claim` / `_release`
  - security alerts (shared core): `security_alert_emails_claim` / `_release`
    (one summary email to the owner, ignores quiet hours; see
    [security-hardening.md](security-hardening.md))
- `src/app/api/email/cron` calls those and sends up to 100 emails at a
  time through Resend's API (with a repeat-safe key, so a retry never
  sends twice).
- Vercel's free plan runs jobs only once a day, so the database wakes the
  sender every 5 minutes (pg_cron and pg_net), and only when an email is
  waiting. It needs the app address and the cron secret saved once in
  Supabase's Vault (see the `email_sender` migration).
- Sign-in emails go through Supabase's SMTP setting to the same Resend
  account (`smtp.resend.com`, port 465, user `resend`, password = API key).

## How we'll know it works

- Resend's dashboard shows sent, delivered and bounced counts.
- `email_sent_at` on each notice; no missed-session complaints about
  reminders.
- Pilot check: fewer late or missed sessions than before (sign-on times).

## Privacy and child safety

- **What is sent:** first name, the notice's short text (which can include
  a student's name, subject, time and place), and a link. No money
  details, no staff notes, no contact details of other people.
- **Who gets it:** only the person the notice is for, at their login
  email. Students under 16 have no login, so their parent gets it.
- **Overseas provider (APP 8).** Resend is a US company. The privacy
  policy must list it as a provider that handles email addresses and
  message content outside Australia. Resend's Tokyo region is used for
  sending. CLG stays accountable under APP 8.1, so Resend's data
  processing terms should be accepted in the Resend account.
- **Security (APP 11).** The API key is only in Vercel and Supabase
  settings, never in the code. SPF, DKIM and DMARC records on
  clgtutoring.com stop others from sending fake CLG emails, which matters
  for families of children (phishing risk).
- **Spam Act 2003.** These are service messages, not marketing. They still
  say who sent them and how to stop them. Any future marketing email
  needs consent and a one-click unsubscribe.
- **Children's Online Privacy Code (OAIC, in development).** Keep emails
  to the minimum needed; no profiling or tracking pixels (open and click
  tracking stay off in Resend).
- **UK/EU later:** the same design fits UK GDPR and PECR (service
  messages, minimal data, a named processor with an overseas transfer
  basis).

## Changes, 2 Nov 2026

See [app-changes-2-nov-2026.md](app-changes-2-nov-2026.md) for the full brief.

Carla chose app notices only. Session, booking and billing notices are no
longer emailed or texted, and the email and text settings are gone.
Sign-in and password links, security alerts to the owner, and emergency
access emails are still sent.

## Quiet hours, 12 Nov 2026

Carla asked for notices to be held from 9pm to 5am (they were 8pm to 8am
until 2 Nov, then 9pm to 6am Adelaide time).

**What changed**

- One shared setting, `public.quiet_hours_settings` (9pm to 5am). Owner
  and operations admins change it under Sessions > Notices > "Quiet hours
  (all of CLG)", on the hour or half hour. Nothing else keeps its own copy.
- The hours follow the person getting the notice: a student with their own
  login uses their state, a parent uses their child's state, a tutor uses
  their work state, and anyone else (office staff) uses Adelaide time. So
  the Victorian tutor's quiet hours are 9pm to 5am Melbourne time.
- One trigger on each notice table (`session_notices`, `progress_notices`)
  checks every new notice as it is saved and holds anything due in quiet
  hours until 5am local time. The older helper
  `private.outside_quiet_hours(time)` now hands the time straight back, so
  the functions that already call it keep working and the trigger is the
  one place the rule lives.
- A "session in 1 hr" reminder that would be held until less than 15 min
  before its session (a session before about 5:15am) comes the evening
  before, 30 min before quiet hours start (8:30pm).
- Security alerts to the owner still ignore quiet hours.
- Migration: `20261113100100_quiet_hours.sql`. Tests:
  `supabase/tests/scheduling_quiet_hours.test.sql`.

**Evidence and law**

- Teenagers need 8 to 10 hr sleep a night, and phone use and alerts late
  at night are linked to less and worse sleep (Sleep Health Foundation;
  AERO's student wellbeing work treats sleep as part of readiness to
  learn). Notices are in the app only, with no push alerts, so 5am delivery
  only means a notice is waiting when the person next opens the app.
- Privacy and child safety: the UK Age Appropriate Design Code and the
  coming Australian Children's Online Privacy Code both expect services
  used by children not to nudge them to keep using the service, including
  at night. Holding notices overnight in each person's local time follows
  that. No new personal information is collected: the time zone comes from
  the state already held for matching and tutor checks.
