# Senior certificates by state

Part 6 of progress tracking (phase 2 of the research brief: https://claude.ai/artifact/UvGuihmTC7xyH9XHrjLbLt).

## What it's for

Years 11 and 12 follow each state's own senior certificate: SACE in South Australia, NTCET in the Northern Territory, HSC in New South Wales, VCE in Victoria, QCE in Queensland, WACE in Western Australia, TCE in Tasmania and the ACT Senior Secondary Certificate. Families of senior students want to know one thing above all: is the student on track to finish? This adds a tracker on the progress page: the student's senior subjects, their results, and what's still needed for the certificate.

All CLG students are in South Australia, so SACE's rules are loaded now. The other certificates are listed, so a student in another state is matched to the right one, and their rules are loaded (and checked against the official source) before CLG takes senior students there.

## SACE rules used

From the SACE Board's "What is the SACE?" page (https://www.sace.sa.edu.au/studying/your-sace/what-is-the-sace), read 2026-10-28, and a 2027 school SACE handbook:

- 200 credits in total. 10 credits is one semester; 20 credits is a full year.
- Exploring Identities and Futures: 10 credits at Stage 1, C or better.
- Literacy: 20 credits of Stage 1 English subjects, C or better.
- Numeracy: 10 credits of Stage 1 Maths subjects, C or better.
- Activating Identities and Futures: 10 credits at Stage 2, C- or better. It replaced the Research Project from 2025; a Research Project result is recorded the same way.
- At least 60 more credits at Stage 2, C- or better.
- Grades: A to E at Stage 1; A+ to E- at Stage 2.

To check with the SACE Board: whether a finished non-compulsory subject with a low grade still earns credits (the app counts every finished subject towards the 200), and the NTCET's rules before loading them. The rules are data (`certificate_requirements`), so a change is a row update, not new code.

## What the evidence says

- **Goal setting and self-regulation** (EEF metacognition and self-regulation, +8 months): learners do better when they can see the goal and monitor their own progress towards it. The tracker makes the certificate's requirements visible to the student and family, alongside the roadmap's assessment steps.
- **Parental engagement** (EEF, +4 months; AERO): families help most with planning and keeping track, not re-teaching. The tracker gives them a shared picture with the tutor.
- **Senior students' subject choices** (AERO and state curriculum bodies stress informed subject choice): seeing what's still needed (for example, numeracy not yet met) prompts a conversation early enough to act.

## How the design follows the evidence

- Shown on the progress page from Year 10 (Exploring Identities and Futures can start in Year 10), or once a subject is added.
- The student (own login), a parent who manages them, or their tutor adds subjects: name, stage, credits, which compulsory part it counts towards, year, status (planning, studying, finished) and the grade the school gave.
- The table shows each requirement: credits done with a good enough grade, credits under way, and whether it's met.
- The card says plainly that the school's record is the official one.

## How we'll know it works

- share of Year 11 and 12 students with their subjects entered
- students flagged early with a compulsory part not yet met, and whether it was met by year end

## Privacy and child safety

- `senior_subjects` hangs off `students`, so the shared access rules and automatic deletion apply. Only the family, the student, the student's current tutors and admins see it; changes are in the audit log.
- Grades are learning data the family already has; no health or ATAR prediction is stored.
- Certificate rules are reference data: everyone signed in can read them; only admins change them.
- SACE completion rules are facts about the certificate, written in CLG's own words; no SACE subject content is copied (see curriculum-import.md on SACE copyright).
- Migration `20261029500400_progress_senior_certificates.sql`; tests in `supabase/tests/progress_senior_certificates.test.sql`.
