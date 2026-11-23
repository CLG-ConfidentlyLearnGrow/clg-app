# Personal and team learnings

Carla, 22 Nov 2026: "Anyone can add to personal learnings, then team learnings are adapted from personal learnings when approved by either myself or Emma." This comes from the How We Do Things guide, where staff note what they learn and the best lessons are shared with the whole team.

## What it is for

Tutors and admin staff learn things every week: a way of explaining fractions that finally worked, a better way to reply to a worried parent, a booking mix-up to avoid. Today those lessons stay in one person's head. A simple place to write them down helps each person improve, and sharing the best ones lets the whole team improve faster, especially new tutors.

## What the evidence says

- **Reflective practice and professional learning** (AERO, "Effective professional learning", and the EEF guidance report "Effective Professional Development", 2021): professional development works best when it builds knowledge, motivates staff, develops techniques and embeds practice. Writing down what worked and why is a low-cost way to embed practice.
- **Collaborative learning among teachers** (AERO and Evidence for Learning on professional learning communities): teachers improve more when they share and discuss practice, with clear agreement on what good practice looks like. A reviewed team list gives one shared reference instead of scattered advice.
- **Quality control on shared advice** (EEF on implementation): ideas spread best when someone checks they fit the organisation's approach. That is why team learnings are adapted by Carla or Emma, not published straight away.

## How the design follows it

- Every tutor and admin has **Learnings** in their side menu.
- **My learnings**: a short title and the learning. Private to the person who wrote it. They can change or remove it at any time before it is adopted.
- **Suggest for the team** sends it to the owner and Operations admins (Carla and Emma), with an app notice. A number on their **Learnings** menu item shows suggestions waiting.
- Carla or Emma **adapt** a suggestion: they change the words so they suit everyone, then choose **Add to team learnings**. The person is told, and their own copy shows "Now a team learning". Or they **decline** with an optional kind note, which the person sees; they can change it and suggest it again.
- **Team learnings** are read by every tutor and admin. Carla and Emma can change or remove them, or add one directly.

## How we will know it works

- learnings written per staff member each term
- suggestions per term, and the share adopted
- team learnings mentioned in check-ins and training reviews

## Privacy, child safety and legal notes

- **Privacy Act 1988 (APPs 3, 6 and 11) and the Children's Online Privacy Code**: learnings are about practice, not people. The form reminds staff not to write students' or families' names, and team learnings are reworded by Carla or Emma before anyone else sees them. Personal learnings are visible only to their writer, and to Carla and Emma once suggested. Access rules are in the database (row level security), not only in the page.
- **Employment**: learnings are not performance records and are not used for discipline. Declining a suggestion only means it is not added to the team list.
- **UK and EU (GDPR)**: the same minimal fields and access apply; legitimate interest is the basis.

## Technical

- Migration `20261124711500_personal_team_learnings.sql` (module: staff). It adds the table `public.learnings` and the functions `learning_save`, `learning_remove`, `learning_suggest`, `learning_adopt`, `learning_decline`, `team_learning_save`, `team_learning_remove` and `learnings_waiting_count`. Safe to run more than once.
- Page: `/learnings`. Actions: `src/app/actions/learnings.ts`.
- Tests: `supabase/tests/staff_learnings.test.sql`.
