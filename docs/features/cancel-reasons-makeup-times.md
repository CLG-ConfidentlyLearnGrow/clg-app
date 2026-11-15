# Cancel reasons and make-up times

Asked for by Carla, 16 Nov 2026: "When tutors and clients cancel a tutor
session, there needs to be a space for a reason (maybe a drop down of sick,
away, ... etc). This also needs to give a space to give two alternative
session times for that week."

Part of the scheduling module. Migration
`supabase/migrations/20261118100100_cancel_reasons_makeup_times.sql`; tests in
`supabase/tests/scheduling_makeup_times.test.sql`.

## What it's for

A cancelled session is a lost hour of learning unless it is made up. Today a
cancel only records who cancelled and when (for credits and pay), with an
optional free-text reason. Nobody is prompted to rebook, so the gap depends
on CLG chasing it. This feature makes the person cancelling offer the fix at
the moment they cancel, and lets the other side say yes with one tap.

## What the evidence says

- **One to one tuition** (EEF Teaching and Learning Toolkit, +5 months):
  impact is highest when sessions are regular and sustained, and the EEF's
  tutoring guidance stresses consistent scheduling and attendance. A missed
  session made up in the same week keeps the weekly rhythm and the planned
  sequence of learning.
- **Dosage and consistency** (Stanford National Student Support Accelerator,
  high-impact tutoring): the benefits depend on students actually receiving
  the planned number of sessions with a consistent tutor. Programs that
  reschedule missed sessions quickly keep dosage up. The make-up is with the
  same tutor, same place, same length.
- **Parental engagement** (EEF, +4 months): the approaches that work are
  specific and easy to act on. A parent gets two concrete times to pick from,
  in the app, rather than an open "when suits you?" message.
- **Few clear choices** (choice research, e.g. Iyengar and Lepper 2000, cited
  from memory): a small number of concrete options gets answered faster than
  an open question. Two times is enough to fit most weeks without a back and
  forth; "neither works" with a reason hands it to CLG.
- **Reasons as data** (AERO's guidance on using attendance data): knowing
  *why* sessions are missed (illness, school events, clashes) shows patterns
  CLG can act on, such as school event weeks or a student who is often
  unwell. A short fixed list gives clean data; "Other" keeps room for the
  unusual.

## How it works

1. **Cancel** (tutor, parent, student 16+, or CLG front desk on their behalf):
   the Cancel form on Sessions now asks for
   - a **reason** from a drop-down: Sick or unwell, Away or travelling,
     School or uni event, Family matter, Clashes with something else, Other.
     "Other" needs a few words; for the rest the words are optional;
   - **two other times in the same week** (Monday to Sunday): a day and a
     start time each, on the quarter hour (sessions start at 15-minute
     steps), at least 2 hr from now. Same length and same place as the
     cancelled session. The database refuses a time that clashes with the
     tutor's or student's other sessions, or falls on an away date;
   - or a tick: **"No other time works this week"**, and CLG's admins are
     asked to arrange a make-up.
2. **Who picks**: if the family cancelled, the tutor picks. If the tutor (or
   CLG) cancelled, the family picks. They are told straight away in the
   "Session cancelled" notice, which lists the two times, and a "Pick a
   make-up time" card sits at the top of their Sessions overview (with a
   number on the Overview tab).
3. **Pick or say neither**: picking a time books the make-up session
   immediately (linked to the cancelled one) and tells everyone. "Neither
   works" needs a reason; the side that offered and CLG's admins are told.
4. **CLG hears at each step** (owner and operations admins): the cancel with
   its reason, the pick or "neither", and, if both times pass with no answer,
   a "Make-up time not picked" notice (checked every 15 minutes).
5. CLG front desk can pick on either side's behalf (for a phone call).
   Admins see every offer, and where it's up to, in a "Make-up times" card.

Stopping a whole booking is unchanged (reason optional, no make-up times).

## Money and pay

Nothing changes in billing. The cancelled session gets its credit by the
usual rules (family: more than 24 hr full credit, 24 to 2 hr 50%, under 2 hr
none; tutor or CLG cancels: full credit). The make-up is a new session that
is invoiced and paid like any other. So a family that cancels late pays for
the make-up as well; if Carla wants make-ups after a family's late cancel to
use the lost credit instead, that is a billing change for later. The
tutor's pay for the make-up follows the award as for any session
(including the 2-hr minimum engagement per attendance).

## Privacy, child safety and the law

- **Data minimisation (Privacy Act 1988, APP 3; Children's Online Privacy
  Code)**: the reason list says "Sick or unwell" without asking what's wrong.
  The note box tells people it is shared with the tutor, family and CLG and
  asks them not to include health details. Health information is sensitive
  information under the Privacy Act, so we avoid collecting it.
- **Tutor need-to-know**: tutors see make-up offers only for their own
  students, only while their checks for that student are in date, and with
  the student's first name only. Other tutors and other parents see nothing
  (row level security on `session_makeup_offers`, and the list function).
- **Child safety (SA Child Safe Environments; CLG's child safe policy)**: the
  times are agreed inside the app, never by private messages between tutor
  and family, and CLG sees every step.
- **Australian Consumer Law**: credits follow the published terms
  unchanged; the make-up is optional for both sides ("neither works").
- **UK and EU**: the same minimisation applies under UK GDPR / GDPR (no
  special category data asked for).
- Every change is in the audit log. All changes go through database
  functions; nobody writes the table directly.

## Database

- `sessions.cancel_reason_kind` (the reason picked) and `sessions.makeup_for`
  (on a make-up session, the session it replaces).
- `session_makeup_offers`: one row per cancelled session, with the two times,
  who picks, and where it's up to (waiting, picked, declined, expired,
  none_offered).
- `cancel_session_with_times(...)`: cancels with a reason and the times.
- `answer_makeup_times(offer, choice, note)`: 1 or 2 books that time; 0 is
  "neither" (note needed).
- `list_makeup_offers()`: what the viewer may see.
- `cancel_session` now refuses a cancel with no reason (edited in place).
- `notice_on_cancel` now lists the times and asks the picking side to pick.
- Job `clg-makeup-times-expire` every 15 minutes.

## How we'll know it works

- share of cancelled sessions that get a make-up booked within the week
- how often "neither works" or "no other time" is used, and by which side
- reasons by term (e.g. school event weeks), to plan around them

## Not done (could come later)

- Make-up times at a different place (online instead of the library).
- Checking the tutor's weekly availability hours when a family offers times
  (the tutor can say neither works).
- The concerning-words scan reads certain tables; adding the cancel note and
  the "neither" note to it is a change for the safety module.
