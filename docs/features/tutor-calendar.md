# Weekly calendar and private calendar link (tutors, parents, students)

Asked for by Carla, 12 Nov 2026: "The tutors need to be able to see their
weekly bookings - or at least integrate them into their own calendars."

## 1. What tutors could already see

- **Sessions > Overview** (tutor dashboard) lists upcoming sessions for the
  next 10 weeks as one long list, in Adelaide time, with Teams links.
- **Sessions > Bookings** lists each regular booking (day, time, place).
- There was no week-at-a-glance view, and no way to get sessions into a
  tutor's own calendar app.

## 2. What this adds

1. **Weekly calendar** tab in the tutor side menu
   (`/dashboard/tutor/calendar`). One week at a time, Monday to Sunday, with
   time, student, subject, place, status and **Join on Teams**. Times are on
   the tutor's own clock (the state they work in, from Admin > tutor work
   settings; Adelaide if not set). Cancelled sessions show faded and crossed
   out. Week total of sessions and hours at the top.
2. **Private calendar link** (iCal / `.ics` subscription) on the same page.
   The tutor makes a link, then taps **Add to Google Calendar**, **Add to
   Apple or phone calendar**, or pastes it into Outlook. Their calendar app
   checks it every few hours. It covers 4 weeks back to 6 months ahead.
   Cancelled sessions are sent as cancelled so the calendar removes them.

## 3. Privacy and safety (legal rules it touches)

- **Australian Privacy Principles 3, 6 and 11** (collect and use only what's
  needed; keep it secure) and the **Children's Online Privacy Code** (least
  data about children): the link shows only the student's **first name**,
  subject, time and place (library name and address, or Online). Teams links
  are NOT included (Carla decided 15 Nov 2026, see below). No surname, family contact, home address, school, notes, goals or
  money. Home-session addresses are never sent ("In person (see the CLG
  app)").
- Calendar apps can't sign in, so the link carries a 64-character random
  secret. Only a scrambled copy (SHA-256 hash) is stored, so a database leak
  can't rebuild links. The link is shown once.
- The tutor can **make a new link** (old one stops at once) or **turn it
  off**. The link stops by itself if the person loses the tutor role or
  their tutor profile is switched off.
- Making, replacing and turning off a link is written to the audit log.
- A wrong or old link gets an empty calendar (no hint whether it ever
  worked). Responses are marked `no-store` and `noindex`.
- **UK GDPR / EU GDPR** (data minimisation, Art. 5(1)(c)): same approach
  satisfies these. Note that once copied, sessions sit in Google, Microsoft
  or Apple's systems under the tutor's own account; the tutor contract and
  privacy policy should say tutors may only use this on a private, secured
  account (lawyer to check).

## 4. Research basis

- Predictable routines and reliable attendance matter for learning gains
  from tutoring: the EEF's tutoring guidance and Evidence for Learning's
  one-to-one tuition summary both point to **regular, consistent sessions**
  as a condition for the high impact of tutoring (around +5 months).
  Missed or late sessions break that. Putting sessions in the calendar a
  tutor already uses lowers the chance of a missed session.
- AERO's guidance on high-quality tutoring stresses **sessions scheduled
  regularly and protected**. A week view helps tutors protect that time
  and plan preparation across the week.
- Reducing admin load on teachers/tutors (AERO and EEF workload findings)
  frees time for preparation: one place to look instead of checking the app
  each day.

## 5. How it's built

- Migration `supabase/migrations/20261113200100_tutor_calendar.sql`:
  table `public.tutor_calendar_links` (one row per tutor, hash only);
  `public.reset_calendar_link()` and `public.remove_calendar_link()`
  (tutors with two-step sign-in only); `public.calendar_feed(token)` (open
  to calendar apps; the secret is the key; minimum columns).
- Tests: `supabase/tests/tutor_calendar.test.sql`.
- Feed address: `/api/calendar/<secret>.ics` (open in `src/lib/supabase/proxy.ts`
  because calendar apps can't sign in). Calendar file written by
  `src/lib/tutor-calendar.ts`.
- The weekly page uses the existing signed-in `list_sessions`, so tutors
  see exactly what the Sessions tab already shows them.
- Belongs to the scheduling module; it only reads `sessions`, never writes.

## 6. Open questions for Carla

- Should the feed stop while a tutor's child safety check has lapsed?
- **Decided (Carla, 15 Nov 2026): Teams links stay out of calendars.**
  CLG's Teams meetings let everyone with the link straight in, because
  tutors join as guests and couldn't admit a student from a waiting room
  (`src/lib/teams/graph.ts`). A tutor's own calendar is only as safe as
  their account, so the calendar entry says "Online – join from the CLG
  app" and links to the Weekly calendar page. Migration
  `20261117300200_calendar_no_teams_links.sql` removes the column from the
  feed.

## 7. Parents and students (Carla, 15 Nov 2026)

"Student and parent profiles should also get a similar calendar entry as
tutors do."

- **Weekly calendar** tab on the parent and student dashboards
  (`/dashboard/calendar?as=parent|student`): the same week view, showing a
  parent's children (child, subject, tutor's first name, place) or a
  student's own sessions, with **Join on Teams** for online sessions. Times
  are in the student's state's time zone.
- **Private calendar link** for each parent or student with their own login
  (`/api/calendar/family/<secret>.ics`). Shows the child's first name, the
  subject, the tutor's first name, the time and the place. No Teams links,
  surnames, notes or money. A child unlinked from a parent drops out of
  that parent's feed straight away; the link stops if the person loses the
  parent or student role.
- Separate table (`public.family_calendar_links`) and functions
  (`reset_family_calendar_link`, `remove_family_calendar_link`,
  `family_calendar_feed`) so tutor and family links can never open each
  other's feeds. Migration `20261117400100_family_calendar.sql`; tests
  `supabase/tests/scheduling_family_calendar.test.sql`.
- The same migration makes the tutors' feed leave out sessions while the
  tutor's checks for that student have lapsed, to match their Sessions list
  (Carla, 16 Nov 2026).
- Research: the EEF and Evidence for Learning tutoring evidence stresses
  regular, consistent attendance, and AERO's family engagement guidance
  stresses clear, regular communication with families. Putting sessions in
  the calendar a family already uses makes missed sessions less likely.
- Privacy: same rules as the tutors' link (APP 3, 6, 11; Children's Online
  Privacy Code; UK/EU data minimisation). Families may share their calendar
  with other family members; the page asks them to share only with family
  who should see these sessions.
