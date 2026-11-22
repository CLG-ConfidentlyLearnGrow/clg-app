# Staff probation

Requested by Carla, 20 Nov 2026, in her comments on the admin role (Emma)
review: track probation in the app and remind her when someone is due.

## 1. What it is for

- **Tutors** finish probation at **3 months or 30 completed sessions**,
  whichever comes first.
- **Admin staff** (for example the new admin role) finish probation at
  **3 months or 40 approved hours** (one full-time work week, 8 hours x
  5 days), whichever comes first. Carla changed this from 30 hours on
  22 Nov 2026 (migration `20261123700100_probation_admin_40_hours.sql`).
- The app **reminds Carla** (the owner) when a probation review is due, so
  no review is missed while she is busy tutoring and running the business.

## 2. What the evidence says

- **Early support and feedback shape practice.** The EEF's *Effective
  Professional Development* (2021) finds that practice improves with
  specific feedback, follow-up and support over time, rather than one-off
  input. A planned review point gives CLG and the new staff member a set
  time to look at what is going well and what to work on.
- **Induction matters most at the start.** AITSL's *Graduate to Proficient*
  (2016) and Ingersoll and Strong's review of induction and mentoring
  (Review of Educational Research, 2011) find that structured early support
  helps new educators settle, improves their teaching practice and helps
  keep them. Probation in CLG works alongside the training modules and the
  match check-ins, not instead of them.
- **Experience, not only time.** A tutor who teaches many sessions in a
  short time has given CLG enough to review sooner. Counting sessions (or
  hours for admin staff) alongside months makes the review happen when
  there is enough to look at, which is why Carla chose "whichever comes
  first".

## 3. How it works

- One probation record per person and role (`staff_probations`). Someone
  who is both a tutor and an admin has one for each role.
- **Progress** counts from the probation start date:
  - tutors: completed sessions (cancelled and no-show sessions do not
    count);
  - admin staff: approved admin hours from My pay (hours still waiting for
    approval do not count yet).
- **Due date**: the earlier of 3 months after the start and the day the
  30th session (tutors) or 40th hour (admin staff) was reached. If the owner extends a probation, it is
  due on the new date instead.
- **Daily run** (`/api/probation/cron`, about 7:30am Adelaide time):
  - sets up a probation for any tutor or admin (never the owner) whose pay
    details have a start date in the last 3 months and who has no record
    for that role yet;
  - sends the owner one app notice when a probation becomes due, saying why
    (3 months, 30 sessions, 40 hours, or the extended date).
- **Staff probation page** (`/admin/probation`, owner only): due reviews
  with a form to mark each **passed**, **extended** (new date) or
  **ended**; everyone still on probation with progress; a form to set up a
  probation by hand; and finished probations. The side menu shows how many
  are due.

## 4. Legal rules it touches

- **Fair Work Act 2009 (Cth), unfair dismissal.** The minimum employment
  period before someone can make an unfair dismissal claim is 6 months, or
  12 months for a small business employer (fewer than 15 employees)
  (ss 383 and 384). CLG's 3-month probation is a CLG review point. It does
  not change that legal period, and it does not change notice, pay or
  National Employment Standards entitlements. The Small Business Fair
  Dismissal Code still applies to any dismissal.
- **Casual employees.** A probation review does not change casual
  employment status or the casual conversion and employee choice rules.
- **Employee records.** Probation notes are part of the employee record.
  The Privacy Act's employee records exemption covers a private employer's
  handling of current and former employees' records, but CLG still keeps
  them private: only the owner can see them, with two-step login, and
  every change is in the activity log.
- **Child safety (Children and Young People (Safety) Act 2017 (SA)).** The
  probation review is a natural time to confirm the staff member's child
  safety checks, Code of Conduct and child safe training are in place.
  This feature does not change the checks themselves.

## 5. Access rules

- Only the owner (with two-step login) can read or change probation
  records. Operations, Support and Finance admins cannot, and staff cannot
  see their own record.
- Nobody writes the table directly; every change goes through a database
  function that checks who is asking.
- Tests: `supabase/tests/staff_probation.test.sql`.

## 6. Module boundaries

Writes only `staff_probations`. Reads accounts, account_roles,
admin_profiles, sessions, billing_hour_logs and billing_staff_pay. Sends
app notices through the shared `private.add_notice` helper.
