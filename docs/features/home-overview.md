# Home overview for every dashboard

Asked for by Carla, 20 Nov 2026: "When going home to the home dashboard of
each profile, can it please be an overview dashboard, so it is a quick look
at all the important things for that particular person's role."

## 1. What it is for

Until now, **Home** and the role tabs opened the first working section of
each dashboard: the admin Families list, the tutor's student list, the
parent's children list, the student's learning page. Important things were
spread across the side menu (numbers on tabs, a session card, check
statuses in another section, billing on its own page). People had to open
several pages to know whether anything needed them.

Each dashboard now opens on an **Overview** page: one screen that answers
"what needs me, and what is coming up?" for that role (and, for admins,
for that admin level). Every tile and line links straight to the page where
the job is done.

## 2. What the evidence says

- **Show what needs action first, then what is coming up.** Dashboard design
  guidance (Stephen Few, *Information Dashboard Design*, 2nd ed. 2013;
  Nielsen Norman Group, "Dashboards: Making Charts and Graphs Easier to
  Understand", 2017) recommends one screen, the few measures that matter
  for the person's job, and exceptions (things that need action) placed
  where the eye lands first. The Overview lists "Needs your attention"
  first and shows "All caught up" when nothing does.
- **Reduce what people have to hold in their heads.** AERO's
  [*Teaching how students learn* practice guides](https://edresearch.edu.au/resource-collections/teaching-how-students-learn-practice-guides)
  (cognitive load theory) recommend removing what is not needed so attention
  goes to what matters. Each line is a plain sentence with one link, not a
  table to read.
- **Families stay involved when information is regular, specific and easy to
  act on.** The EEF's
  [*Working with Parents to Support Children's Learning*](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/supporting-parents)
  and Evidence for Learning's
  [Teaching and Learning Toolkit](https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit)
  (parental engagement: positive impact for moderate cost) support short,
  actionable messages. The parent Overview shows each child's next session,
  their tutor, and new updates from the tutor, with one link to act.
- **Students learn more when they plan and track their own next steps.** The
  EEF's
  [*Metacognition and Self-Regulated Learning*](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/metacognition)
  guidance (one of the highest-impact, lowest-cost approaches in the
  Toolkit) recommends explicitly planning, monitoring and reviewing. The
  student Overview shows the steps due this week and the next session, so
  the student can plan the week.
- **Learner dashboards should support goals, not comparison.** Reviews of
  learning dashboards (Schwendimann et al., *IEEE Transactions on Learning
  Technologies*, 2017; Jivet et al., *LAK '18*, "License to evaluate")
  warn that comparing learners with each other can lower motivation. The
  student and parent Overviews only ever show the learner's own steps and
  sessions. Nothing ranks or compares children.
- **Keep compliance jobs visible to staff.** The tutor Overview shows each
  child safety check that is missing, expired or due within 60 days, and the
  admin Overview (Owner and Operations) lists tutors whose checks need
  renewing, so no one keeps working past an expiry.

## 3. What was built

- A new page, `/home?as=admin|tutor|parent|student`. **Home** in the top bar,
  the logo, and each role tab now open it. **Overview** is the first item in
  every side menu. The old first sections are still in the menu (for
  example **Your children**, **Your students**, **Your learning**,
  **Families**).
- **Needs your attention**: every side-menu item that has a number, written
  as a plain sentence with a link (for example "2 notes or reviews to write
  for your students"). Because it is built from the same side menu, it shows
  only what that person's role and admin level can open. Child safety
  concerns, flagged words (Child Safety Officer and Deputy only) and help
  chats with a new reply are added when there are any.
- **Admin** (by level): sessions today and this week across CLG (front
  desk), families waiting for a tutor, Billing jobs (Owner, Operations and
  Finance), and tutors whose checks need renewing (Owner and Operations).
  Finance admins now have an Overview too, instead of landing on Billing.
- **Tutor**: sessions this week (with hours), the next session, number of
  students, child safety checks (each one that is missing, expired or due
  within 60 days), and the next 5 sessions in the coming week.
- **Family** (the parent role): sessions on hold (every parent is told, as before), each own
  child with their tutors and next session, the family's next sessions, new
  updates from tutors, and a **Billing** card only for the person or people
  who pay.
- **Student**: sessions on hold, the next session, steps due this week, their
  own tutors, and the next sessions in the coming week.

## 4. Speed

- The attention list reuses the side menu, which is now built once per page
  (React `cache`), and the to-do numbers already come from one database call
  (`to_do_counts`).
- Sessions for the coming week come from one `list_sessions` call, shared by
  every card on the page.
- Migration `20261122610100_sessions_starts_at_index.sql` adds an index on
  `sessions.starts_at`. Admin views of sessions (this Overview, the Sessions
  page and calendars) filter by start time across all tutors, which had no
  index. Test: `supabase/tests/home_overview_index.test.sql`.

## 5. Legal and privacy rules it touches

- **Australian Privacy Principles 6 and 11, and the Children's Online Privacy
  Code (data minimisation, best interests of the child)**: the Overview shows
  only what the person already sees elsewhere, and only what their role
  needs. Nothing new is collected.
- **Own-view filtering**: each card is filtered to the viewer's own links
  (a parent's own children by `parent_student_links.parent_id`, a student's
  own record by `students.account_id`, a tutor's own sessions by `tutor_id`),
  not just to what row level security allows. This matters for people with
  several roles (for example an admin who is also a parent).
- **Sibling privacy**: a student's own Overview shows only their own
  sessions, steps and tutors, never a sibling's.
- **Tutor need-to-know**: the tutor Overview shows only the tutor's own
  sessions, students and checks. No billing or family details.
- **Billing only for payers** (Carla, 16 Nov 2026): the Billing card shows
  only when the database says the person pays (`billing_i_pay`), and only
  for the families they pay for. Non-payers still see **Sessions on hold**.
- **Child safety (SA Child Safety (Prohibited Persons) Act 2016, WWCC; RRHAN-EC)**:
  check expiries are shown to the tutor and to Owner and Operations admins
  so checks are renewed before they lapse.
- **UK and EU** (for later): the same minimisation and role-based display
  fits UK GDPR and the UK Age Appropriate Design Code.
