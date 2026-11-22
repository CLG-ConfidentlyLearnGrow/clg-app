# Admin changes for Emma's role: student details, significant dates, 12 hr summary follow-up

Requested by Carla, 20 Nov 2026, in her comments on Emma's admin role review
(https://claude.ai/artifact/47dp6rJibjfsA3k37qskVU). Emma joins as an
Operations admin; Lauren finishes at the end of 2026.

## What changed

- **Change a student's details (admin).** Carla asked whether admins can edit
  what they check when confirming a family: year level, school, subjects and
  levels, end goal, and preferred days and times. Preferred days and times,
  places and study dates were already editable on the Schedule page. The rest
  had no admin screen, although the database already let owner and
  Operations admins change them. Admin, Families now has **Change a
  student's details**, which uses the same form parents use. The Matching
  tab's **Fill in** link for a missing year level or school opens it for that
  student (that link went nowhere useful before).
- **"Significant date", not "event".** The extra session request now asks for
  a **Significant date** (a test, exam or assignment due date). The words in
  notices and error messages changed too. Stored column names stay
  (`event_on`, `event_label`). Migration:
  `20261123400110_significant_dates_wording.sql`.
- **Missing summaries: admins told at 12 hr.** The tutor is still reminded at
  6 hr, when the summary is due. Admins are now told, and the to-do count and
  Notes overdue list count it, only if it is still missing at 12 hr.
  Migration: `20261123400200_summaries_admins_12_hours.sql`.

## Evidence

- **Accurate learner records drive matching and teaching.** EEF's guidance on
  one to one tuition and AERO's tutoring guidance both stress matching
  tutoring to the learner's current level and goals. Letting the admin who
  checks a new family correct the year level, subjects and levels on the spot
  keeps those records right without extra parent effort (EEF, *Working with
  Parents to Support Children's Learning*, 2021: keep parent asks light).
- **Assessment dates matter to families.** Extra sessions are usually before
  a test, exam or assignment. Naming them "significant dates" uses the words
  families and schools use, so requests are clearer.
- **Timely feedback.** EEF's *Teacher Feedback to Improve Pupil Learning*
  (2021) finds feedback works best when timely. The 6 hr tutor reminder keeps
  that. Moving the admin follow-up to 12 hr gives the reminder time to work,
  and still leaves 36 hr before families' 48 hr promise.

## Legal notes

- **Privacy Act 1988 (APP 10 quality, APP 11 security) and the Children's
  Online Privacy Code:** admins correcting a child's details keeps records
  accurate. Only owner and Operations admins can change them (row level
  security, unchanged), with two-step login.
- No new personal information is collected. UK GDPR Article 5(1)(d)
  (accuracy) says the same for later.

## Tests

`supabase/tests/summaries_admins_12_hours.test.sql` (hours and wording, run
twice). The existing student edit access rules are already tested in
`access_rules.test.sql`.

## More changes from Carla's notes on Emma's Job Proposal (22 Nov 2026)

### What changes

- **My Pay:** the side menu item, guides and tours now say "My Pay". The
  migration `20261124710100_my_pay_name.sql` changes the same words in
  training lessons, quiz choices and handbook pages.
- **Weekly waitlist check-ins:** each waitlist place remembers the last
  check-in. "Check in due" shows once 7 days have passed since the last one
  (or since joining), the Waitlist sub-tab counts them, and front desk
  admins press "Checked in" after contacting the family
  (`20261124710200_waitlist_weekly_check_ins.sql`).
- **Significant dates from families:** when a parent or student adds a
  test, exam or assignment due date to a roadmap, the owner and Operations
  admins get a notice straight away. Dates added by the tutor or CLG staff
  do not send one (`20261124710300_significant_dates_tell_admins.sql`).

### Research

- AERO's guidance on family engagement and the EEF's "Working with Parents
  to Support Children's Learning" both find that regular, two-way contact
  keeps families engaged. A weekly check-in keeps a waiting family in touch
  instead of leaving them a month without news, which also reduces families
  dropping out before a tutor is found.
- The EEF's tutoring guidance says sessions work best when they are linked
  to what the learner needs next. Knowing about a test or due date early
  lets the tutor plan for it, and lets CLG offer an extra session in time.

### Legal notes

- No new personal information is collected. The check-in date and who did
  it are admin records, kept with the waitlist place (APP 11). The notice to
  admins names the student and the date, which admins can already see.

### Tests

`supabase/tests/weekly_waitlist_significant_dates.test.sql`, and the
waitlist checks in `scheduling_away.test.sql` now test "check in due".
