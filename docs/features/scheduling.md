# Scheduling and tutor matching

Requested by Carla, 2026-10-26. Full brief with Carla's decisions:
https://claude.ai/artifact/VKHnZFR36UFzbxvFi5jezV

This is the first part of the module: finding a time, booking, the tutor
confirming, the weekly sessions, cancelling and recording what happened.
Later parts: away dates, waitlist, reminders, Teams links, tutor sign on and
off, renewal each term.

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

## How we'll know it works

- Time from request to confirmed booking (target: under 48 hours).
- Share of requests that expire or are declined.
- Sessions per booking before it ends (consistency).
- Cancellations by who cancelled, and no-shows.
- Tutor hours in blocks of 2 hours or more.

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
- **Records**: bookings and sessions are deleted with the student under the
  retention rules. Billing keeps its own copy of what it invoices (7 years).
- **Overdue payments**: when billing marks a family as paused, they can't
  book and tutors can't accept new requests from them.
