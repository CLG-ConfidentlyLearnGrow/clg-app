# Support requests, automatic curriculum and notes from home

Requested by Carla, 2026-10-26.

## What it does

- **Asking for support.** When a parent adds a child, they now give:
  - their year level at school
  - the subjects the child wants help with (one or more, up to 10; Maths as General, Essential or Advanced), each with the level the child is working at in that subject, or "Not sure"
  - the end goal of CLG's support (required)
  - any other information (optional)
- **Seeing and changing details.** Parents see these on their dashboard and can change them, with "See or change details" under each child: name, year level, school, subjects, end goal and other information. Date of birth and state stay with CLG, because they decide which child safety rules and tutor checks apply.
- **Skills are the tutor's job.** Families give the overall goal, which they can add to later. They never choose curriculum skills. When a tutor adds a goal, skills at the level the family gave for that subject start ticked, or the school year if they weren't sure. The tutor unticks or adds skills. The page notes that skills may change in the first three sessions.
- **Automatic curriculum.** When an admin assigns a tutor for a subject, the app attaches every confirmed curriculum with skills for that subject at the student's year level. Examples:
  - The level used is the one the family gave for that subject, or the school year if they weren't sure.
  - General Maths in Year 6 gets the Australian Curriculum's Mathematics.
  - General Maths in Year 11 gets SACE General Mathematics, once loaded.
  - Admins can still add or change a curriculum by hand.
- **Family view of progress.** Parents and students see only family tools on the progress page. Session notes stay with tutors. Someone who is both a parent and staff (for example Carla) sees the family view when they open the page from the parent dashboard.
- **Notes from home.** Students and parents can send "Feedback" or "Progress at home" at any time, not only after a session. The student's tutors and admins see these, and so does the family. Notes can't be edited or deleted by families; admins can remove them.

## Why (education research)

- **Parental engagement.** The EEF Teaching and Learning Toolkit rates parental engagement at about +4 months' progress. It works best when it is specific and supports learning at home, not just general contact. A simple "progress at home" note gives tutors that link without adding work for busy parents. This fits Carla's rule that parent support stays light.
- **Clear goals.** Goal setting and shared learning intentions are part of the metacognition and self-regulation evidence (EEF, about +7 months). They are also part of explicit teaching (AERO). Asking the family for the end goal at the start gives the tutor a target to plan towards. It also sets up later roadmap work ("planning"; see the progress tracking brief).
- **Matching on need.** One-to-one tuition (EEF, about +5 months) works best when it is closely tied to the learner's needs and to the curriculum they are taught. Attaching the curriculum for the subject and year level does this from the first session.

(EEF figures are from the Toolkit's headline estimates. Check them again before quoting externally.)

## Legal notes

- **Privacy Act and APPs, Children's Online Privacy Code (draft).**
  - Data minimisation: the "other information" box asks families not to put medical details there. CLG asks privately and records them in the separate, audited learning needs area if needed (APP 3, sensitive information).
  - Only the family, the student's current tutors and admins can read requests and notes. This is enforced in the database (row level security), with tests in `supabase/tests/support_requests.test.sql`.
- **Child safety.** Family notes are not a channel for safety concerns. The form points families to contact CLG directly. Concern flags are a separate, planned feature.
- **Records.** Notes and subjects are deleted with the student under the existing retention rules (student records 2 years after last activity).
