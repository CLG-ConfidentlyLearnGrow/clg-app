# Quiet hours: anything done counts from 5am

Carla, 22 Nov 2026: "Quiet hours are implemented, it needs to be noted, anything done during those quiet hours counts to have been done when it is no longer in quiet hours time. Quiet is from 9pm to 5am." The tutor contract update (v1.3) asks for the same: a cancellation saved in quiet hours counts from 5am for the 2-hour late cancellation pay rule.

## What it is for

The app already sends nothing between 9pm and 5am. A cancellation saved at 11pm for a 7am session would show 8 hours' notice, but nobody can act on it until morning: the tutor is asleep, CLG cannot offer a make-up time, and the tutor has already kept that time free. Counting it from 5am makes the notice match what people can actually do with it.

## What the evidence says

- **Wellbeing and workload**: the EEF and AERO both point to staff workload and wellbeing as conditions for good teaching. Quiet hours protect tutors' rest; this rule stops a late-night cancel from quietly costing them pay they would have had with a morning message.
- **Regular sessions** (EEF one to one tuition): sessions work best when they happen as planned. A clear, fair notice rule discourages last-minute cancels without penalising genuine emergencies, which the once-a-year waiver covers.

## How the design follows it

- One shared rule, `private.counts_from(time)`: a time inside CLG's quiet hours setting (9pm to 5am, Adelaide time) moves to the end of quiet hours; any other time is unchanged.
- Used for: family credit for a cancelled session (more than 24 hr, 24 to 2 hr, under 2 hr), the make-up credit rules, tutor late-cancel pay (under 2 hr), and the 24-hour "cancelled late" rule for logging work during a no-show or late cancel.
- The real time of the cancel is still saved and shown. The late-cancel waiver list adds "(saved in quiet hours, counts from 5am)".
- Cancels by the tutor or CLG still give the family full credit, whatever the time.
- Adelaide time is used for everyone, because CLG's quiet hours setting and policies are written for South Australia. If CLG grows interstate or overseas, this can move to each family's own time zone.

## How we will know it works

- number of late-cancel waivers asked for after quiet-hours cancels
- tutor questions about late-cancel pay

## Privacy, child safety and legal notes

- No new personal information is stored; only how existing times are measured changes.
- **Australian Consumer Law**: the credit rules must match what families agreed to. The parent and student App guides now say a cancel saved in quiet hours counts from 5am; CLG's terms and policy documents should say the same.
- **Fair Work Act**: late-cancel pay is CLG's own term in the tutor contract, on top of award pay, and this rule matches the contract update.

## Technical

- Migration `20261124711000_quiet_hours_count_from_5am.sql` (run after `20261124710900_student_success_program.sql`). It changes five functions in place and is safe to run more than once.
- Tests: `supabase/tests/quiet_hours_count_from_5am.test.sql`.
