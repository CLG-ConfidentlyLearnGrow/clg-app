# Change tutor on booked sessions

Asked for by Carla on 15 Nov 2026, as a follow-on to urgent re-matching (see `confidential-worker-flag.md`, section 5). This feature belongs to the scheduling module.

## 1. What it's for

Sometimes a student needs a new tutor while they still have sessions booked, and often already paid for. That can happen when a tutor leaves CLG, cuts their hours, gets sick for a long stretch, or a family asks for a change. It also happens when a match is ended because of a child safety concern.

Before this feature, the only way was to cancel the sessions and book again. That broke the link between each session and the invoice it was paid on. Paid sessions then showed as unpaid, and the family had to approve new times.

Now a matching admin (owner, operations or support) can move a student's upcoming sessions in one subject to another tutor, from a chosen date. The sessions stay the same (same times, places and Teams links). Only the tutor changes.

## 2. What the evidence and the rules say

- **Continuity and the tutor relationship.** The EEF's tutoring guidance ("Making a Difference with Effective Tutoring", 2021) and its Teaching and Learning Toolkit entry on one-to-one tuition stress regular sessions and a tutor who knows the learner's needs. Evidence for Learning's Australian version of the Toolkit says the same. AERO's guidance on high-quality tutoring also points to sessions that are frequent, consistent, and aligned with what the learner is working on. So the design avoids gaps between tutors: the same booked times carry on without a break. It also tells the new tutor to read the student's notes before the first session. The new tutor is matched straight away, so they can read the notes as soon as the change is made.
- **Information sharing and handover.** The National Principles for Child Safe Organisations (Principle 4, "Families and communities are informed and involved") support telling families promptly about changes to who works with their child. So the family gets a notice naming the new tutor straight away.
- **Need to know (Privacy Act, APP 6 and APP 11).** Only the people who need a student's information should have it. The old tutor's match for that subject ends the day before the change, so they lose access. The new tutor gains access only from the day they're matched. A safety reason is never shown to the family or either tutor. The reason box tells admins not to write one.
- **Consumer law (Australian Consumer Law, consumer guarantees for services).** Services that are paid for must still be supplied with due care and within a reasonable time. Moving the paid sessions to a new tutor at the same times keeps that promise. A credit would only be needed if a session can't go ahead. The family terms already cover credits.
- **Staff pay (Fair Work).** Sessions that move are paid to the tutor who actually teaches them, because pay is worked out from each session's tutor. The old tutor's guaranteed hours top-up (part-time staff) still works as before.
- **Matching rules CLG already uses.** The new tutor must meet every rule an ordinary match does. They must hold in-date checks for the student's state (WWCC, RRHAN-EC), teach the subject at the student's level, and be free at those times. For library sessions they must teach at that library. They must stay within their most hours per week, and they can't be someone blocked from the student. That includes a match ended from a child safety concern.

## 3. How the design follows this

- **Where.** A new "Change tutor" page under Sessions, for matching admins with two-step sign-in. It's linked from the Sessions page and from the red "Urgent: needs a new tutor" box on the Matching page.
- **Steps.** Pick the student, current tutor and subject. Choose the change date. The page then lists every tutor who could take over, with anything that would stop the move: clashing sessions, a library they don't teach at, or going past their hours. Tutors who already teach a brother or sister show first among the free ones. The admin then picks one, gives a short reason, and chooses whether to tell the old tutor.
- **What moves.** Every upcoming session from the change date. A weekly booking that has already started is split. The old part ends the day before, and a new booking with the new tutor runs to the same end date. It's marked as carrying on the old booking, so "next term" offers and the matching reports treat it as the same booking. A booking request still waiting for the old tutor goes to the new tutor, who has 48 hours to answer.
- **Invoices.** Nothing in billing changes. Invoice lines point at the same sessions, so paid sessions stay paid.
- **Reminders.** Reminders not yet sent for the moved sessions are withdrawn. They're made again within 15 minutes with the new tutor's name.
- **Notices.** The new tutor gets "Sessions added". The family gets "New tutor" with the new tutor's name. The old tutor gets "Sessions moved" ("have moved to another CLG tutor. You don't need to do anything"), with no reason. The admin can untick this, for example while a concern is looked into.
- **Record.** Each change is kept in `tutor_changes` (who, what, when, why). Only matching admins can read it. The activity log holds ids only.
- **Modules.** Scheduling writes only its own tables and the tutor matches, as confirming a booking already does. It never writes billing, Teams or child safety tables. After moving sessions for an urgent re-match, the admin still marks the red flag "sorted" on the Matching page.

## 3a. Day and time, and confirming first (Carla, 15 Nov 2026)

Carla's follow-ups on the same day:

- "When changing the tutor for pre-booked sessions, the day and time of the sessions can be altered in this step (will be set to the current booked day and time initially though)."
- "A session which has been altered needs to be confirmed by the other or all parties before being confirmed."

So the steps are now:

- **Day and time.** The page fills in the current booked day and start time. The admin can pick another day, or a start time on the quarter hour. Each session moves to that day within its own Monday-to-Sunday week, keeping its length. This only works when every session being moved is on one weekly day and time. If there's a one-off session in the mix, choosing a change date after it makes this possible.
- **Checks at the new time.** The new tutor must be free at the new time. The student mustn't have another session then, and no session can land before the change date.
- **Confirming first.** "Send for confirmation" saves a waiting change and asks the new tutor and the family (parents, and the student if they have their own login). They each see a "Please confirm a change" box on their Sessions page, showing the old and new times, and get a notice. Nothing moves until both say yes. That matches how CLG's offers already work, where both sides approve a time (see `scheduling.md`). It also follows Principle 4 of the National Principles for Child Safe Organisations, on informing and involving families.
- **Saying no.** A no needs a short reason. Full admins are told who said no and why, and the other side is told the change isn't going ahead.
- **Something changes meanwhile.** When the last yes comes in, every check runs again. If the change can't be made any more (for example, the tutor got booked at that time), nothing moves. The change is marked "couldn't be made", and full admins are told why.
- **Withdrawing.** The admin can withdraw a waiting change, and the new tutor and family are told nothing is changing.
- **The old tutor** isn't asked, because their sessions are being moved. They're told after it's confirmed, unless the admin unticks that.
- **Invoices** already made keep the old day and time in their wording. Billing's records aren't changed by scheduling, and the session still counts as paid. **Teams links** stay the same and still work at the new time.

## 4. How we'll know it works

- Every urgent re-match flag is sorted before the first paid session date.
- No paid session is cancelled because of a tutor change. The pilot test guide checks this.
- In the pilot test guide: after a change, the family, the new tutor and the old tutor each see the right notice. The old tutor can no longer open the student.

## 5. Still to decide

- What happens when a change isn't answered for a long time. For now it waits until someone answers or the admin withdraws it, and the admin page shows when it was sent.
- Moving only some sessions, such as one week while a tutor is away, rather than everything from a date. For now one-off changes are made by cancelling and booking that session.
