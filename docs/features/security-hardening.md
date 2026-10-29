# Background security (hardening)

Requested by Carla, 2026-10-29: "reinforce the app so it keeps all the
things extra safe ... something that can be added in the background which
doesn't impact the size or working ability of the app negatively."

Carla's follow-up: keep the access request for tutors and admins, with
access granted from the app. The alerts below only tell the owner; giving
access still happens in the app exactly as before.

## What it's for

The app holds children's names, year levels, learning records and family
contact details. Most of the protection is already in place (access rules
on every table, 2-step login for staff, account lock after 5 wrong
passwords, private file stores, signed payment messages, a 7-year activity
log, automatic deletion). This work adds the layers that catch mistakes
and attacks early, without changing how the app looks or how fast it runs.

## What the guidance says

This is a security feature, so the evidence comes from security and privacy
guidance rather than education research:

- **OAIC, Guide to securing personal information** and **APP 11**: take
  reasonable steps to protect personal information, including software
  security, monitoring and logging, and acting quickly on incidents. Under
  the Notifiable Data Breaches scheme CLG must assess a suspected breach
  within 30 days; early alerts make that possible.
  https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/handling-personal-information/guide-to-securing-personal-information
- **OWASP Top 10 (A03 Injection, A05 Security Misconfiguration, A06
  Vulnerable Components, A09 Logging and Monitoring Failures)** and **OWASP
  ASVS 4.0** (V1.4 access control architecture, V7 logging and alerting,
  V14.4 HTTP security headers). https://owasp.org/Top10/
- **ACSC Essential Eight**: patch applications quickly, restrict admin
  privileges, regular backups.
  https://www.cyber.gov.au/resources-business-and-government/essential-cyber-security/essential-eight
- **Children's Online Privacy Code** (OAIC, being developed under the
  Privacy and Other Legislation Amendment Act 2024): expects strong default
  protection for children's information.
- UK/EU for later: UK GDPR Article 32 and the ICO Children's Code
  (standard 11 data security) point the same way.

## What it does

1. **Browser lock-down rules** (`next.config.ts`). A Content Security
   Policy tells browsers to run only the app's own code, load images only
   from the app or Supabase, talk only to Supabase, send forms only to the
   app or Stripe's payment page, and never show the app inside another site.
   No nonces, so pages stay static and fast. Also `Cross-Origin-Opener-Policy`.
2. **Database safety test** (`supabase/tests/security_baseline.test.sql`).
   Fails the build if any table is missing access rules, any view skips
   them, any special-rights function has no fixed search path, or any file
   store is public. Runs only in testing; nothing changes in the live app.
3. **Add-on and leaked-secret checks** (`.github/`). Dependabot proposes
   add-on updates weekly (security fixes straight away). CI fails if a
   live add-on has a known high or critical flaw (`npm audit`) or if a
   password or key has been saved into the code (Gitleaks).
4. **Security alert emails to the owner**
   (`20261029950100_security_alerts.sql`). Raised when an account is locked
   after 5 wrong passwords, when 30 or more wrong passwords happen across all
   accounts within 1 hr (at most once every 6 hr), when someone is given
   tutor or admin access, and when someone's admin access is removed.
   Gathered into one email per run of the email sender (every 5 minutes at
   most) with a link to the admin page. Alerts ignore the 8pm to 8am quiet
   hours, because a security problem can't wait.
5. **Timing-safe check of the nightly jobs' password** (`src/lib/cron-auth.ts`).

## Settings Carla turns on (free)

- **Vercel > Project > Settings > Deployment Protection**: Vercel
  Authentication on for preview deployments, so test versions of the app
  can only be opened by people signed in to CLG's Vercel team.
- **GitHub > repo Settings > Advanced Security**: turn on Dependabot alerts
  and Dependabot security updates.
- **Supabase > Advisors > Security Advisor**: open once a month and fix
  anything red. Also check Authentication > Rate Limits are on.
- 2-step login on the GitHub, Vercel, Supabase, Resend and Stripe accounts.

## Paid, recommended before the pilot holds real children's data

- **Supabase Pro (about US$25 a month)**: daily backups (the free plan has
  none), "Prevent use of leaked passwords", idle sign-out, longer logs.

## How we'll know it works

- CI shows the security job green on every pull request.
- The owner receives a test alert after giving someone tutor access.
- Supabase Security Advisor shows no errors.

## Privacy and child safety

- Alerts hold an email address or account, a role and a time. No student
  information. Only the owner can read them; nobody can edit them. They
  are deleted after the activity log period (7 years).
- Alert emails go through Resend (United States), the same as other app
  emails; they contain staff and parent email addresses only.
- Nothing here blocks or approves access. Alerts support Carla's role as
  breach response lead under the Data Breach Response Plan.
