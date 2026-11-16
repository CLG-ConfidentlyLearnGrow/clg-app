# First-time app tour

Asked for by Carla, 16 Nov 2026: "There will need to be an initial show how
to use the app - app tour - for all profiles so it actually takes the
person through all of the things and why those things are important to do
and why they need to know them."

New table `app_tour_progress` (migration `20261119300100_app_tour.sql`),
words in `src/lib/app-tours/`, pop-up in `src/components/app-tour.tsx`.

## 1. What it's for

The App guide (PR #140) answers "how do I…?" once someone knows what to
look for. A brand-new parent, student or tutor doesn't know that yet: they
don't know that a session offer closes after 3 days, that cancelling by text
doesn't count as notice, or that a lapsed Working with Children Check hides
a tutor's sessions. The tour fills that gap the first time someone opens a
dashboard: a short walk through each main part, with **why it matters** to
them, and **where to find it**. Trial families start on 30 Nov 2026, so the
tour is their first impression of the app.

## 2. What the evidence says

- **Explain why, not only how.** Adults learn and act on new routines best
  when they see why each one matters to them (relevance and purpose are
  central to adult learning and to motivation research). The EEF's
  [*Working with Parents to Support Children's Learning*](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/supporting-parents)
  guidance says communication with parents should be specific, easy to act
  on and clear about how it helps their child's learning. Every step in the
  tour has a "Why it matters" box, written to the reader.
- **Small chunks, one idea at a time.** AERO's
  [*Teaching how students learn* practice guides](https://edresearch.edu.au/resource-collections/teaching-how-students-learn-practice-guides)
  and NSW CESE's
  *Cognitive load theory: research that teachers really need to understand* (2017)
  recommend breaking new information into small parts, showing them in
  order, and cutting what isn't needed, because working memory is limited.
  Each step covers one part of the app in two short paragraphs, a reason
  and a "Find it" line. Detailed steps stay in the App guide.
- **Name the thing exactly as it appears.** Explicit instruction works best
  when the words match what the learner will see (AERO, explicit
  instruction). Menu items and buttons are in bold with their exact names,
  as in the App guide.
- **Parents help most by supporting learning at home.** Evidence for
  Learning's Toolkit rates
  [parental engagement](https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/parental-engagement)
  at about +4 months, strongest when it supports learning at home rather
  than general involvement. The parent tour explains the session note's
  "tip for home" and the roadmap in those terms.
- **Feedback and metacognition.** The Toolkit's
  [feedback](https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/feedback)
  (+6 months) and
  [metacognition and self-regulation](https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/metacognition-and-self-regulation)
  (+7 months) strands are why the tutor tour stresses a specific next step
  in every note, and the student tour stresses "How did it go?" after each
  session.
- **Don't trap people in a tour.** Nielsen Norman Group's
  [*Onboarding tutorials vs. contextual help*](https://www.nngroup.com/articles/onboarding-tutorials/)
  and [*Popups: 10 problematic trends*](https://www.nngroup.com/articles/popups/)
  find that people skip or forget long up-front tutorials, and resent
  pop-ups they can't close. So the tour always offers **Not now** and
  **Skip the tour**, closes with Escape or ×, shows "Step 3 of 10" and a
  progress bar, opens only once, and can be replayed or carried on from
  the App guide whenever the person wants it.

## 3. How the design follows the evidence

- **One tour per dashboard.** Parents, students (16+ and adult learners),
  tutors, and each admin level (Owner, Operations, Support, Finance) have
  their own tour, covering only what that person can see. Someone with
  several roles gets each tour the first time they open that dashboard.
- **Steps.** A welcome step (with **Start the tour** or **Not now**), then
  one step per main area (8 to 15 steps), each with what it is, "Why it
  matters", and "Find it". The last step points to the App guide and the
  What's new box.
- **Opens once.** The first dashboard page someone opens shows the tour.
  When they close or finish it, the app remembers how far they got and it
  doesn't open by itself again. If the "What's new" pop-up also has
  something, it waits for the next visit, so two pop-ups never stack.
- **Replay.** The top of the App guide has **Take the tour again** (or
  **Carry on the tour (step N)** if they stopped part-way). Admins who help
  families and tutors can open **See their tour** from those guides.
- **Showing it again after a big change.** Each tour has an edition number
  in `src/lib/app-tours/index.ts`. Raising it shows that tour once more to
  everyone on that dashboard.
- **Accessible.** It uses the browser's own dialog box (keyboard focus
  stays inside, Escape closes it), the step heading takes focus on each
  step so screen readers read it, and the colours are the dashboard's own.

## 4. Legal and privacy rules it touches

- **Privacy Act 1988 (APP 1, APP 11) and the Children's Online Privacy
  Code.** The only new data is one row per person per tour: which step they
  reached, whether they finished, and the tour edition. No personal details,
  no tracking of what they click. Rows are visible only to their owner
  (database access rule), written only through `app_tour_save()`, which
  checks the tour belongs to one of the person's own roles, and deleted
  with the account.
- **Child safety (SA Child Safe Environments, National Principles 3 and
  7).** Every tour tells people where **Child safety** is and to call 000 in
  an emergency. The student tour is written for 16+ learners and says who
  can see their progress (parents on their account and their tutor; never
  siblings).
- **Billing visibility.** The parent and student tours describe Billing as
  "if you pay", matching the rule that only bill payers see billing.
- No new rights or access are given: the tour only describes screens the
  person already has.

## 5. How we'll know it works

- Most new accounts finish the tour or close it after a few steps
  (`app_tour_progress.finished` and `step`, counted without names).
- Fewer "where do I…?" calls and problem reports from trial families in the
  first two weeks.
- Feedback in the "How easy the app is to use" area during the pilot.
