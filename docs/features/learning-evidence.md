# Work and reports (evidence of learning)

Part 5 of progress tracking (phase 2 of the research brief: https://claude.ai/artifact/UvGuihmTC7xyH9XHrjLbLt).

## What it's for

Tutors set goals and judge skill levels from what they see in sessions. School reports, NAPLAN results and marked school work show the same student from the school's side, and families already have them. The upload portal gives families and students one place to share them, and gives tutors a place to keep samples of work from sessions. Each upload can be linked to the skills it shows.

## What the evidence says

- **Assessment for learning / formative assessment** (Black and Wiliam; EEF guidance on feedback and on metacognition): teaching works best when it starts from what the learner can already do, using more than one source of evidence. Uploads add the school's view to the tutor's session observations.
- **One to one tuition** (+5 months, EEF): works best when it is closely linked to classroom teaching. School work and reports show what is being taught at school and how the student is going there, so tutoring can line up with it.
- **Parental engagement** (+4 months, EEF; AERO): two-way sharing between home and the educator helps more than one-way reports. Uploading is a simple, low-effort way for families to take part; it asks for nothing beyond what they already have.
- **Caution on single results** (AERO, ACARA on NAPLAN): one test or report is a snapshot. No upload sets a skill level on its own; the tutor decides levels from the whole picture, and the upload is linked as supporting evidence.
- **Tutor workload** (EEF): the tutor's review is optional and short (a comment and ticking skills from the student's goals).

## How the design follows the evidence

- **Who uploads**: the student (own login), a parent who manages the student, or the student's tutor. School reports and NAPLAN results come from parents (Carla, 2026-10-28): tutors can't add them, and a student can only if no parent manages their account (for example an adult learner). On a phone, the file picker offers the camera, so a photo of a marked test takes seconds.
- **What**: marked work or a test, a school report, NAPLAN results, another assessment, or a sample of work. A name, and optionally the subject, date and grade as written.
- **The tutor is told** about family and student uploads on their dashboard ("New uploads from families"), and links the skills it shows from the student's goals, with an optional comment the family can see.
- **Family view**: a "Work and reports" card on the progress page lists every upload with the tutor's comment and the skills it shows.

## How we'll know it works

- share of students with at least one school report or marked piece of work uploaded each term
- share of family uploads the tutor has looked at within a week
- tutors' view (pilot feedback) of whether uploads changed what they focused on

## Privacy and child safety

- Files sit in a private file store (5 MB limit; PDF, JPG, PNG or WebP only, checked from the file's contents). Each file is in a folder named for the student, and the database checks every upload, download and record against that student's access rules: the family, the student's current tutors (with two-step login) and admins. Links to open a file work for one minute.
- School reports often name the school and teachers, and photos of class work can show other children's names. The upload form asks families to cover other children's names (APP 3: collect only what is needed).
- `learning_evidence` hangs off `students`, so automatic deletion of a student's data removes the records; their files are queued and removed by the daily job (`/api/progress/cron`), because files can only be deleted through the file store.
- Families can remove anything they uploaded (and a managing parent or the student can remove any upload). Records can't be edited after upload, only removed and added again; the tutor's comment and skills go through `review_evidence`. Every change is in the audit log.
- No free-text fields invite health or diagnosis details. Reports from psychologists or other health professionals aren't asked for; if CLG needs them later, that needs its own consent and access rules.
- Migration `20261029500300_progress_evidence.sql`; tests in `supabase/tests/progress_evidence.test.sql`.
