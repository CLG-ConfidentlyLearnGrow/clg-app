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
  Only the family and admins see a child's places.
- **Records**: bookings and sessions are deleted with the student under the
  retention rules. Billing keeps its own copy of what it invoices (7 years).
- **Overdue payments**: when billing marks a family as paused, they can't
  book and tutors can't accept new requests from them.
