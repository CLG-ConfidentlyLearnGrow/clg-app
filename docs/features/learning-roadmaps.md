# Learning roadmaps

Part 3 of progress tracking (phase 2 of the research brief: https://claude.ai/artifact/UvGuihmTC7xyH9XHrjLbLt). Carla chose planning as the first kind of support beyond tutoring (26 October 2026).

## What it's for

Most students see their tutor once a week. Between sessions, learning stalls unless the student knows exactly what to do next and when. A roadmap turns what a student is working towards (a school assessment, or something they want to learn) into small, dated steps they can tick off.

## What the evidence says

- **Metacognition and self-regulation** (+8 months, EEF Teaching and Learning Toolkit, high evidence): students who plan, monitor and evaluate their own learning make more progress. A roadmap is the "plan" and "monitor" parts made visible: the student sets the target, ticks steps off, and reviews with the tutor each session.
- **Spacing and retrieval practice**: practice spread over time beats the same practice crammed together, and testing yourself beats re-reading. AERO's "Tried and tested" guide on spacing and retrieval practice recommends both. The EEF's 2021 review of cognitive science in the classroom found the lab evidence strong but warned that classroom results vary with how well they are done. So the planned steps use both, but stay editable.
- **Feedback** (+6 months, EEF): the session note's next step is the "where to next" of feedback. Putting it on the roadmap with a date makes it something the student acts on, which the EEF says feedback needs to work.
- **Parental engagement** (+4 months, EEF): parents help most by supporting habits and planning, not by teaching content. For younger students, a parent can see and tick off the week's steps; one reminder the afternoon before keeps it light.
- **Goal setting** (Locke and Latham, cited from memory): specific goals with a date lead to more effort than "do your best".

Sources opened: AERO "Tried and tested: spacing and retrieval practice" listing (edresearch.edu.au); EEF news, "What do we really know about cognitive science in the classroom?" (2021). EEF Toolkit strands as cited in the progress tracking brief.

## How the design follows the evidence

- **Targets**: a school assessment (date, grade now, grade aiming for) or a learning goal, optionally linked to one of the tutor's goals.
- **Steps**: small and dated. Anyone who plans can add, edit and tick them: the student (own login), a parent who manages them, the tutor, an admin. Steps show who added them.
- **Next steps join automatically**: each session note's next step becomes a step due by the next booked session (or a week later). No extra tutor time.
- **"Plan the steps for me"**: for an assessment, six steps spread from today to the day before (list the topics, self-test on hard parts, mixed practice, a timed practice test, fix mistakes, a last self-test). Under a week away, three steps. Everything can be changed.
- **Who drives it**: high school and tertiary students plan their own; for primary and middle school the steps mostly come from the tutor's next steps, with parents ticking off (brief, "Learning roadmaps").
- **One reminder** the afternoon before steps are due: to the student if they have their own login, otherwise to the parents who manage them. Never to the tutor. Nothing between 8pm and 8am.

## How we'll know it works

- share of steps ticked off by their date
- share of next steps ticked off before the next session
- for assessments with grades: the grade aimed for against the grade reached (once families add results)

## Privacy and child safety

- Tables `roadmap_targets` and `roadmap_steps` hang off `students`, so the shared access rules and automatic deletion apply. Families see only their own child; tutors only current, cleared students with two-step login.
- Grades are optional and stored only as the school writes them. No free-text fields for health or diagnosis.
- Parents who can't manage a child's account can read but not change the roadmap. Targets are closed, not deleted, and every change is in the audit log.
- Children's Online Privacy Code (exposure draft): data is limited to learning plans; a student with their own login is told on the roadmap that their parent or carer can see it, as the draft Code asks.
- Migration `20261029200100_progress_roadmaps.sql`; tests in `supabase/tests/progress_roadmaps.test.sql`.
