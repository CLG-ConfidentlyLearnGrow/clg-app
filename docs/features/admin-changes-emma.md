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
  `20261123400100_significant_dates_wording.sql`.
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
