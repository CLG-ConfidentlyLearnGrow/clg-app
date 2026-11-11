# Scheduling and tutor matching

Requested by Carla, 2026-10-26. Full brief with Carla's decisions:
https://claude.ai/artifact/VKHnZFR36UFzbxvFi5jezV

Part 1: finding a time, booking, the tutor confirming, the weekly sessions,
cancelling and recording what happened. Part 2: away dates and the
waitlist. Part 3: tutor sign on and off. Part 4: reminders and notices in
the app. Part 5: school terms and renewing each term. Later parts: email
and text sending. Teams links are their own module (teams-links.md).

## What it's for

Replaces the "CLG Tutor Availability" spreadsheet and Jira. Matching is
automatic, like booking a doctor:

1. The family (or an admin, during the pilot) chooses the child, a subject
   they asked for, how long (1 hour minimum, half-hour steps), and where:
   online, at libraries they tick, or both. They can narrow by day and time.
2. The app shows only tutors who can take it:
   - cleared for the student's state (child safety checks verified and in date)
   - teach that subject at the student's year level
   - free then: inside their weekly availability and not already booked
   - under their maximum weekly hours
   - working that way (online, or at one of the family's libraries)
   - not at a different library that day (a tutor stays at one library a
     day; online sessions on a library day are fine)
3. The family picks a time. It's held for the tutor, "subject to tutor
   confirmation". The tutor has 48 hours to accept or decline. After that
   the request expires and the time is free again.
4. When the tutor accepts, they are assigned to the student (so they can
   open the student's record and progress), and every weekly session up to
   the booking's last date is created.
5. Families, tutors and admins can cancel a session before it starts, or
   stop a booking (all future sessions are cancelled). The app records who
   cancelled and when. Billing uses that for credits and pay.
6. After a session starts, the tutor records "completed" or "no-show". An
   admin can correct it.

7. **Away dates.** A tutor, or a family for their child, adds dates they
   can't make. Booked sessions on those dates are cancelled (recorded as
   cancelled by the tutor or the family, at the time the dates were added,
   so early notice gets the full credit). New bookings skip away dates.
8. **Waitlist.** When no tutor is free, the family can join the waitlist
   with what they searched for. Admins see everyone waiting, oldest first,
   how many times would now suit, and who has waited 4 weeks or more (time
   to check in). Booking that subject takes the child off the waitlist.

9. **Sign on and off.** From 30 minutes before a session, the tutor taps
   "Sign on". For a library session the phone asks once to share their
   location; the app checks it is within 300 m of the library and keeps
   only the result (at the library or not), never the location. Online,
   the time counts from the later of signing on and the booked start (a
   late tutor is paid for time worked). Sign-off is automatic at the booked
   end, every 15 minutes. If a session ran over or finished early, the
   tutor records the end time with a reason within a week, and an admin
   confirms it under "Times to check", which also lists sessions with no
   sign-on or a location check that didn't pass. Families are still charged
   the booked time.

10. **Reminders and notices.** Everyone involved (tutor, parents, and a
    student with their own login) gets a first reminder before each session
    (48 hr by default, each person can change it) and a final reminder 1 hr
    before. They also hear when a booking is requested, confirmed or
    declined, and when someone else cancels a session. Nothing arrives
    between 8pm and 8am Adelaide time; it waits until 8am. A final reminder
    for an early-morning session comes at 7:30pm the evening before.
    Notices show in the app now; email and text use the same notices once
    CLG switches them on.

11. **Next term.** CLG keeps each state's school term dates (South
    Australian government school dates for 2026 to 2028 are loaded; admins
    add or correct terms). Two weeks before a term ends (four weeks before
    the end of terms 1 and 3, when sport seasons change) the family is asked
    about each booking that ends that term: same time and tutor next term?
    sessions in the holidays? If they want a change, what (day and time,
    tutor, or both) and why. The same form takes feedback, with a separate
    tick to let CLG use it as a testimonial. "Same again" sends the tutor a
    request for next term at the same time, which they accept as usual (so
    the child safety and clash checks run again). A booking without holiday
    sessions gets no sessions between terms. Tutors don't see the answers,
    so families can be frank about wanting a change of tutor.

12. **Tutor availability each term.** A week before families are asked
    (3 weeks before a term ends; 5 weeks for terms 1 and 3), each tutor is
    asked whether their weekly availability is right for next term. They
    tap "No changes", or update it and tap "I've updated it". Admins see who
    hasn't answered (flagged after a week), weekly times removed since last
    term, and bookings that now fall outside a tutor's availability. A
    missed answer doesn't hide a tutor from bookings, and changing
    availability never changes booked sessions.

13. **Matching.** Tutors are matched on the level the student is working at
    in each subject (the family's "working level"), or their school year if
    none is given. This applies to finding times and to assigning a tutor.
    Families save **session places** for each child (online, and the
    libraries that suit), and searches start from them. Admins see a
    **Matching** tab: every subject a student asked for, by stage (needs a
    tutor, waitlist, tutor to confirm, assigned with no time, active), with
    days in that stage, oldest first, searchable and paged so it works for
    hundreds of students. Stages come from the records, so nobody moves
    cards by hand.

14. **CLG offers, both approve (Carla, 29 Oct 2026).** From the Matching
    tab an admin opens a student's subject. The app suggests the best
    tutor, time and place: the family's preferred days and times first,
    then tutors with learning-support experience, then times that join a
    tutor's other sessions. The admin sends it, or picks another option and
    says why (kept so repeated reasons can improve the suggestions). The
    tutor and the family are asked at the same time and have 48 hours. It
    shows "Waiting for confirmation" until both approve, then the sessions
    are made and everyone gets the details. If either says no, it returns
    to the Matching tab. A family booking for themselves still needs only
    the tutor.
15. **Preferred days and times.** Optional, saved with session places and
    clearly marked as a preference, not a guarantee, including a "during
    school hours" option. Offers use a preferred time when one is
    available, otherwise the closest available.

Home sessions can only be booked by an admin, for special circumstances.
Families never choose a tutor by gender or similar; requests go in the
note.

## What the evidence says

- **One-to-one tuition** has a high average impact (EEF Teaching and Learning
  Toolkit: about +5 months). The impact is larger when sessions are
  **regular, frequent and sustained**, and when the tutor knows the
  learner's needs. Evidence for Learning's summary of the Toolkit says the
  same for Australian schools.
  https://educationendowmentfoundation.org.uk/education-evidence/teaching-learning-toolkit/one-to-one-tuition
- **Consistency of tutor.** The EEF's National Tutoring Programme reviews
  and its guidance on making the best use of tutoring found that a stable
  tutor-learner relationship and good communication between tutor and
  school or family help tutoring work.
- **Short, regular sessions.** The Toolkit notes that short, regular
  sessions (about 30 minutes to an hour, 3 to 5 times a week, over 6 to 12
  weeks) give the best results in school interventions. CLG's 1-hour
  minimum and weekly bookings across a term fit this pattern.
- **Matching on need.** AERO's work on explicit teaching and tutoring
  stresses aligning support with what the learner is being taught in class.
  Matching on subject and year level, then attaching the curriculum when the
  tutor accepts, does this from the first session.

(EEF figures are the Toolkit's headline estimates. Check them again before
quoting externally.)

## How the design follows the evidence

- **Weekly bookings, not one-off sessions.** A booking repeats every week to
  a last date (up to about a year), so support is regular and sustained.
- **Same tutor kept.** The booking keeps one tutor. A change of tutor is a
  new booking.
- **Need first.** Students with learning needs on record see tutors with
  learning-support experience first. Other tutors are still offered.
- **Tutor wellbeing and pay.** Times that join onto a tutor's other sessions
  come first, so tutors get blocks of 2 hours or more (the casual minimum
  engagement in the Miscellaneous Award MA000104 and Post-Secondary Award
  MA000075). One library a day avoids unpaid travel between sessions.

Reminders follow the evidence on attendance: reminder messages reduce
missed appointments in health and education settings (for example the
Cochrane review of mobile phone reminders, Gurol-Urganci et al. 2013), and
EEF trials of texting parents found small attainment and attendance gains
(Texting Parents, 2016). Few messages, sent at sensible hours, keep parent
support light.

Asking before each term keeps support sustained, the condition under which
tutoring has most effect (EEF Toolkit, above), and keeps the same tutor
where the family is happy, which the National Tutoring Programme reviews
link to better outcomes. Asking why families want a change, and for
feedback each term, gives CLG the learner and parent voice that AERO and
the EEF's implementation guidance recommend for reviewing a programme.

Checking tutors' availability before families rebook protects the same
consistency: a family that books a time the tutor can no longer keep loses
the regular, stable sessions the evidence favours. Casual tutors may change
what they offer under the Miscellaneous and Post-Secondary Awards, so the
app shows changes to admins for a conversation rather than blocking them.

Matching on working level follows the evidence that tutoring works best
when it targets what the learner is ready for (EEF, one to one tuition;
AERO on explicit teaching and checking prior knowledge). A student a few
years behind in maths needs a tutor who teaches that level, whatever their
school year.

Asking the tutor and family together keeps the time to a first session
short, which the brief's measures treat as what families notice first,
and recording why suggestions are changed gives CLG the data to review the
process each term, as the NSSA implementation toolkit recommends.

For the pilot, CLG staff book every time and families approve what CLG
offers, rather than searching for themselves. Staff matching keeps the
learner's needs, working level and tutor fit at the centre (the same
reasons as above), and keeps parent support light. Families give
preferred days and times (a preference, not a guarantee) and study dates
under "Preferred times"; admins choose where sessions can happen. Tutors say for each available time whether
they can teach in person, online or both, so offers only include ways of
teaching the tutor has agreed to.

## How we'll know it works

- Time from request to confirmed booking (target: under 48 hours).
- Share of requests that expire or are declined.
- Sessions per booking before it ends (consistency).
- Cancellations by who cancelled, and no-shows.
- Tutor hours in blocks of 2 hours or more.
- No-show rate before and after reminders.
- Share of offers approved by both sides, and reasons suggestions were changed.
- Days from a subject being asked for to its first session (Matching tab).
- Share of tutors confirming availability before families are asked.
- Share of bookings renewed each term, and the reasons families give for a
  change.

## Privacy and child safety

- **Australian Privacy Principles (APP 3, 6, 11)**: only what's needed. A
  tutor offered a booking sees the student's first name, year level,
  subject, time, place and the family's note. The full record opens only
  once they accept and are assigned.
- **Access in the database (row level security)**: families see their own
  bookings and sessions; tutors see only theirs, with two-step login;
  admins see all. Bookings and sessions change only through checked
  functions. Tests: `supabase/tests/scheduling.test.sql`.
- **Child safety (Children and Young People (Safety) Act 2017 (SA), CLG's
  child safe policy)**: a tutor is offered only for students in states where
  their checks are verified and in date, and only once an admin has
  verified the parent link (under 18s). Sessions are online or at public
  libraries, not homes, unless an admin approves.
- **Children's Online Privacy Code (draft)**: no tracking of children's
  location. The family picks libraries; the app doesn't ask where they
  live.
- **Tutor location (APP 3, data minimisation; Surveillance Devices Act
  2016 (SA))**: one check at sign-on, only with the tutor's permission in
  the browser, compared on the server and thrown away. Only "at the
  library" or "not" is stored. Tutors can decline and still sign on; an
  admin then checks the time.
- **Feedback and testimonials (APP 6; Australian Consumer Law)**: feedback
  is used to improve CLG's support. It is shared as a testimonial only with
  a separate, unticked-by-default yes, and the app records that yes. Shared
  testimonials use a first name only and are never edited to change their
  meaning. Tutors don't see renewal answers.
- **Session places (APP 3)**: families pick libraries from a list; the app
  never asks for or stores a home address or phone location for matching.
  For the pilot, admins choose a child's places; families give preferred
  times only. Tutors don't see either.
- **Records**: bookings and sessions are deleted with the student under the
  retention rules. Billing keeps its own copy of what it invoices (7 years).
- **Overdue payments**: when billing marks a family as paused, they can't
  book and tutors can't accept new requests from them.

## Changes, 2 Nov 2026

See [app-changes-2-nov-2026.md](app-changes-2-nov-2026.md) for the full brief.

- Quiet hours are 9pm to 6am. Notices are in the app only.
- Each student follows SA government terms, SA private terms (Term 2 a week
  shorter) or their own dates; each student's last day of Term 4 is
  confirmed. Families are asked about next term 3 weeks before their study
  period ends; tutors check availability 4 weeks before.
- Offers that need both the tutor and the family are open 3 days, with
  reminders after 2 days. Requests to a tutor still have 48 hours.
- A tutor's away dates cancel sessions after 2 hours; families and CLG are
  told politely, the tutor can offer other times, and families can ask for
  another time or tutor.
- New: requests for extra or one-off sessions, public holiday weeks with a
  skip option, blocking, preferred parts of the day, library confirmation
  and opening hours, and home or school sessions booked by CLG only.
- The waitlist already lists everyone, longest wait first.

## The Matching tab, 3 Nov 2026

Carla found matching "very clunky": it was split between the admin page
("Assign a tutor") and a Sessions sub-tab, with a long drop-down and a plain
tutor list. Her answers to the matching questions (3 Nov 2026) set the
design.

**What it does.** A Matching tab (top bar and admin menu) for owner,
operations and support admins:

- A queue of student subjects by stage, longest wait first, filtered by
  year level, state and a search box, with a "Next student" link.
- One student's full picture: school year and working level, other
  subjects, goal, learning needs, the family's tutor preferences note,
  places, preferred times, siblings and past tutors.
- A ranked shortlist with the reasons each tutor fits. Only tutors who
  teach the subject at the level the student is working at are listed.
  Best fit order (Carla, 10 Nov 2026): a tutor who already teaches a
  sibling, then spare hours (room for this session), then a place that
  suits (one of the student's libraries, or online), then a time that suits
  (preferred times first). The top tutor's best time is ready
  to offer in one click; choosing another records why.
- A tutor at their weekly maximum still shows, with a note to ask them
  first if they're the only option. The database never books a tutor past
  their maximum. Checks due to expire within 30 days are flagged. Pay rates
  are not shown.
- Tutors who don't fit, and why (checks not current for the state, doesn't
  teach the level, or can't be matched with this student).
- A Gaps view: subjects and levels students are waiting for that no tutor
  with current checks teaches, by state, to show who to recruit next.

**Evidence.** The EEF's guidance on effective tutoring and its Teaching and
Learning Toolkit (one to one tuition) find tutoring works best when it is
regular, with a consistent tutor, and pitched at the learner's current
level. Ranking keeps families with a tutor they already trust (siblings),
offers times that fit so sessions can stay regular, and matches on working
level. AERO's guidance on explicit teaching makes the same point about
building from what the learner already knows. Recording why suggestions are
changed, and the gap report, give CLG the data to review the process each
term (NSSA implementation toolkit).

**Legal.**

- *Equal opportunity:* families write tutor preferences as a note. There
  are no filters on protected attributes such as sex, age, religion or race
  (Equal Opportunity Act 1984 (SA), Sex Discrimination Act 1984 (Cth),
  Racial Discrimination Act 1975 (Cth), Age Discrimination Act 2004 (Cth)).
  The form asks families not to ask for these.
- *Privacy (APP 3, APP 6) and child safety:* before accepting an offer, a
  tutor sees only the student's first name, year level, subject, goal,
  place and time (`offer_card`). Learning needs, documents, progress and
  contact details open only once there is a current assignment, which is
  made when the tutor and family have both accepted. The database enforces
  this (`private.is_tutor_of`), and `scheduling_offer_matching_tab.test.sql`
  tests it. Tutors are shortlisted only for states where their WWCC and
  RRHAN-EC are current.
- The tutor preferences note is seen by the family and CLG admins only,
  never by tutors.
- *UK and EU later:* the same data-minimising approach fits UK GDPR and the
  EU GDPR (Article 5, data minimisation) and the UK Equality Act 2010.

## Changing the time and place on an offer, 11 Nov 2026

Carla asked to be able to change the time and place before offering a tutor.

- Each tutor on the Matching card has "Offer this tutor". It starts on the
  best time, and a list shows all of that tutor's other suitable times and
  places (preferred times are marked).
- "Another time or place" lets an admin type any day, start time, length and
  place (online or a confirmed library), even outside the tutor's
  availability. The admin is reminded to check with the tutor first.
- Anything but the app's suggestion asks for a reason, which feeds the
  "why a different choice" report (as before).
- The tutor and the family still both approve before anything is booked.
- For another time or place the database still checks the tutor is active,
  cleared for the student's state, teaches the subject at the student's
  level, isn't blocked from this student, has room under their weekly
  maximum and has no other booking at that time (offer_other_time).

Research: keeping an admin in the loop for exceptions, with a recorded
reason, matches the brief's "people decide, the app suggests" approach and
lets CLG see where the suggestions fall short (EEF guidance on using data
to improve implementation). No new personal information is collected.


## Declined offers, 11 Nov 2026

Carla found that a declined session sent CLG no notice, and that the
student's waiting time restarted after a decline.

- When a tutor or family declines a session time, CLG's owner and
  operations admins get a notice under Schedule. It says who declined, gives
  any reason, and points to Matching.
- A student who was never taken on keeps their waiting time. Only sessions
  that were confirmed (went ahead) restart the count when they finish.
  Declined or expired offers don't.
- Tutors can't book sessions themselves. Booking is open to CLG admins,
  parents (for their own children) and students with their own login.

Research: tracking how long each learner has waited, without resets, keeps
the queue fair and shows where CLG needs more tutors (the brief's "longest
waiting first" rule). No new personal information is collected.

## Booking end dates, 11 Nov 2026

Carla asked that end dates are never guessed, that the student's term dates
are shown so the right end can be picked, and that families say how long
they want to book for as its own step, separate from preferred times.

- A "How long to book" tab under Sessions asks each family, for each child:
  the last date for sessions (from today, up to a year ahead), whether
  sessions go ahead in school holidays, and whether they go ahead on public
  holidays. All three are needed. Families are told they can change it
  later.
- CLG admins can change it for a family (Matching shows it, with a Change
  link).
- When CLG offers a time (Matching, or Book a session), the last date is
  the family's date. If the family hasn't answered, it is left blank for the
  admin to fill in. The app no longer fills in 10 weeks.
- A new booking copies the family's holiday answers (skip_holidays and
  skip_public_holidays). Renewals keep their own choice.
- Beside every last-date box there is a list of the student's term dates
  (from their school calendar, the private school calendar or their own
  study periods), so the end of a term can be picked in one step.
- Only the family, the student (with their own login) and CLG admins can
  see a student's term dates (student_term_dates) or set the booking length
  (set_booking_length).

Research: matching tutoring blocks to school terms supports regular,
sustained sessions, which the EEF and Evidence for Learning toolkits link
to the strongest tutoring gains (EEF Teaching and Learning Toolkit, "Small
group tuition" and "One to one tuition"). Under the Australian Consumer Law
the family should know what they are booking (how long, and which weeks)
before agreeing; asking them directly does that. No new personal
information is collected beyond a date and two yes/no answers.

## A place for each availability time, 11 Nov 2026

Carla asked that tutors give a place for each weekly time: online, one
library, or online and one library. Never several libraries in one time.

- The tutor's "Add time" form has an Online tick and a Library list (one
  library). For another library on another day, they add another time.
- The list shows libraries CLG has confirmed, plus any the tutor suggested
  that CLG is still checking. The database refuses any other library.
- Choosing a library for a time also adds it to the tutor's libraries under
  "Where you teach", so lists of where each tutor works stay right.
- Finding times offers a time only at its own library. Older times with "in
  person" ticked but no library still use any of the tutor's libraries until
  the tutor re-adds them. Where a tutor had only one library, it was filled
  in for them.
- The term availability check compares each booking with its own time's
  library.

Research: giving each slot a fixed place cuts travel between sites and
keeps sessions regular, which supports the consistent, scheduled tutoring
the EEF links to better outcomes. No new personal information is collected.

## Loading SA libraries, and addresses on suggestions, 11 Nov 2026

Carla asked to load the SA Government list of libraries. That data set
("Public Libraries location map") only covers the City of Onkaparinga, and
no statewide file is published, so the list comes from OpenStreetMap
instead (free, Open Database Licence; the credit is shown on the Libraries
page).

- Schedule > Libraries has "Load SA libraries". It adds every SA library
  OpenStreetMap knows that isn't listed yet, with its address and map
  location (used for the sign-on check). University, TAFE, school and other
  non-public libraries are left out by name; admins can hide any others.
- Libraries already listed keep their details; only a missing address or
  map location is filled in. Loading again adds nothing twice.
- Loaded libraries can be chosen straight away. Opening hours are asked for
  only once a tutor or family picks a library.
- Admins can still add one library by hand (Schedule > Libraries > Add a
  library).
- Tutors suggesting a library must give its street address as well as its
  name. CLG still confirms it.

Legal: library names and addresses are public business information, not
personal information. OpenStreetMap's licence needs the credit line.
