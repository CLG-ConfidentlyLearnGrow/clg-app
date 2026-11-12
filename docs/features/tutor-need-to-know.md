# Tutors see only what they need

Carla, 12 Nov 2026: "Need to ensure tutors only see the students they have been matched with, no other student information, and no financial information or personal information they do not need to know in order to be an effective tutor for that student."

## What a tutor needs to tutor well

Education research on effective tutoring points to a short list:

- **Who the student is now:** year level, school, the subjects and the level they work at. Tutoring works best when it is matched to the student's current attainment and linked to what they learn in class (EEF Teaching and Learning Toolkit, "One to one tuition" and "Small group tuition"; EEF guidance on making the most of tutoring; Evidence for Learning's Australian version of the Toolkit).
- **Their goals and learning needs:** what the family wants, any learning needs and the support that helps (AERO, "Tailoring teaching to students' needs"; EEF, "Special Educational Needs in Mainstream Schools").
- **Progress so far:** goals, skills, session notes, evidence and reviews, so each session builds on the last (EEF, "Feedback" and "Metacognition and self-regulation").
- **Who to talk to:** the parent's name, for messages about the student.
- **When and where:** session times, place or meeting link.

What the research does not need: the student's exact birth date (year level is the measure used), any family's billing, invoices, prices or payment status, parents' contact details or emergency contacts (CLG passes messages on), or anything about students the tutor doesn't teach.

## The rules that apply

- **Privacy Act 1988 (Cth), APPs 3, 6 and 11:** collect and use personal information only as reasonably necessary, and take reasonable steps to protect it, including limiting staff access.
- **Children's Online Privacy Code (draft, OAIC, due Dec 2026):** data minimisation and privacy by default for children's information.
- **National Principles for Child Safe Organisations, Principle 8** (adopted in SA's child safe environments guidance): physical and online environments minimise the risk of harm, including who can see children's information.
- **UK GDPR and EU GDPR Article 5(1)(c)** (data minimisation) and the **ICO Age Appropriate Design Code**, standard 8 (data minimisation), for when CLG goes international.

## What was already in place

- Tutors see a student only while they have a current match with that student, and only while every check that student's state needs (WWCC, RRHAN-EC) is verified and in date. A lapsed check hides the student straight away. This lives in the database (`private.is_tutor_of`).
- Before a tutor accepts an offer, they see only the student's first name, year level, subject and goal (`offer_card`, PR #77).
- Tutors can't read any family's billing: accounts, invoices, payments, credits, rates, pause status or plan choices. They see only their own pay.
- Tutors can't read anyone's email, phone, emergency contacts or payment ids, or family records.
- Tutors see parents' names only for students they teach.
- Learning-needs notes are read through a function that logs every view.

## What changed (12 Nov 2026)

1. **Birth dates hidden from tutors.** No tutor page showed it, but the database let a tutor read it. The `students.date_of_birth` column is no longer directly readable; `student_birth_dates()` gives it to admins, the student's parents and the student only. The parent to-do number and "Download my data" read it through the same check.
2. **Add-on prices hidden from tutors.** The study plans note on a progress page showed the price to tutors. `add_on_for_student` now gives the price to admins and the family only.
3. **Tutor tab shows only the tutor's own.** Someone who is also an admin is sent everything by the database, so the Sessions page's Requests, Blocks and Away dates lists now filter to the tab: the tutor's own students in the Tutor tab and the family's own children in the Parent or Student tab. This is the same kind of fix as the Parent dashboard fix in PR #103.

## Tests

`supabase/tests/tutor_need_to_know.test.sql` signs in as every tutor-only account and checks, across every table that names a student or family and every billing table, that they see nothing outside their current students and their own pay. It also checks birth dates and add-on prices, and fails if a new `students` column is added without being made readable.

**For future changes:** a new column on `students` needs `grant select (new_column) on public.students to authenticated;` in its migration. The test above tells you if it's missing.

## Not changed (questions for Carla)

- **Lapsed checks and the schedule.** If a tutor's check lapses, their students disappear, but their own session list still shows the student's name and times. CLG should reassign those sessions; the app could also hide them.
- **Emergency contact for in-person sessions.** Tutors can't see a parent's phone number. If CLG wants in-person tutors to reach a parent in an emergency, that would be a deliberate, logged addition.
- **CLG's price list** (active price items) is readable by everyone signed in, including tutors. It holds CLG's public prices only, not any family's.
