# Reports (monthly, quarterly, yearly and any dates)

Asked for by Carla, 12 Nov 2026: "it would be much better for the app to
just have the ability to spit out all of these numbers (auto send monthly,
quarterly and yearly report and has the ability to generate a report for
specified dates)." The numbers are the ones she had been asking staff to
pull together by hand: how long families wait to be matched, how many
enquiries become students, how full each tutor's week is, why people leave,
and profit per hour.

## 1. What it's for

CLG's owner needs a regular, honest picture of the business without anyone
compiling it. The same five questions come up every month:

1. **Are students getting a tutor quickly?** Time from asking for a subject to
   a confirmed booking, and who is still waiting.
2. **Are enquiries turning into students?** New students added, how many
   booked, how many are still waiting, how many didn't go ahead.
3. **How full is each tutor's week?** Hours booked against the most hours each
   tutor wants (or their available hours), so CLG knows who has room before
   taking on new families and when to recruit.
4. **Why are people leaving?** Families and tutors by reason, from the Leaving
   records.
5. **Is each tutoring hour profitable?** Income less tutor wages and super, per
   hour, for school and tertiary; then after admin wages and other running
   costs.

## 2. What the evidence says

- **Tutoring works best when it starts soon and runs consistently.** The EEF
  Teaching and Learning Toolkit rates one to one and small group tuition as
  high impact for moderate cost, with the strongest results from regular
  sessions over a sustained period
  ([EEF: one to one tuition](https://educationendowmentfoundation.org.uk/education-evidence/teaching-learning-toolkit/one-to-one-tuition)).
  Evidence for Learning's Australian version says the same
  ([E4L Toolkit](https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/one-to-one-tutoring)).
  Long waits mean students start later and get fewer sessions in a term, so
  waiting time is the first figure in each report.
- **Tutor capacity limits delivery.** The EEF's National Tutoring Programme
  evaluations reported tutor availability, matching and scheduling as common
  delivery challenges
  ([EEF: NTP evaluation](https://educationendowmentfoundation.org.uk/projects-and-evaluation/projects/national-tutoring-programme)).
  Watching how full each tutor is lets CLG recruit before waits grow, and
  avoid overloading tutors.
- **Keeping the same tutor matters.** The toolkits above link impact to
  regular sessions with a consistent tutor. Leaving reasons
  (especially "tutor or student wasn't the right fit" and "times didn't
  suit") show where matching or scheduling is losing students.

## 3. How the design follows the evidence

- **Wait time is measured from the family's point of view:** it starts when a
  subject is asked for (or first waitlisted, or requested, whichever is
  earliest), or when their last tutor finished, and ends when a booking is
  confirmed. Renewals and straight swaps between bookings (less than two
  weeks apart) aren't counted as new matches. This uses the same "a declined
  offer doesn't restart the wait" rule as the Matching tab.
- **Who is waiting now** is shown in every report, using the Matching tab's own
  list, so the report and the tab always agree.
- **Tutor fullness** compares hours booked now, and average weekly session
  hours in the period (cancelled sessions left out), with each tutor's most
  hours a week (or available hours if no limit is set). Fullest first, with
  hours still free.
- **Profit per hour** is shown two ways: after tutor wages (the direct cost of
  each hour) and after all costs (admin wages plus a monthly "other costs"
  figure the owner enters). Super (12% by default) is added to every wage.
  The report warns when sessions have no pay worked out or aren't invoiced
  yet, because those make profit look higher or lower than it really is.
- **Reports are saved,** not recalculated, so a past report shows exactly
  what it showed on the day, even after records change. The owner can
  download any report as a CSV for Excel or Google Sheets.
- **Made automatically:** a monthly report on the 1st (for the month before),
  a quarterly report after each quarter (Jul-Sep, Oct-Dec, Jan-Mar, Apr-Jun)
  and a financial year report each July (1 July to 30 June). The daily timer
  (`/api/reports/cron`, about 7am Adelaide time) makes anything due and never
  makes the same report twice. Automatic reports start with November 2026.
- **"Sending":** in line with Carla's 2 Nov 2026 rule (app notices only, no
  notification emails), a new report shows as a number on the owner's
  Reports menu item and a "New" label in the list, until opened.
- **Any dates:** the owner picks a first and last day, or taps a common range
  (last month, this financial year so far, and so on).

## 4. How we'll know it works

- The owner stops compiling these figures by hand.
- Average and longest wait times fall over the year; fewer families leave
  for "times didn't suit" or "tutor wasn't the right fit".
- CLG recruits before tutors reach 90-100% full.

## 5. Privacy and child safety

- **Owner, plus Operations without money (Carla, 20 Nov 2026).** Reports
  include pay and profit, so only the owner reads the `reports` and
  `report_settings` tables and makes, deletes or downloads reports.
  Operations admins read reports through `report_list` and `report_get`,
  which take the `money` part out inside the database, so it never reaches
  their browser. Support and finance admins, tutors and families see no
  reports.
- **No children's details in reports.** Figures are counts and averages. Tutor
  names appear (for their own hours); no student names, dates of birth,
  schools or notes are saved in a report.
- **Module boundaries.** The reports module only reads scheduling, billing,
  leaving and student tables, and writes only its own two tables.
- **Laws touched:** Privacy Act 1988 and the APPs (use limited to the
  business purpose of running CLG; APP 11 security, owner-only access);
  Fair Work and super guarantee (super shown at the current 12% rate, which
  the owner can change in Settings).
- **Downloads** are sent with "don't keep a copy" settings, and only to the
  owner.

## 6. Quarterly and yearly goals, and the Operations view (Carla, 20 Nov 2026)

What it is for: Emma (Operations admin from 2027) runs day-to-day admin.
Carla wants goals "set for each quarter and year, with monthly reviews to
ensure on track and discuss why/why not".

Evidence: goal-setting research (Locke and Latham's work on specific,
challenging goals with regular feedback) finds that clear numeric targets
plus frequent progress checks lift performance more than vague aims. The
school-improvement guidance from AERO and the EEF's implementation guide
both stress choosing a few measurable indicators, reviewing them on a set
cycle, and talking about why progress is or is not happening, rather than
only reporting numbers. The design follows this:

- **A few clear figures.** Goals can only be set on eight figures without
  money: students matched, matched within 2 weeks, average wait, new
  students, new students who booked, share who booked, families who left,
  and students still waiting at the end. Each says whether more or fewer is
  better.
- **Monthly check against the share expected by now.** Figures that add up
  over a period (such as students matched) are compared with the share of
  the goal expected by today (target times days gone, divided by days in the
  period). Averages, shares and "still waiting" are compared with the target
  itself. This is on **Reports, Goals**, and monthly reports link there.
- **Met or not met at the end.** Quarterly and yearly reports show each goal
  for that period with **Met** or **Not met**.
- **Who does what.** Only the owner sets or removes goals
  (`report_set_goal`, `report_remove_goal`). The owner and Operations admins
  read goals (`report_goals`, read only) and progress
  (`report_goal_progress`). Periods must be a real quarter (1 January,
  April, July or October) or financial year (1 July).
- **Privacy.** Goals and progress hold counts only, never children's
  details. Operations still never sees money, the spreadsheet download,
  **Report for your dates** or **Settings**.

## Limits to know

- "New students" counts student records added in the period. When existing
  families move into the app (Term 1 2027) their students will count as new
  that month.
- Profit uses invoices and pay lines in the app. Costs paid outside the app
  are only included through the "other running costs a month" setting.
- Progress for the current quarter and year is worked out live each time
  **Goals** opens, so it can change during the day as matches are made.
- A straight-line "share expected by now" does not allow for school
  holidays, when enquiries are usually lower. Read **Behind** early in a
  holiday-heavy quarter with that in mind.
