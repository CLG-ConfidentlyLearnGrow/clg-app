# Buttons that show they're working

## The problem

Some buttons (for example an admin confirming a parent and child, or
approving an invoice) take a few seconds. Nothing on screen changed while
they ran, so people pressed them again and again.

## What changed

- Every button that submits a form now switches itself off while the form
  is saving, and the pressed button shows a small spinning circle. When the
  work is done the button comes back (or disappears, if its job is done).
- This is built into the shared button (`src/components/busy-button.tsx`),
  so new forms get it for free. The main teal `Button` does it on its own;
  small or link-style buttons use `BusyButton` with their own look.
- Screen readers hear "working on it" on the pressed button.
- On the server, confirming a parent and child now only counts the first
  press, so a second press can't change the confirmation time. The other
  slow actions (confirm a check, confirm a curriculum, approve an invoice)
  were already safe to press twice: the database only acts once.

## Why (research and guidance)

- Families, students and staff are the users here, not learners in a
  lesson, so the guidance is about usability rather than teaching. Two
  well-known usability rules apply: always show people what the system is
  doing ("visibility of system status", Nielsen Norman Group), and give a
  visible sign within about one second of a press, or people assume it
  didn't work and try again.
- WCAG 2.2 (status messages, 4.1.3) asks that a change like this is also
  announced to screen readers, which `aria-busy` and the hidden "working on
  it" text do.
- The education evidence base (EEF, AERO, Evidence for Learning) has no
  direct finding on buttons. Its general point holds, though: tools should
  cut out frustration and wasted time so the time goes on learning.

## Legal rules it touches

None directly. Stopping double presses lowers the chance of a doubled
record (for example a payment action or a confirmation), which helps keep
records accurate under the Privacy Act (APP 10, quality of personal
information).

## Not covered

Search and filter boxes that just load a new page (such as "Find" or
"Filter") don't use this, because the browser already shows the page
loading.
