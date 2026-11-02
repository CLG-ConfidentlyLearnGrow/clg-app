# Admin levels

Requested by Carla, 2026-10-29. Proposal approved the same day
(https://claude.ai/artifact/1iiDNvJx6FxqwsREsSzoXa): four levels, Lauren as
Operations, all four built now, plus emergency owner access with a 48 hr
delay and a required reason.

## What it's for

Until now there were two admin levels: the owner (Carla) and "staff admin",
who could see and do nearly everything. As CLG grows it will add office help
and a bookkeeper. Each should only see what their job needs, because the app
holds children's learning records, contact details and money.

| Level | Who | What they do |
| --- | --- | --- |
| Owner | Carla | Everything. Only the owner adds or removes admins, changes levels, prices, pay rates, billing rules and record-keeping periods, overrides a billing pause (unless she allows Operations), and erases records. |
| Operations | Lauren | Day-to-day running: families, matching, bookings, tutor checks, progress, curriculum, invoices, inviting tutors. Sees tutor pay but doesn't change it. (This is what "staff admin" was.) |
| Support | Future office help | Family contact details, setting up families, login links, bookings and sessions, and whether a family is paused. No progress notes, tutor checks or money details. |
| Finance | Future bookkeeper | Invoices, payments, credits, tutor pay and pay rates. Sees names on invoices; no student records, sessions, notes or tutor checks. |

Child safety duties (Child Safety Officer: Carla; deputy for concerns about
Carla: Lauren) are separate from levels and are not changed here. A
concerns register isn't built yet; when it is, it gets its own rules.

**Emergency owner access.** If Carla can't be reached, an Operations admin
can ask for owner access. They must write a reason. Carla is emailed at
once with the reason. Access starts 48 hr later unless Carla cancels, lasts
7 days, then ends by itself. The person is emailed when it starts and ends,
and when Carla cancels. Nobody, including someone using emergency access,
can change or remove the owner's own admin access or make a second owner.

The owner sees every staff member (tutors and admins) with their level in
Admin > Staff and accounts, and changes levels there.

## What the evidence says

The education research bodies (Evidence for Learning, AERO, EEF) study
teaching, not system access. The guidance that applies comes from privacy,
security and child-safe-organisation sources used by Australian schools:

- **Only the access a job needs.** APP 11 requires reasonable steps to
  protect personal information; the OAIC's Guide to securing personal
  information names role-based access, "need to know" and regular access
  reviews as expected steps
  (https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/handling-personal-information/guide-to-securing-personal-information).
- **Restrict admin powers.** The Australian Cyber Security Centre's
  Essential Eight lists restricting administrative privileges as a core
  control: give admin rights only to those who need them, for the tasks
  they need, and review them
  (https://www.cyber.gov.au/resources-business-and-government/essential-cyber-security/essential-eight).
- **How schools split access.** School systems give office, finance and
  wellbeing staff different access rather than one admin key. The UK DfE's
  data protection guidance for schools makes the same point (access by role,
  removed when staff leave).
- **Children's data.** The National Principles for Child Safe Organisations
  (Principle 10, policies and procedures; Principle 6, complaints) and the
  coming Children's Online Privacy Code point the same way: fewer people
  seeing a child's records means less risk.
- **Separation of duties for money.** Keeping "set the rules" (owner) apart
  from "apply the rules" (Operations, Finance) means the people who send
  invoices can't also change prices or billing rules.
- **Continuity.** A business with one owner key needs a safe way to keep
  running if the owner is unavailable ("break glass" access). A delay with
  notice, a reason, a time limit and a full log is the usual pattern.

## How the design follows the evidence

- Levels live in the database (row level security), not only the screens.
  `private.is_admin()` now means owner or operations, so every older rule
  keeps working, and the new levels start with nothing and are given only
  what they need.
- Support and Finance get extra "may see" rules for their tables; billing
  rules and functions were switched to "admin or finance"; changing pay is
  owner and finance only; prices and kept family rates are owner only.
- Each admin reads only their own activity log entries; the owner reads all.
- All levels still need two-step login.
- The app shows each admin only the sections for their level.

## How we'll know it works

- Database tests (`supabase/tests/staff_levels.test.sql`) check what each
  level can and can't see or change, and the emergency access rules.
- Carla reviews the staff list every 3 months (Essential Eight practice).

## Privacy and child safety

- New table `emergency_owner_access` (who asked, reason, times). Seen by the
  owner and Operations only. Every request and cancellation is logged with
  the reason.
- No new personal data is collected.
- Legal rules touched: Privacy Act APP 11 (security), Children's Online
  Privacy Code (data minimisation), SA child safe environments and the
  National Principles (clear responsibility). UK GDPR Article 32 and
  Article 5(1)(f) say the same for later.

## Notes for running the migrations

Run `20261029900100_admin_levels_names.sql` first, then
`20261029900200_admin_levels.sql`. If an older billing, scheduling or
family-setup file is ever run again, run `20261029900200_admin_levels.sql`
again afterwards, because older files put back their old rules. The same
goes for `20261029700100_email_sender.sql`. Don't re-run
`20261029800100_staff_invite_links.sql` after this.
