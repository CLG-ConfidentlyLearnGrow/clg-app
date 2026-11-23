# Decision steps record and decisions log

Carla, 22 Nov 2026, from How We Do Things v1.0 (section 4): each person has a decision steps record, one line for each kind of problem, showing their current step, the date it moved and a short note. Carla moves the steps at accountability check-ins. At Step 4 decisions go in a decisions log that Carla can read at any time. Until the app had a place for it, the record was a table in check-in notes. Carla agreed that Emma (Operations) reads tutors' records and adds notes, and only Carla moves the steps.

## What it is for

The five steps (1 Suggest then ask, 2 Fix then tell, 3 Fix and put it in the daily update, 4 Fix and record, 5 Overview only) give each person more freedom as their judgement is proven, one kind of problem at a time. A clear record shows each person where they stand and what to aim for, makes check-ins concrete, and becomes their pathway into new responsibilities.

## What the evidence says

- **Gradual release of responsibility** (Pearson and Gallagher; used across AERO's explicit teaching guidance): independence grows best in planned stages with support withdrawn as competence is shown. The steps apply the same idea to staff decisions.
- **Effective professional development** (EEF guidance report, 2021): feedback, goal setting and monitoring help embed new practice. Each line has a goal and dated moves.
- **High expectations with support** (wise feedback research, Yeager and others, 2014): people respond well to high standards when they know the person believes they can reach them. Moving back a step is framed as normal learning, not a mark against anyone.

## How the design follows it

- Every tutor and admin has **Decision steps** in their side menu, showing their own record: the kind of problem, their step, the goal from the guide, when it moved and the note. Lines come from the guide's starting points tables (10 for admin, 7 for tutors) and match the person's roles.
- During probation every line shows Step 1, as the guide says, using the existing probation records.
- **My decisions log**: the problem, the options considered (at least three), the one chosen and why, and whether it is done.
- Carla opens anyone's record, moves a step with a note (the person gets an app notice, and every move is kept), adds notes, and changes the kinds of problem.
- Operations admins (Emma) open tutors' records and logs and add notes, but cannot move steps.
- Notes are visible to the person, in line with the No-BS and keep-informed values.

## How we will know it works

- share of staff with at least one step moved per term
- steps moved back (should be rare and short)
- decisions logged at Step 4, and whether check-ins use the record

## Privacy, child safety and legal notes

- **Privacy Act 1988 (APPs 3, 6, 10 and 11)**: this is employee information. The person sees their own record; CLG's owner sees everyone's; Operations admins see tutors' only. Access rules are in the database, and every change is in the audit log. The log reminds staff to use first names or initials only for students.
- **Employment (Fair Work)**: the record is a development tool, not a disciplinary record, and is not used to set pay. Notes are visible to the person, so nothing is kept from them.
- **Child safety**: not part of the steps. Concerns always go to Carla the same day through Child safety.
- **UK and EU (GDPR)**: the same minimal fields and access apply; legitimate interest is the basis.

## Technical

- Migration `20261124711700_decision_steps.sql` (module: staff). Tables `decision_kinds` (loaded with the guide's starting points), `decision_steps`, `decision_step_moves`, `decision_notes` and `decision_log`; functions `decision_record`, `decision_record_people`, `decision_step_move`, `decision_note_add`, `decision_log_add` and `decision_kind_save`. It reads `staff_probations` (probation module) but never writes it. Safe to run more than once.
- Page: `/decisions`. Actions: `src/app/actions/decisions.ts`. Shared words: `src/lib/decision-steps.ts`.
- Tests: `supabase/tests/staff_decision_steps.test.sql`.
