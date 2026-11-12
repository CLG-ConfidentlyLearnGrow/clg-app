# To-do counts across the app

Asked for by Carla, 11 Nov 2026: "Please have a notification (numbered)
under the tab this is in so admin know something needs to be completed
(please do this numbering for all things that need to happen - even the
Matching, it should be for example 'Matching (4)')."

## 1. What it's for

Staff, tutors and families each have a few jobs the app is waiting on:
an invoice to approve, a session note to write, a child's details to
finish. Until now, only some menus showed a number, and the dashboard tabs
at the top showed none, so a job hidden in another section or dashboard
was easy to miss.

Now every place where something needs doing shows a number, and the
numbers add up the same way everywhere:

- **Side menu items** show how many things need doing in that section.
- **Dashboard tabs at the top** (Admin, Tutor, Parent, Student) show the
  total for that dashboard, so someone with several roles sees at a glance
  where work is waiting.
- **Top bar**: "Sessions" shows the total from the Sessions page menu, and
  "Matching" shows how many subjects are waiting for a tutor.
- **Links** to Billing and to Privacy requests show their own number.

No number is shown when there's nothing to do.

### What is counted

| Where | Counts |
| --- | --- |
| Admin > Families | parent and child links to confirm, possible double-ups |
| Admin > Matching | student subjects waiting for a tutor |
| Admin > Tutors and checks | tutor checks waiting to be confirmed |
| Admin > Progress | term reviews to check, session notes 48 hr or more late |
| Admin > Curriculum | curriculum files waiting to be confirmed |
| Admin > Staff and accounts | staff invitations that ran out unused (resend or remove) |
| Admin > Privacy and records | records due for deletion in 30 days, open privacy requests, open data breaches |
| Billing > Family billing | families on hold for an overdue invoice |
| Billing > Invoices | invoices waiting for approval |
| Billing > Staff pay | staff hours waiting for approval |
| Tutor > Your students | session notes to write, term reviews to write, new uploads from families |
| Tutor > What you teach | 1 while it's empty |
| Tutor > Child safety checks | checks missing, expiring within 60 days or expired |
| Parent > Your children | children whose details need finishing |
| Parent > Billing link | plan to choose, payment terms to agree, automatic payment to set up |
| Student > Your learning | roadmap steps past their due date (plus billing for an adult learner who pays) |
| Sessions (top bar) | offers to answer, unread notices, next term questions, "How long to book", library hours (the same as the Sessions page menu, which the scheduling module owns) |

The admin tab adds up the admin menu and the billing menu. The parent tab
adds up the parent menu and family billing.

Left out on purpose, because they stay on the list until someone else acts
and would make the number feel like noise: stalled students on Progress
(they are shown there, but are a "keep an eye on" list), family replies to
term reviews (no "done" step yet), staff invitations that haven't run out
yet (waiting on the invitee), and the Teams and Materials pages (they keep
their own numbers on their own menus).

## 2. What the evidence says

The education evidence bases (EEF, AERO, Evidence for Learning) don't
study app menus. Two findings from them still shape this:

- **Timely feedback matters.** The EEF Teaching and Learning Toolkit rates
  feedback as one of the highest-impact, lowest-cost approaches, and the
  EEF's guidance report *Teacher Feedback to Improve Pupil Learning* (2021)
  stresses that feedback must be timely to be acted on. Session notes and
  term reviews are CLG's feedback to families; a number on the tutor's
  menu helps them go out on time.
- **Workload is a real cost.** Australian work on teacher workload (for
  example AERO's and the national teacher workforce reviews) points to
  admin load crowding out teaching time. One clear "what's waiting" signal
  saves staff from clicking through every section to check.

From usability research:

- Nielsen Norman Group's "visibility of system status" heuristic: show
  people what needs attention without making them look for it.
- Badges work best when the number means "you can act on this now". A
  number that never goes down gets ignored ("notification fatigue"), which
  is why the left-out items above aren't counted.
- WCAG 2.2: a number alone in a circle isn't clear to screen readers, so
  each one reads as "4 to do".

## 3. How the design follows the evidence

- One database call (`public.to_do_counts()`) works out every number for
  the person viewing. Menus, tabs and the top bar all read from it, so
  numbers never disagree between pages.
- Only things the person can act on are counted. A support admin doesn't
  see owner-only numbers; a tutor sees only their own students.
- The same small badge style is used everywhere, in the dashboard's colour.

## 4. How we'll know it works

- Session notes written within 24 hr (already measured on Admin >
  Progress) should go up for tutors.
- Fewer invoices and tutor checks left waiting more than a few days.
- In the pilot, ask Carla, Lauren and Amy whether the numbers match what
  they expect, and whether any feel like noise.

## 5. Privacy and child safety

- No new data is stored. The function only counts rows.
- It runs as the person viewing (security invoker), so row level security
  decides what is counted, exactly as on the pages themselves. Admin-only
  numbers are also guarded by admin level inside the function. Signed-out
  visitors can't call it.
- A number never reveals more than the page it leads to.
- Rules touched: Privacy Act APP 11 (security of personal information)
  and the Children's Online Privacy Code (least access): unchanged, as the
  counts follow existing access rules. UK and EU GDPR data minimisation:
  only counts leave the database.

## Technical notes

- Migration: `supabase/migrations/20261111700100_to_do_counts.sql` (needs
  the scheduling module's `20261111600800_action_counts.sql` first).
- Tests: `supabase/tests/to_do_counts.test.sql`.
- App: `src/lib/to-do-counts.ts` (loads once per page),
  `src/components/count-badge.tsx`, used by `RoleTabs`, the top bar in
  `src/app/layout.tsx`, and each dashboard page.
- A new section that needs a number: add a row to `to_do_counts()` with
  its area and section id, and the menu picks it up.
