# What's new pop-up

Asked for by Carla, 15 Nov 2026: "Every time there is a new update in the
app for that profile's part of the app, the app will offer a pop up of what
has been updated, added and/or removed." To be working from 30 Nov 2026,
when the app goes live for the trial families.

## 1. What it's for

The app will change often during the pilot and through 2027. When a button
moves or a step is added, families and tutors who aren't told get stuck,
book the wrong way, or message CLG to ask. A short note at the right moment,
only about their own part of the app, saves that confusion without making
anyone read about changes that don't affect them.

## 2. What the evidence says

- **Tell people about a change, and keep telling them in the same place.**
  The EEF's guidance report
  [*A School's Guide to Implementation*](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/implementation)
  stresses clear, timely communication about what is changing and why, so
  the people affected can adjust their practice. A short, regular "what's
  new" note does that for the app.
- **Keep messages to families simple and relevant.** The EEF's
  [*Working with Parents to Support Children's Learning*](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/supporting-parents)
  recommends communication that is easy to take in and tailored to the
  family. Parents only see parent changes; each change is one or two plain
  sentences.
- **Don't overload working memory.** AERO's
  [*Teaching how students learn* practice guides](https://edresearch.edu.au/resource-collections/teaching-how-students-learn-practice-guides)
  (drawing on cognitive load theory) recommend breaking new information into
  small parts and cutting what isn't needed. The pop-up shows at most three
  updates, each a short list labelled New, Updated or Removed; anything older
  is on the "What's new" page.
- **Pop-ups interrupt, so use them sparingly and make them easy to close.**
  Nielsen Norman Group's
  [*Popups: 10 Problematic Trends and Alternatives*](https://www.nngroup.com/articles/popups/)
  finds overlays annoy most when they appear before people get any value
  (for example straight after login), interrupt a task, stack up, or are
  hard to close, and says to save modals for crucial information at the
  right time. So the pop-up only appears when there really is a change to
  that person's part of the app, shows once per update, appears only as a
  dashboard page opens (never part-way through filling something in), never stacks (all unseen updates share one
  box), and closes with one tap, the Escape key or the ×. If Carla finds it
  intrusive in the pilot, the next step is a small "What's new" badge
  instead of opening the box by itself.

## 3. How the design follows the evidence

- **Per dashboard.** Each change is ticked for the dashboards it applies to
  (admin, tutor, parent, student). Someone with several roles sees the admin
  changes on the admin dashboard and the tutor changes on the tutor
  dashboard, each once.
- **Only what's new to you.** Each dashboard remembers when the person last
  closed the pop-up. Updates from before they got a role are skipped, so a
  new family isn't greeted with old news.
- **Always findable.** A "What's new" link in the footer, and "See all
  updates" in the pop-up, open every update for the person's dashboards.
- **Written by admins.** Owner and operations admins write updates under
  Admin > What's new: a title, then each change with its kind and
  dashboards. Publish now, or pick a day it starts (for example a welcome
  note for trial families on 30 Nov). Published updates are locked; to fix
  one, take it back to a draft, fix it and publish again, and it shows
  fresh to everyone on those dashboards.

## 4. How we'll know it works

- Fewer "where has X gone?" questions and problem reports after an update.
- Feedback in the "How easy the app is to use" area stays steady or improves
  after updates during the pilot.

## 5. Privacy, child safety and the law

- **Data held**: updates contain no personal details. The only personal
  information is the time each person last closed the pop-up on each of
  their dashboards (account id, dashboard, time). That is the minimum needed
  (Privacy Act, APP 3 and APP 11) and is deleted with the account.
- **Access rules in the database**: parents and students can't read admin or
  tutor changes, nobody but full admins sees drafts, and nobody writes the
  tables directly; everything goes through checked functions. Tested in
  `supabase/tests/whats_new.test.sql`.
- **Children's Online Privacy Code (draft) and the UK Age Appropriate Design
  Code**: students using the app are 16+, but the pop-up is still designed
  without nudges: no tracking of what people click, no "remind me later"
  pressure, and one obvious way to close it.
- **Accessibility (Disability Discrimination Act 1992, WCAG 2.2)**: uses the
  browser's own dialog box, so keyboard focus stays inside it, Escape closes
  it, and screen readers announce it by its heading.
- **Activity log**: publishing, taking back and deleting updates are logged
  with ids only.
