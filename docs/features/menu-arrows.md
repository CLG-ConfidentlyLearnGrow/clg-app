# Side menu arrows that open sub-tabs anywhere

Asked for by Carla, 20 Nov 2026: "If it is a tab with sub-tabs in it, need
to have the arrows always there, and click on the arrows from any screen
without loading up and being taken to the first tab of that section."

## 1. What it is for

Some side menu headings have smaller tabs (sub-tabs) under them, for
example **Sessions** (Overview, Bookings, Notices and more) and **Billing**
(Family billing, Invoices, Staff pay and more). Before this change, a
heading only knew about its sub-tabs while you were on that heading's own
page. Anywhere else the arrow did not show, and the only way to reach a
sub-tab was to open the heading's first tab and then pick again.

Now:

- Every heading with sub-tabs always shows an arrow at the end of its row,
  on every page, on computers and phones, for every role.
- Clicking the arrow opens or closes the sub-tabs right there, without
  loading a page. You can then go straight to the sub-tab you want.
- Clicking the heading's name still opens that section, as before (and on
  the section you are already in, it still folds or unfolds the sub-tabs).
- The folded-number badge from 20 Nov still works: a folded heading shows
  the total of its sub-tabs' numbers, and an open heading leaves the
  numbers to its sub-tabs.

Matching has no sub-tabs in the side menu (its "Students waiting" and
"Reports" views are buttons on the Matching page), so it has no arrow.

## 2. Research it rests on

- Cognitive load theory, which underpins the Evidence for Learning and AERO
  guidance on explicit teaching and managing working memory: people do
  better when they do not have to hold steps in mind or take detours to
  reach what they need. Showing sub-tabs in place removes an extra page
  load and an extra choice.
- The same principle shows up in the EEF guidance on metacognition: clear,
  predictable structure lets people see where they are and plan where to
  go next. A consistent arrow on every heading with sub-tabs makes the menu
  predictable.
- Web accessibility guidance (WCAG 2.2, and the W3C "disclosure" pattern):
  the arrow is a real button with `aria-expanded` and `aria-controls`, a
  spoken name ("Show Billing sub-tabs"), a visible keyboard focus outline
  and a 36 pixel wide target, so screen reader, keyboard and touch users
  can all use it.

## 3. How it works

- Each heading's sub-tab list now lives in one shared file,
  `src/lib/menu-sub-tabs.ts`. The side menu (`src/lib/dashboard-menu.ts`)
  attaches the lists to every heading on every page, and each page reads
  the same list to know which sub-tab is open, so they cannot drift apart.
- Sub-tab numbers in the menu come from the to-do numbers the menu already
  reads, so no new database reads were added. On a heading's own page, the
  page's own up-to-date numbers replace them, as before.
- The menu remembers which headings the person opened or closed until they
  move to another page, then goes back to showing only the current
  heading's sub-tabs.

## 4. Legal rules it touches

None. No data is collected, stored or shown that was not shown before;
each sub-tab list follows the same role and admin level rules as the
pages themselves (for example, only the owner sees "Who checks app issues",
and only front-desk admins see "Book a session"). Accessibility supports
the Disability Discrimination Act 1992 (Cth) expectation that online
services are usable by people with disability.
