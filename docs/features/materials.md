# Materials library

Migration `20261029600100_materials.sql`, tests in `supabase/tests/materials.test.sql`.

## What it's for

CLG's own worksheets, lesson plans, activities, tests and answers live in the app instead of in personal drives and Teams. Tutors find the right material for the student in front of them quickly, and every material is tagged with the curriculum skills it works on, so the app can suggest it from a student's goals now and from roadmaps later. Carla is still writing materials, so adding and tagging them has to be quick.

## What the evidence says

- **Good shared materials beat everyone making their own.** Grattan Institute, *Ending the lesson lottery* (2023): teachers spend hours each week finding or making materials, quality varies widely, and access to shared, quality-assured, curriculum-aligned materials saves time and lifts learning. https://grattan.edu.au/report/ending-the-lesson-lottery-how-to-improve-curriculum-planning-in-schools/
- **Materials should be checked and sequenced, not just stored.** AERO's work with OCHRE on free, quality-assured curriculum resources rests on the same idea: materials aligned to the Australian Curriculum and to evidence-based teaching (explicit teaching, worked examples, practice). https://www.edresearch.edu.au/guides-resources/ochre-resources
- **Tutoring works best when it's linked to what the student is learning.** EEF, *Making a difference with effective tutoring* (2022): sessions should be well structured, use quality resources, and connect to the curriculum and to assessment of the student's needs. https://educationendowmentfoundation.org.uk/news/new-eef-guide-making-a-difference-with-effective-tutoring
- **Feedback and next steps work skill by skill** (EEF Feedback, AERO formative assessment; see `progress-tracking.md`). Tagging materials with the same skills as goals lets a tutor go straight from "next step" to the right practice.

## How the design follows the evidence

- **One shared library, checked before tutors see it.** Admins upload; a material is a draft until an admin publishes it. Tutors can't add materials (quality control), though they can suggest them to Carla.
- **Tagged with specific skills from the shared skill library**, using the versioned curricula already loaded for progress tracking (AC9, SACE and any later ones). Only skills from a confirmed curriculum can be used. Publishing needs at least one skill, or a short reason when no curriculum fits (for example study skills).
- **Easy to tag.** The skill picker only lists skills for the material's subject and year range, with search by words or code. Up to 20 files can be uploaded at once with shared settings, titles come from file names, and an optional editable original (Word, PowerPoint, Excel) can be kept with each one for admins.
- **Right material, right tutor.** Tutors see only published materials for a subject they teach, where the year range overlaps the years they teach it for.
- **Suggestions from goals.** A tutor's materials page leads with "For your students' goals": materials tagged with skills in their current students' active goals. Roadmaps can use the same tags later (`materials_for_my_students` reads goals; it never writes progress tables).

## Protecting CLG's materials

Research on what's practical: anything a browser can show, a person can save, print or photograph, so "view-only" can't be guaranteed. The approach used by publishers and schools is to make copying unnecessary, traceable and limited:

- **Stamped copies only.** Tutors never get the original. Each open makes a fresh PDF with the tutor's name, email and the date across every page (three faint diagonal lines, so cropping doesn't remove it) and along the bottom. A shared copy shows whose it was.
- **No direct file access.** Files sit in a private store only admins can reach. The server reads a file only after the database agrees the tutor may open it, so the stamp can't be skipped.
- **No bulk download.** One material at a time, and at most 30 different materials per tutor in 24 hours (reopening the same one doesn't count).
- **Every open is logged.** Admins see opens per person for the last 7 days (with a "busy week" mark at 40 or more different materials) and the latest opens.
- **Access ends with the role.** When someone stops being a tutor, or a subject is removed from what they teach, the materials disappear at once.
- **Contract.** The stamp deters; the tutor contract enforces. The tutor contract should say CLG owns materials, tutors use them only for CLG sessions and must not keep, share or upload them (see Legal below).

Not done, because it doesn't work or gets in the way: blocking right-click or printing (easily bypassed, and tutors in in-person sessions need to print), and DRM viewers (cost, poor on phones).

## How we'll know it works

- Share of published materials tagged with at least one skill (aim: all, except those with a reason).
- Opens per tutor per week, and how often a tutor opens a material suggested from a goal.
- Number of drafts waiting to be tagged.
- Later: progress on skills after a tagged material was used.

## Legal rules and privacy

- **Copyright (Copyright Act 1968, Cth).** Materials made by employees in their job belong to CLG (s 35(6)). Materials made by contractors belong to the contractor unless the contract assigns them, so the tutor contract needs an assignment and confidentiality clause. Third-party content (textbooks, SACE material) needs permission; SACE material needs written permission (see `curriculum-import.md`).
- **Privacy Act 1988 and APPs.** The stamp and open log hold tutors' names and emails (staff personal information), used to protect CLG's work. Tutors should be told this (APP 5): the materials page says so. Open records are seen only by admins, kept 2 years, then deleted nightly, and deleted at once with the account.
- **Children's data.** Materials hold no student information. Suggestions show a tutor only their own current students' goals, using the existing access rules (two-step login, current and cleared tutor).
- **Children's Online Privacy Code (exposure draft) and UK/EU.** No new data about children. The same design would meet UK GDPR and the EU GDPR (legitimate interest for the log; short retention).
