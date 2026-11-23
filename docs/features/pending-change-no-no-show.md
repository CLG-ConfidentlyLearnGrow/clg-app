# No no-show while a session change is waiting

Carla, 22 Nov 2026, from the tutor contract (v1.2 and v1.3, clause 3.4): "Once a change has been requested, the original session does not count as a no-show for you or the family if the change is not approved in time. CLG follows up and rebooks it."

## What it is for

When CLG asks to move a student's sessions to a new tutor, day or time, the new tutor and the family both have to confirm. Until they do, the old arrangement is uncertain: the family may think the session has moved, or the tutor may not be sure whether to turn up. Counting a missed session as a no-show in that gap would charge the family and pay or penalise the tutor for CLG's own unfinished change.

## What the evidence says

- **One to one tuition** (EEF Teaching and Learning Toolkit): sessions work best when they are regular and the arrangement is clear to everyone. Rebooking quickly keeps the learning going instead of losing a week to a dispute.
- **Parental engagement** (EEF): families stay engaged when communication is clear and fair. A rule that never charges them for a change CLG started protects that trust.

## How the design follows it

- A session counts as "changed but not approved in time" when a tutor change covering it (same student, tutor and subject, from the change's first date) was sent before the session started and was not confirmed before it began (still waiting, could not be made, or answered only after the start).
- Recording a no-show for such a session (tutor or admin) does not save a no-show. The session is closed as cancelled by CLG with the reason "A change was waiting for approval".
- The family gets full credit (no charge), and the tutor gets no no-show or late cancellation pay for it, as the contract says.
- The owner and Operations admins get a "Session to rebook: change not approved in time" notice to follow up and rebook. The tutor sees a plain message saying the same.

## How we will know it works

- number of sessions closed this way each term (a sign of changes taking too long to confirm)
- time from a change being sent to it being confirmed

## Privacy, child safety and legal notes

- No new personal information is stored. The cancel reason is a fixed label.
- **Australian Consumer Law**: families are not charged for a session that did not go ahead because of CLG's own pending change.
- **Fair Work Act**: matches the tutor contract term (clause 3.4) that this is not a no-show for the tutor.

## Technical

- Migration `20261124711100_pending_change_no_no_show.sql` (run after `20261124711000_quiet_hours_count_from_5am.sql`). It adds the cancel reason, `private.session_change_pending`, and changes `record_session_outcome`, `cancel_reason_label` and `billing_build_pay` in place. Safe to run more than once.
- Tests: `supabase/tests/scheduling_pending_change_no_show.test.sql`.
