# Brothers and sisters keep their profiles private

Carla, 16 Nov 2026: "If a parent has multiple student profiles, the separate student profiles can not see what is on the profile of the students even with the same parent/guardian."

## Why it matters for learning

- **Feedback and progress work best when they are personal.** Feedback is most useful when it is about the learner's own work and next steps, not a comparison with others (EEF Teaching and Learning Toolkit, "Feedback"; Evidence for Learning's Australian Toolkit). Being shown a sibling's marks, goals or reviews invites comparison that research links to lower motivation in the weaker-performing child.
- **Learner agency.** Older students (16+) who manage their own learning build self-regulation when they own their goals and plans (EEF, "Metacognition and self-regulated learning"; AERO, "Tailoring teaching to students' needs"). That works only if the plan is theirs, not shared across the family.
- **Learning needs and wellbeing are sensitive.** One sibling may have learning needs, a safety concern or a change of tutor that the other has no reason to know about.

## The rules that apply

- **Privacy Act 1988 (Cth), APPs 6 and 11:** use personal information only for the purpose it was collected for, and protect it from unauthorised access. A sibling is a separate person, so their records are not "the family's".
- **Children's Online Privacy Code (OAIC, due Dec 2026):** privacy by default and least data for children.
- **National Principles for Child Safe Organisations, Principle 8** (SA child safe environments): online environments minimise the risk of harm, including who can see a child's information.
- **UK GDPR / EU GDPR Article 5(1)(c) and the ICO Age Appropriate Design Code** (standard 7, default settings; standard 8, data minimisation), for when CLG goes international.

## What was already in place

Every student record is checked per student in the database, never per family: a student sees a record only when it is their own (`private.is_student_self`), a parent only for their own linked children (`private.is_parent_of`). That covers profiles, birth dates, sessions, bookings, calendars and the private calendar link, progress, goals, steps, evidence, term reviews, materials, feedback, make-up time offers and change-of-tutor confirmations (each confirmation goes only to that student's own parents and that student), notices and "Download my data".

## The gap found and fixed

An adult learner (18 or over) with their own login was treated as paying for their whole family. An adult sibling could see the family's invoices (each line names a child and a session), the family's credits and plan, and could accept the family terms or choose the plan.

Now an adult learner sees and manages a family's billing only when they are the family's only learner. In a family with brothers or sisters, billing stays with the parents, or with the person CLG names as the bill payer on Admin > Billing (for example an older sibling who pays for everyone). Naming them is CLG's deliberate choice, and they still can't see their siblings' profiles or sessions, only the invoices they pay.

Database change: `supabase/migrations/20261118300100_sibling_privacy.sql` (`private.is_family_payer`, `private.can_pay_for_family`).

## Tests

`supabase/tests/sibling_privacy.test.sql` takes the student with records in the most tables, adds two siblings with their own logins in the same family and parent (aged 17 and 19), and, signed in as each sibling, sweeps every table and view in the app for anything about the first student: their rows, sessions, bookings, the family's invoices and credits. It also checks the family-facing lists, the data download and the private calendar link, that the parent still sees all three children and the family's billing, and that a named bill payer sees the invoices but still not the sibling's profile. New modules are covered automatically as long as their tests add data.

## Screens

No screens change. The App guides (student and parent) now say that each child's profile is private, and that a parent looks after billing when brothers or sisters also learn with CLG.
