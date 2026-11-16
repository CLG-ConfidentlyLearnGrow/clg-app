# Book again: renewals follow each student's book-till date

Asked for by Carla, 16 Nov 2026: renewals should run "off the student's own
book-till date", not the end of the school term. When a student's
book-till date gets close, the parent sets a new book-till date and ticks
the school holiday and public holiday questions again.

Scheduling module. Migration
`supabase/migrations/20261119700200_renewals_book_till.sql`; tests in
`supabase/tests/scheduling_terms_book_till.test.sql` (with the older
`scheduling_terms.test.sql` and `scheduling_terms_study_periods.test.sql`
updated to the new rule).

## What it is for

Families already choose how long to book for (**How long to book**: a
book-till date, and whether sessions go ahead in school holidays and on
public holidays). Until now the renewal question ignored that date. It was
sent 3 weeks before the end of the school term that held the booking's last
date, and "same again" booked to the end of next term. A family whose
book-till date fell in the middle of a term could be asked too late, or not
at all, and their sessions could simply stop.

## What the evidence says

- **Tutoring works best when it is sustained and regular** (EEF Teaching and
  Learning Toolkit, one to one tuition, about +5 months; Evidence for
  Learning's Australian edition of the same toolkit). Gaps between bookings
  break that regularity. Asking 3 weeks before the family's own end date
  gives time to renew with no gap.
- **Attendance and continuity matter** (AERO, *Attendance matters*). A
  booking that ends without warning is a missed run of sessions. A question
  tied to the date the family actually chose means nobody is surprised.
- **Parental engagement** (EEF, *Working with parents to support children's
  learning*). Clear, timely, simple requests to parents work better than
  vague ones. The question asks for three plain things: a new date, school
  holidays yes or no, public holidays yes or no.
- **Planning around the learner, not the calendar** (AERO, tailored
  teaching). Many CLG learners do not follow the school term (tertiary
  students, holiday intensives, families who stop for sport seasons). Their
  own date is the right trigger.

## How it works

1. Each morning the app looks at every confirmed booking that has not
   finished. The date the sessions stop is the student's book-till date, or
   the booking's own last date if that comes first (or if no book-till date
   was ever set, as for some older bookings).
2. 3 weeks before that date, the parents (and the student, if they have
   their own login) get a notice called **Book again?**. Each booking is
   asked once. The tutor is not asked and does not see the answers (a
   family may ask for a different tutor).
3. In **Sessions**, **Book again**, the family answers:
   - same day, time and tutor again, or something different (and what, and
     why);
   - a new book-till date (after the last booked session, and within a
     year), with the student's term dates listed to pick from;
   - sessions during school holidays, yes or no;
   - sessions on public holidays, yes or no.
4. The new date and both holiday answers are saved as the student's **How
   long to book** answers, so any new booking CLG offers uses them.
5. "Same again" sends the tutor a request for the same day, time, place and
   length, from the next session day after the last session up to the new
   book-till date. The tutor still confirms it, and the usual checks apply
   (paused family, clashes, the tutor's summary time).
6. "Something different" is recorded for CLG to arrange. No request is sent.
7. Older questions about a school term that are still unanswered can be
   answered the same way.

The section was called **Next term**. It is now **Book again**, because the
question no longer follows the term. The App guides (parent, student and
admin) and the admin app tour were updated to match.

## Legal rules it touches

- **Privacy Act 1988, APP 3 and APP 6; Children's Online Privacy Code.** No
  new personal information is collected: the book-till date and holiday
  answers were already held for each student. Access stays in the database:
  only the family (and a student 16+ who books for themselves) can answer,
  and only the family and CLG admins can see the answers. Tutors cannot.
- **Australian Consumer Law (unfair contract terms, consumer guarantees).**
  Families are asked before a booking runs on, and "same again" still needs
  the tutor's confirmation and the family's normal billing terms. Nothing
  renews without the family choosing a new date.
- **Fair Work (tutor hours).** The tutor still has to accept the new
  booking, so nobody is booked past their hours without agreeing.
- **UK and EU (later).** The same design fits UK GDPR and the Age Appropriate
  Design Code: no new data, clear choices, and parents in control.

## Not changed

- Tutors are still asked to check their availability 4 weeks before each
  term ends.
- The daily job keeps its name and time (9:30am Adelaide).
