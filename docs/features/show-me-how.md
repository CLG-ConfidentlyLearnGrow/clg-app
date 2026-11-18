# "Show me how" refresher on every page

Asked for by Carla, 18 Nov 2026: "Need to be able to get up the how to use
the section if a person is needing a refresher."

No database change and no migration. Words come from the App guides in
`src/lib/app-guides/`; which guide parts belong to which page are listed in
`src/lib/app-guides/page-help.ts`; the button and pop-up are in
`src/components/page-help.tsx`, shown by `DashboardFrame`.

## 1. What it is for

The first-time app tour (PR #156) opens once per dashboard, and the App guide
(PR #140) holds every "how to" step, but finding a step means leaving the
page, opening the guide and searching. Someone who used a page weeks ago (a
parent cancelling a session once a term, a tutor renewing a check once a
year, an admin sending a contract) needs a quick reminder of how that page
works, right where they are.

## 2. What the evidence says

- **Help at the point of need.** Nielsen Norman Group's
  [*Onboarding tutorials vs. contextual help*](https://www.nngroup.com/articles/onboarding-tutorials/)
  finds that people forget up-front tutorials and do better with help they
  can pull up in context, when they are doing the task. The tour stays as an
  introduction; the refresher is the "pull" help on each page.
- **Retrieval and spaced reminders.** Learning sticks better when people come
  back to it after a gap and practise it (AERO,
  [*Spacing and retrieval practice*](https://www.edresearch.edu.au/resources/spacing-and-retrieval-practice-guide)).
  Many CLG tasks happen only now and then, so a short reminder at the moment
  of doing the task supports that natural spacing.
- **Small chunks, matching what is on screen.** AERO's explicit instruction
  and cognitive load guidance (and NSW CESE, *Cognitive load theory*, 2017)
  recommend showing only what is needed, in order, with words matching what
  the learner sees. The pop-up shows only the guide part (or the few tasks)
  for the page, each task folded until opened, with button names in bold.
- **Clear, actionable communication with families.** The EEF's
  [*Working with Parents to Support Children's Learning*](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/supporting-parents)
  asks for specific, easy-to-act-on communication. Each step is one action.

## 3. How the design follows the evidence

- A **Show me how** button (with a "?" circle) sits beside the heading of
  every dashboard page, in that dashboard's colours. It is not shown on the
  App guide page itself, which already holds every step.
- It opens a pop-up titled with the page name, listing the matching App guide
  part(s). Broad parts (for example Staff and accounts) are narrowed to the
  tasks for that page. If there is only one task, it opens straight away.
- The pop-up also has **Open the whole App guide** (with search) and **Take
  the app tour again**. A page with no listed help shows the guide's
  "Getting started" or "Getting around" part, so the button never shows
  nothing.
- It uses the browser's own dialog box: it keeps keyboard focus inside,
  closes with Escape, × or **Close**, and is read correctly by screen readers.
- The Finance admin guide now has the **Employment contracts** part (Finance
  admins can open Contracts, but their guide did not cover it).

## 4. Legal rules it touches

- **Privacy Act and APPs; Children's Online Privacy Code.** No personal
  information is shown, stored or sent: the pop-up shows the same fixed guide
  words as the App guide page. Each person only gets the guide for the
  dashboard they are on (their own role, or their own admin level), the same
  rule as the App guide (`ownGuide` in `src/lib/app-guides/index.ts`).
- **Accessibility (Disability Discrimination Act 1992; WCAG 2.2).** Native
  dialog, labelled heading, visible keyboard focus and close options.
- No database tables or rules change, so no new database tests are needed.

## 5. Keeping it current

When a page's words change, update the App guide as usual; the refresher
follows. When a new side-menu item is added, add a line for it in
`src/lib/app-guides/page-help.ts`.
