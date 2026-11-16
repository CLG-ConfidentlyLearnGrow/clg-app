# A tutor is never matched with their own child

Carla, 16 Nov 2026: "Students can not be matched with their own child" (a tutor can't be matched with their own child). Found while writing the pilot test guide (test R1b): nothing stopped a tutor who is also a CLG parent from being suggested for, or matched with, their own child.

## Why this matters for learning

- **Honest feedback and assessment.** Tutoring helps most when feedback is specific, honest and tied to clear goals (EEF, "Feedback" guidance report and Teaching and Learning Toolkit; Evidence for Learning's Australian Toolkit). A parent marking their own child's progress, writing their term review or session notes, can't give that independent view, and families and CLG lose a trustworthy record of progress.
- **The tutoring relationship.** Effective one-to-one tuition depends on a structured, professional relationship with clear expectations (EEF, "One to one tuition"; EEF guidance on making the most of tutoring). Home and family roles blur that structure.
- **Families stay partners, not tutors.** Research on parental engagement points parents towards supporting learning at home (talking about learning, routines, encouragement) rather than taking over teaching (EEF, "Working with Parents to Support Children's Learning"; AERO, family engagement). CLG's progress pages already give parents that role (tips for home, roadmap).

## The rules it touches

- **Conflicts of interest in child safe practice:** National Principles for Child Safe Organisations (Principles 1 and 6, governance and conduct of staff), adopted in South Australia's child safe environments guidance; CLG's child safe policy and tutor code of conduct expect workers to avoid dual relationships with children they work with.
- **Professional codes:** teacher codes of ethics (for example the Teachers Registration Board of SA code and AITSL standards) ask educators to avoid conflicts of interest. CLG holds its tutors to the same standard.
- **Billing honesty:** a tutor paid for sessions with their own child would bill their own family. The rule also prevents that.
- **UK and EU:** the UK's Keeping Children Safe in Education and safer recruitment guidance treat conflicts of interest the same way, so the rule carries over when CLG goes international.

## What "their own child" means

Any student where the tutor is:
1. a linked parent or guardian of that student,
2. a linked parent or guardian of another student in the same family (for example a stepchild or sibling), or
3. the student themselves (a tutor learning with CLG).

## How it works (database, migration `20261118100400_no_tutor_own_family.sql`)

- `private.tutor_is_family(tutor, student)` answers the question above.
- `private.blocked_pair` (the shared check used by Matching, Book a session, offers, requests and Change tutor) now also says "blocked" for a tutor's own family, so they're never suggested.
- A guard on `tutor_assignments` refuses any new match, or a match moved to a new tutor or student, with a plain message. Ending an old match still works.

## Tests

`supabase/tests/no_tutor_own_family.test.sql`: linked parent, same-family sibling and self are blocked and refused; other tutors and other children are unaffected; ending a match still works.
