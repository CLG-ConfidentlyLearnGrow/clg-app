# A different colour for each profile

## The problem

People can hold several roles (admin, tutor, parent, student). Every
dashboard looked the same, so it wasn't obvious which profile you were in,
for example whether you could book sessions because you were a tutor or
because you were also an admin (Carla, 11 Nov 2026).

## What changed

- Each dashboard has its own colour, all soft earthy shades that sit with
  the bronze brand:
  - Admin: charcoal
  - Tutor: bronze (the main brand colour, as before)
  - Parent: sage green
  - Student: dusty blue
- Above every dashboard heading there is a coloured label naming it
  ("Admin dashboard", "Tutor dashboard", "Parent dashboard",
  "Student dashboard"). The heading, the bar under it and the side menu
  take that colour.
- The tabs across the top (for people with more than one role) each show a
  dot in their dashboard's colour, and the open tab is shaded in it.
- The colours live in `src/app/globals.css` and `src/lib/role-theme.ts`.
  Pages pass `role` to `SectionShell`, `Page` or `PageTitle`. Shared pages
  such as Sessions stay in the plain brand colours.
- Looks only: no change to what anyone can see or do. Access rules stay in
  the database.

## Why (research and guidance)

- Usability guidance (Nielsen Norman Group: "visibility of system status"
  and "recognition rather than recall") says people should always be able
  to see where they are, rather than remember it. A label plus a colour
  does this at a glance.
- Colour is never the only signal (WCAG 2.2, 1.4.1 Use of colour): the
  written label says which dashboard it is, for people who can't tell the
  colours apart.
- All text colours meet WCAG 2.2 AA contrast (4.5:1 or more) on white, on
  the cream page and on their own pale tint: admin 8.3:1, tutor 5.3:1,
  parent 5.0:1, student 5.6:1 (lowest of the three backgrounds).
- The education evidence base (EEF, AERO, Evidence for Learning) has no
  direct finding on dashboard colours. Its point about cutting needless
  mental load (cognitive load) applies: less effort working out where you
  are leaves more for the task.

## Legal rules it touches

Accessibility: Disability Discrimination Act 1992 (Cth) and the WCAG 2.2
AA standard it's usually measured against; UK Equality Act 2010 and the EU
Accessibility Act take the same approach. No personal data involved, so no
privacy change and no database change.
