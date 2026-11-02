# Add-ons (starting with study plans)

Carla, 2 November 2026: study plans stay free for now, while the kinks are ironed out, and later become a paid subscription add-on. The app needs a switch so that change is easy and charges no one by accident.

## What it's for

CLG will offer extras on top of tutoring (study plans first; games and video lessons later). Each extra needs to be:

- free for everyone while it is tested,
- paid later, for only the students whose family pays for it,
- or switched off,

without a code change, and without anyone losing what they already made.

## What study plans are

Study plans are the parts of the roadmap on each student's progress page (built in PR #40, see `learning-roadmaps.md`) that go beyond tutoring:

- adding school assessments and goals (with task sheet and rubric),
- "Plan study steps for me" (spaced practice and self-testing before an assessment),
- steps the student or family add themselves.

These stay part of tutoring, whatever the switch says:

- each session note's next step, which lands on the roadmap by itself,
- steps the tutor (or an admin) adds,
- ticking steps off, and reading everything already on the roadmap.

## What the evidence says

- **Metacognition and self-regulation** (EEF Teaching and Learning Toolkit, +8 months, high evidence) and **feedback** (+6 months) are why study plans exist. The "where to next" part of feedback is the session next step; it stays free, so every student keeps the core of that benefit.
- **Equity**: the EEF's guidance on closing the disadvantage gap stresses that the highest-impact approaches should reach the students who need them most. A paid add-on could widen gaps, so the design lets an admin give the add-on at no charge to any student (for example on hardship), with a note.
- **Parental engagement** (EEF, +4 months): the parent's part (seeing and ticking off steps) stays free.
- **Testing before charging**: the EEF's implementation guidance ("Putting evidence to work") advises piloting and checking fidelity before scaling. Keeping study plans free during the pilot gives the step-completion measures below time to settle before a price is set.

## How the design follows the evidence

- A shared-core list of add-ons (`add_ons`), each with a switch: **free** (everyone), **paid** (only students given it), **off**. Study plans start as **free**, so nothing changes today.
- Only the owner changes the switch and the price. A paid add-on must have a price first.
- `add_on_members` records which students have a paid add-on, from and until when, with a note. Admins (owner or operations) give and remove it under Admin > Progress.
- Switching to paid **does not charge anyone**. Charging is a later billing step: the billing module will read `add_on_members` and add a line to each family's invoice (billing never writes progress tables; progress never writes billing tables). Until that is built, an admin gives the add-on to each student who pays.
- Without the add-on, the roadmap hides the study-plan buttons and shows one plain line with the price and "Ask CLG". No countdowns, pop-ups or pressure.
- The rule is in the database (a trigger on `roadmap_targets` and `roadmap_steps`), not only the page.

## How we'll know it works

- Uptake: share of families using study plans while free, then share who keep them once paid.
- Share of planned study steps ticked off by their date, for students with and without the add-on.
- For assessments with results: grade aimed for against grade reached.

## Legal rules it touches

- **Australian Consumer Law**: prices shown must be the total price including GST (s 48 ACL). The price field says "include GST if it applies". Moving families from free to paid needs clear notice and their agreement first; the app never charges automatically on the switch. Recommend giving families at least 30 days' notice and adding the add-on to the Client Terms before charging.
- **Unfair contract terms** (ACL, penalties since November 2023): the add-on must be easy to cancel. Ending it is one button for an admin, and the family's tutoring is unaffected.
- **Subscription traps**: the Australian Government has proposed banning unfair trading practices, including subscriptions that are hard to cancel. Check the status before charging. The UK Digital Markets, Competition and Consumers Act 2024 brings in subscription rules (reminders, easy exit) and the UK and EU give a 14-day cooling-off period for digital services; keep both in mind when CLG goes international.
- **Children's Online Privacy Code** (draft) and the APPs: no new personal information is collected (only which student has the add-on and dates). No nudging children to pay: the price line is plain and points to CLG, and payment is always by an adult account holder through billing.
- Records follow the student: `add_on_members` rows are deleted with the student under the retention rules, and every change is in the audit log.

## Files

- Migration `supabase/migrations/20261102500100_study_plan_add_on.sql` (run after `20261029500100` and `20261029900200`).
- Tests `supabase/tests/progress_study_plan_add_on.test.sql`.

## Changes, 2 Nov 2026

A second add-on, `term_reviews`, is set up "off" with a per-term price
to be set. See [term-reviews.md](term-reviews.md).
