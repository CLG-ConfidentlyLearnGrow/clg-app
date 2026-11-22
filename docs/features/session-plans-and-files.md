# Session summary, plan for the next session, session files and plan materials

Requested by Carla, 21 Nov 2026:

- "Tutors need to send in the summary through the app, but also send in their plan for the next session (in total, these two things are only to take 15 minutes)."
- "Tutors need a space they can upload images and/or documents for the students to reference from that session in future (addition to the session summary)."
- "Tutors need to be able to link materials for the session plan so they know they have found the materials they need for the next session and make it super easy to access for them."

Builds on progress tracking (`progress-tracking.md`), the session note (summary), the materials library (`materials.md`) and evidence of learning (`learning-evidence.md`).

## What it is for

Tutors are already paid 15 minutes after each session: 5 minutes for the session summary and 10 minutes to plan the next session (`billing.md`, 12 Nov 2026). Until now the app only collected the summary. The plan lived in each tutor's head or notebook, so CLG could not see it, a cover tutor could not pick it up, and nothing showed the tutor had the right materials ready. Students also had no place to look back at what was on the whiteboard.

## What the evidence says

- **Explicit teaching and lesson planning** (AERO, "Explicit instruction" and "Tried and tested" practice guides; Rosenshine, Principles of Instruction): effective lessons start with a short review of earlier learning, state one clear learning intention, model the new step, give guided practice, then independent practice, and check for understanding. The plan form asks for exactly these: **Focus** (learning intention), **Review first** (daily review and retrieval), **How you will teach it** (model, guided, independent) and **How you will know it worked** (success criteria).
- **Feedback** (EEF, +6 months): feedback works when the next step is specific and acted on. The plan's focus builds directly on the summary's next step, so the next session acts on the feedback.
- **One to one tuition** (EEF, +5 months): works best when sessions are well planned and linked to what the learner needs next. Linking the plan to the next booked session and the materials library keeps each session connected to the last.
- **Retrieval practice and spaced review** (EEF cognitive science in the classroom review; AERO): a short recall at the start of a session strengthens memory. "Review first" prompts this every session.
- **Worked examples and dual coding** (EEF cognitive science review): seeing a worked example again later supports independent practice. Session files (a photo of the whiteboard or worked example) let the student look back before the next session.
- **Tutor workload** (EEF, "Making best use of teaching assistants" and the tuition guidance): planning should be short and focused. The form shows the 15-minute guide and a live "time so far", needs only two plan boxes (focus and how), and makes the rest optional.

## How the design follows the evidence

- **One form, two parts** on the student's progress page: *Part 1: Session summary (about 5 minutes)* and *Part 2: Plan for the next session (about 10 minutes)*. A banner shows "15 minutes in total (paid): about 5 for the summary and about 10 to plan the next session" and the minutes so far (amber with a gentle nudge after 15 minutes). Saved as one step: **Save summary and plan**.
- **When the plan is needed**: whenever the student came. If the student was absent, the plan is optional. The browser marks the needed boxes so nothing is lost by a round trip, and the server checks again before anything is saved.
- **Linked to the next session**: when saved, the plan is linked to the next booked session with the same tutor. The tutor's Home overview has **Plans for your coming sessions** showing each coming session's plan focus (or "No plan linked yet") with a link to the plan.
- **Materials**: the plan form lists the materials from the library that fit the student (the same list as the summary's "Booklet or materials used"); the tutor ticks up to 10. The plan card lists them with a link that opens each stamped copy (the existing materials route, daily limit and logging still apply). **Other resources** covers anything outside the library.
- **Session files**: one file can be added with the summary, and more later (up to 10 per session) under **Recent sessions**, for 7 days. PDF or photo, up to 3.5 MB (the upload limit of the app's forms; the file store allows 5 MB).
- **Correcting**: the tutor can add or change the plan and add or remove files for 7 days after the summary, like correcting the summary itself. Admins can at any time.
- **Who sees what**: the summary and files: the student, their family, their current tutors and admins. The plan and its materials: the student's current tutors (so a cover tutor can pick it up) and admins only. Families already see the next step, and CLG's materials are staff resources.

## Legal rules this touches

- **Privacy Act 1988 (APPs) and the Children's Online Privacy Code**: session files are children's personal information (student work, possibly handwriting or a name). APP 3: collect only what is needed, so the form says "Photos of work only, never of the student". APP 11: files sit in a private file store, in a folder named for the student; every upload, record and download is checked against that student's access rules in the database; links to open a file last one minute and are never cached. APP 12: the student and family can open every file. Retention: records hang off `session_notes` and `students`, so automatic deletion removes them, and their stored files are queued and removed by the daily job.
- **Child safety (SA Child Safety (Prohibited Persons) Act, CLG Child Safe Policy)**: no photos of children are invited. The concerning-words check now also reads plans and file names, so a worrying phrase in a plan reaches the Child Safety Officer and deputy like any other tutor text. Plans are never shown to families, so they are not a channel to contact a child.
- **Employment (Miscellaneous Award and Post-Secondary Award)**: the 15 minutes is already paid per session as "session summary and next session planning" (`billing_build_summary_pay`). Nothing about pay changes. The guide sets the expectation of about 15 minutes; it is not a hard limit and no one is penalised for going over.
- **UK and EU (later)**: GDPR data minimisation and storage limitation are met the same way (only work, deleted with the student).

## Efficiency

- Access rules wrap `private.is_admin()` and `auth.uid()` in `(select ...)` so they are worked out once per query.
- Indexes: plans by student and date, by next session (partial, only linked plans), by tutor; files by summary and by student; linked materials by material.
- The progress page reads plans and files once each, only for the summaries it shows. The Home overview reads plans for at most the 5 sessions it lists.
- No new packages. The daily progress job now clears both file queues in one run.

## How we will know it works

- share of summaries saved with a plan (target: all sessions the student attended)
- median time to write the summary and plan (admins see writing time; target about 15 minutes)
- share of plans with at least one linked material
- tutors' pilot feedback on whether the plan and materials made the next session easier to start

## Technical notes

- Migration `supabase/migrations/20261123620100_session_plans_and_files.sql`; tests `supabase/tests/progress_session_plans.test.sql`.
- Tables: `session_plans` (one per summary), `session_plan_materials`, `session_note_files`, `session_file_removals`. File store: `session-files`.
- Function: `public.save_session_plan(note, focus, activities, review_first, success_check, other_resources, materials)`. Daily job functions: `session_files_to_remove`, `session_files_removed` (secret key only).
- App: `src/lib/session-plans.ts` (the 15-minute guide), `src/lib/session-plans-server.ts` (saving), the progress page and forms, `src/app/session-files/[id]/file/route.ts` (opens a file), `src/app/api/progress/cron/route.ts` (removes deleted files), the tutor Home overview.

## Missing plans followed up, and no plan without a next session (Carla, 22 Nov 2026)

Carla's note on Emma's Job Proposal: the 12-hour missing flag should cover
the session summary and the plan for the next session, and no plan is
needed when there is no next session.

- **No next session, no plan needed.** The form only asks for the plan when
  the student came and the tutor has a coming session booked with them. The
  server checks the same thing before saving.
- **Followed up like the summary.** If the summary is in but the plan is
  missing (the student came and a next session is booked), the tutor gets
  "Plan for the next session due" at 6 hr and the owner and Operations
  admins get "Plan for the next session missing" at 12 hr. Each person is
  told once per session. Quiet hours still apply.
- **Evidence:** the same as above. Planning the next session from the
  summary's next step is what links feedback to the next lesson (EEF
  feedback guidance; AERO explicit instruction). Asking for a plan only when
  a session is booked keeps tutor workload to what is useful (EEF tuition
  guidance).
- **Legal:** no new information is collected. The notices name the student
  and tutor, which admins can already see.
- **Where:** `supabase/migrations/20261124710400_plans_missing_12_hours.sql`
  (new hourly job `clg-plan-reminders`), tested in
  `supabase/tests/progress_plans_missing_12_hours.test.sql`.
