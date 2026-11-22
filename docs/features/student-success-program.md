# Student Success Program

Carla, 22 Nov 2026. From her notes on Emma's job proposal: "need to have a space where can click or check off or something if a student is part of the Student Success Program ... then it sets up their student and/or family profile up accordingly." What it sets up: "Study plan, term reviews, a program label, book till date range (number of sessions) - these are top priority for matching, as they have already paid the $500 deposit to secure their place."

## What it is for

Families in the Student Success Program pay a $500 deposit to secure their child's place for a planned run of sessions. The program bundles the parts of CLG that the evidence says matter most for steady progress: a written plan, regular reviews against it, and a consistent tutor found quickly.

## What the evidence says

- **One to one tuition** (EEF Teaching and Learning Toolkit, about +5 months): works best when sessions are regular, sustained over a planned period, and linked to what the student is learning. A planned number of sessions and a book-until date make the run regular and sustained.
- **Feedback** (EEF, about +6 months) and **metacognition and self-regulation** (EEF, about +7 months): students gain most when they know where they are going, how they are going, and what to do next. The study plan sets the goals; the term review (included at no charge) checks progress against them each term.
- **Parental engagement** (EEF, about +4 months): personalised updates about a child's progress work better than general ones. The term review is written by the student's own tutor and checked by CLG.
- **Tutor consistency** (Evidence for Learning and AERO guidance on high-impact tutoring, drawing on the Stanford National Student Support Accelerator): a stable relationship with one tutor and quick matching reduce lost learning time. Program students go first in Matching.

## How the design follows it

- **One tick box**, in **Families > Change a student's details** (owner and Operations admins). It records sessions planned, the book-until date, when the deposit was paid, and a note.
- **Study plan**: the student gets the study plan add-on (noted "Student Success Program"). Removing them ends only that add-on, not one given for another reason.
- **Term reviews**: each term review offer for a program student is accepted straight away at no charge, the tutor's draft is made, and the family is told it is included. (Term review offers only happen while the term review price item is active.)
- **Label and priority**: a violet "Student Success Program" label in Matching, and program students are listed first in the queue and in "Fill a tutor's times", then longest waiting first as before.
- **Book until**: saved through scheduling's own `set_booking_length`, with the school holiday and public holiday answers, so the program module never writes scheduling's tables. The date must be within a year (scheduling's rule).

## How we will know it works

- days from deposit to first session for program students, against everyone else
- share of program students with a term review sent each term
- share of program students who finish their planned sessions, and who re-enrol

## Privacy, child safety and legal notes

- **Privacy Act 1988 (APPs 3, 6 and 11) and the Children's Online Privacy Code**: the program record holds only what CLG needs (sessions, dates, a short note). Its note box is for admin notes only and should not hold health or diagnosis details. Access is limited in the database: front-desk admins, the student's family and the student's tutors can see that a student is in the program; only owner and Operations admins can change it. Every change is in the audit log, and the record is deleted with the student.
- **Australian Consumer Law**: the deposit and what the program includes are set out in CLG's terms. The app records the date the deposit was paid but does not take or refund money; refunds follow CLG's terms and the consumer guarantees.
- **UK and EU (GDPR)**: the same data minimisation and access rules apply if CLG expands.

## Technical

- Migration `20261124710900_student_success_program.sql` (run after `20261124710800_policy_versions_read_again.sql`).
- Table `public.ssp_enrolments`; functions `public.ssp_enrol`, `public.ssp_leave`, `private.ssp_member`.
- Changes `private.queue_term_reviews`, `public.matching_queue` and `public.matching_tutor_fill` in place.
- Tests: `supabase/tests/student_success_program.test.sql`.
