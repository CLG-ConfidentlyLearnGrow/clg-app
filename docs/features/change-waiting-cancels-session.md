# Cancel a session while a change to it is waiting

Carla, 23 Nov 2026: "when a session change is waiting it cancels the session (notifying the tutor/family that they need to confirm the session change, give a different availability, or continue with the session cancellation)."

This builds on [No no-show while a session change is waiting](pending-change-no-no-show.md) (PR 219), which only acted if someone recorded a no-show.

## What it is for

When CLG asks to move a student's sessions to a new tutor (and maybe a new day and time), the new tutor and the family both have to confirm. Until they do, nobody is sure which session is real. Instead of leaving the old session booked and hoping, the app cancels it ahead of time, tells everyone plainly, and asks the people who need to act to choose what happens.

## What the evidence says

- **One to one tuition** (EEF Teaching and Learning Toolkit): tuition works best when sessions are regular, well planned and clearly arranged. A clear cancel a day ahead, with a quick way to rebook, protects that regularity better than an uncertain session that may or may not happen.
- **Parental engagement** (EEF; AERO guidance on family and school partnerships): families stay engaged when communication is timely, specific and gives them a clear next step. Each notice says what happened, that there is no charge, and the three things they can do.
- **Working with parents to support children's learning** (EEF guidance report): offering simple, practical choices works better than general messages. The card has three buttons and one short box for times.

## How the design follows it

- Every 15 minutes the app looks for booked sessions covered by a change that is still waiting (same student, tutor and subject, on or after the change's first date, change sent before the session).
- If such a session starts within 24 hr (a setting, `scheduling_settings.change_cancel_hours`) but more than 2 hr from now, it is cancelled as a CLG cancel with the reason "A change was waiting for approval".
- The current tutor is told the session is cancelled and not to go. The new tutor and the family (parents, and the student with their own login) get a notice and a **Session cancelled: please choose what happens** card on the Sessions page with three choices:
  1. **Confirm the change**: the existing confirmation. When everyone has confirmed, the cancelled session comes back at the new tutor, day and time, if it is still more than 2 hr away and no credit has been given for it yet.
  2. **Offer other times**: the family's days and times go to CLG's **Requests** list (as a request for another time), and admins are told. From the new tutor, the times go to the admins.
  3. **Keep it cancelled**: the session stays cancelled.
- The first answer from anyone asked counts for that session. For the family, the first answer from a parent or the student counts (Carla, 16 Nov 2026).
- The owner and Operations admins are told when a session is cancelled this way, and when someone offers other times or keeps it cancelled.
- A session less than 2 hr away when a change is noticed stays booked. If it is then recorded as a no-show, PR 219 closes it as a CLG cancel instead.

## Money

These follow the rules already in place for a CLG cancel made 2 hr or more ahead (Carla, 26 Oct and 16 Nov 2026):

- The family gets full credit for the cancelled session.
- The tutor gets no pay for it (late-cancel pay is only for under 2 hr notice, and PR 219 keeps these sessions out of pay).
- If the session comes back, it is charged and paid as a normal session.

## How we will know it works

- how many sessions are cancelled this way each term (a sign changes take too long to confirm)
- how many come back after the change is confirmed
- time from a change being sent to everyone confirming

## Privacy, child safety and legal notes

- No new personal information beyond the times a family or tutor types in. The record is read only through functions that show each person their own rows, and admins see it through their notices and the Requests list.
- **Australian Consumer Law**: families are never charged for a session cancelled because of CLG's own unfinished change, and are told so in plain words.
- **Fair Work Act and tutor contract (clause 3.4)**: the session is cancelled well before it starts (2 hr or more), so no tutor is left waiting for a session that is not going ahead.
- **Child safety**: the old tutor is told only that the session is cancelled, not why the change is happening.

## Technical

- Migration `20261125400100_change_waiting_cancels_session.sql` (it includes everything in `20261124711100_pending_change_no_no_show.sql`, so it works whether or not that file was run). Adds the setting, the table `change_cancelled_sessions`, the notice kind `change_cancelled`, the job `clg-change-waiting-cancels` (every 15 minutes), `private.cancel_sessions_for_waiting_changes`, `private.restore_change_cancelled_sessions` (called from `finish_tutor_change`), `public.my_change_cancelled_sessions`, `public.answer_change_cancelled_session`, and a small Teams helper so a session that comes back gets a new link. Safe to run more than once.
- Page: the card is in `src/components/tutor-change-answer-box.tsx`, the action in `src/app/actions/change-tutor.ts`.
- Tests: `supabase/tests/scheduling_change_waiting_cancels.test.sql`.
