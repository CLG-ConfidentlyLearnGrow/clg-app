# App changes from Carla's notes, 2 Nov 2026

Requested by Carla on 2 Nov 2026. This brief covers the new parts (study
periods, requests and public holidays, blocking, libraries with opening
hours, leaving reasons) and lists the changes to existing features. Each
existing feature's brief has a short "Changes, 2 Nov 2026" note too.

## What it's for

- **Fewer emails, calmer evenings.** Families and tutors get notices in the
  app only. Nothing arrives between 9pm and 6am.
- **The right term dates for each student.** SA government schools, SA
  private schools (an extra week off between Terms 2 and 3) or the
  student's own dates (university, TAFE). Each student's last day of
  Term 4 is confirmed, because it changes by school and year level.
- **Earlier next-term planning.** Families are asked about next term
  3 weeks before their study period ends; tutors check their availability
  4 weeks before.
- **Fairer offers.** An offer that needs both the tutor and the family is
  open for 3 days. After 2 days, whoever hasn't approved gets a reminder,
  and the side that has approved is told it's waiting on the other.
- **Away dates without surprises.** A tutor's away dates cancel sessions
  2 hours after they're saved, so mistakes can be fixed. Families and CLG
  are told politely; the tutor can offer other times; the family can ask
  for another time or a different tutor.
- **One-off sessions.** Families can ask for an extra session before a test
  or exam, or a one-off in a public holiday week. Public holiday weeks are
  highlighted, and a booking can skip public holidays.
- **Safe matches.** A tutor can block a student, or a family a tutor. A
  reason is required, CLG follows up with the person who blocked, the other
  person isn't told, and the app stops suggesting the match.
- **Libraries CLG trusts.** Tutors can suggest a library; CLG confirms it
  and adds its opening hours. Sessions are only offered at confirmed
  libraries, inside opening hours. Home and school sessions are booked by
  CLG only.
- **Up-to-date checks.** Tutors upload a certificate and its done or expiry
  date. Reminders go 6 and 2 weeks before a check expires. RRHAN-EC is
  required in every state.
- **Learning from people who leave.** Admins record why a family or tutor
  left, and for happy families, whether a testimonial or review was asked.
- **Preferences, clearly not promises.** Families choose preferred days and
  parts of the day (morning, middle of the day, afternoon, evening), with a
  clear note that these may not be met.

## What the evidence says

- **One to one tuition** (+5 months, EEF Teaching and Learning Toolkit;
  Evidence for Learning's Australian version agrees): the effect depends on
  sessions being regular and consistent with classroom learning. Matching
  terms to each student's real school calendar, and asking about next term
  earlier, protects that regularity across the holidays.
  https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/one-to-one-tuition
- **Attendance and continuity** (AERO, "Tackling the attendance problem",
  2024): missed weeks add up, and routines help. Public holiday weeks are
  highlighted and a one-off can replace the missed session; away dates
  give families a way to ask for cover.
- **Extra sessions before a test**: EEF's guidance on tuition is that it
  works best when targeted at a specific need. A short, focused session
  before an assessment is that kind of targeted support. (Judgement, not a
  separate study.)
- **Feedback** (+6 months, EEF): written feedback works when it comes from
  the person who knows the learner. Term reviews stay written by the
  tutor, and are now an opt-in paid extra.
- **Parental engagement** (+4 months, EEF): personalised, two-way
  communication works; frequent generic messages don't. That is one
  reason the monthly summary (written by the app) was removed.
- **Relationships** (EEF, "Making a difference with effective tutoring",
  2021): the tutor and student relationship matters. When a match isn't
  working, the blocking tool ends it quietly, and CLG's follow-up helps the
  next match go better.

## How the design follows the evidence

- Each student has one study period: public, private or own dates. Private
  terms copy the public dates with Term 2 ending a week earlier. Term 4
  uses the student's own last day where known. Renewals, holiday skipping
  and term reviews all use the student's dates.
- Admins see a "Study dates to check" list: tertiary students with no dates
  and school students whose last day of Term 4 isn't confirmed.
- Requests are listed for the student's tutor and CLG. Either can offer a
  one-off time; the family approves it as usual. An extra session must be
  before the event.
- Blocks hide the pair from times, matching and booking. Existing sessions
  aren't changed until CLG has talked with the person.
- Library opening hours are checked when times are found and when a
  one-off is offered. A confirmed library with no hours yet is treated as
  open (CLG is shown "opening hours missing").

## How we'll know it works

- share of renewals answered before the study period ends
- number of offers that expire without both sides approving
- requests made and booked; public holiday one-offs booked
- blocks followed up within a week
- tutor checks that lapse (should be none)
- leaving reasons over time, and share of happy families asked for a review

## Privacy and child safety

- **Australian Privacy Principles.** APP 3 (collect only what's needed):
  a block reason and a leaving reason are short free text, seen only by
  admins (and the blocker for their own block). APP 11 (security): every
  rule is in the database with row level security; every change is in the
  audit log. The OAIC's Children's Online Privacy Code (due by
  December 2026) will likely expect the least data and the most privacy by
  default for children: fewer emails means less children's information
  leaving the app.
- **Spam Act 2003.** Notification emails are gone. Sign-in and password
  emails, security alerts to the owner, and emergency access emails are
  still sent (they are needed for the account to work and stay safe).
- **Child safety (SA Children and Young People (Safety) Act 2017, Child
  Safe Environments).** RRHAN-EC is required for tutors in every state,
  and checks expire with reminders. Sessions happen online, at confirmed
  public libraries inside opening hours, or (arranged by CLG only) at home
  or school. A tutor or family can end a match safely and quietly; CLG
  follows up.
- **Fair Work.** Admin hours are due the day after the pay week ends, but
  late hours can still be logged (people must be paid for time worked).
  Late entries are flagged for the approving admin.
- **GST.** Drafting at $90 per hour (school) and $110 per hour (tertiary)
  is set up GST-free, as Carla asked. Please confirm with CLG's accountant
  once CLG registers for GST.
- **AI tools.** The term review form tells tutors to write it themselves
  and not put any student information into AI tools (APP 6 and APP 8:
  using or sending children's information to an overseas AI service
  without consent).
- **UK and EU later.** Silent blocking and leaving reasons are "legitimate
  interest" records under UK and EU GDPR; keep them short and delete them
  with the family or tutor's other records.

## Where it lives

- `20261103000100_app_notices_only.sql`: quiet hours, no notice emails.
- `20261103000200_emergency_access_24_hours.sql`
- `20261103000300_scheduling_study_periods.sql`
- `20261103000400_scheduling_requests_and_holidays.sql`
- `20261103000500_scheduling_blocks_and_libraries.sql`
- `20261103000600_tutor_checks_reminders.sql`
- `20261103000700_leaving_prices_hours.sql`
- `20261103000800_progress_term_review_add_on.sql`
- Tests: `scheduling_terms_study_periods`, `scheduling_requests`,
  `tutor_checks_reminders`, `leaving_records`, plus updates to existing
  tests in `supabase/tests`.
- Screens: Schedule (Requests, Blocks, Session places, Next term,
  Libraries, Away dates), Admin (Leaving), My pay, Billing, the progress
  page's term review form.

## Not built (yet)

- The $50 public holiday loading isn't added to invoices automatically.
- Drafting isn't invoiced automatically; add it to an invoice by hand.
- Term reviews start "off" until Carla sets a price and switches the add-on
  to paid.
- Screenshots for the how-to guides need the app running with test data.
