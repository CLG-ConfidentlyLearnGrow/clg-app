# Every press shows straight away

Asked for by Carla, 16 November 2026: "When any button is clicked, there
needs to be a visual to indicate the button has been clicked."

## The problem

The busy buttons from 3 November (see `busy-buttons.md`) show a spinner on
form buttons while they save. Many other things a person can press did not
change at all when pressed: side menu links, profile tabs, the "Show / Hide"
titles on cards, the What's new pop-up buttons, the app tour buttons, small
link-style buttons, and every link that opens another page. On phones and
tablets there is no "hover" look either, so a tap gave no sign at all until
the next page appeared. Pages in this app are built fresh each time (none
has a "loading" page), so a slow connection could leave a person staring at
an unchanged screen for a second or more.

## What changed

1. **Pressed look on everything you can press.** Buttons, links, tabs and
   "Show / Hide" titles shrink very slightly, darken, and get a soft bronze
   glow the moment they are pressed. It is set once, for the whole app, in
   `src/app/globals.css`, so every current and future button gets it with no
   extra code (including the app tour, which is in another pull request).
2. **Quick taps are visible.** A tap on a phone can be over too fast to see,
   so `src/components/press-feedback.tsx` holds the pressed look on for at
   least a sixth of a second. It also switches on the pressed look on
   iPhones and iPads, which only show it once a page listens for touches.
   Pressing Enter (or Space on a button) shows it too.
3. **Loading bar.** When a link or a search opens another page, a thin
   bronze bar slides across the top of the screen until the page arrives.
   Screen readers hear "Loading the page". The pressed link is marked busy.
4. **More buttons show a spinner and cannot be pressed twice.** The shared
   `Button` and `BusyButton` now take `busy`, for work the page runs itself
   (such as uploading files first). These now use it: the tutor application,
   problem reports, check uploads, materials and training uploads, two-step
   login set-up, email-link buttons and the ready-made action form. The
   last plain send buttons in admin pages (problem reviewers, deleting a
   problem report, deleting a report, the quick report buttons) now use
   `BusyButton`.
5. **Clearer keyboard focus ring.** The ring now uses the deeper bronze
   (#76573a) instead of the light brand bronze, because the light bronze is
   too faint on the cream page.

## Why (research and guidance)

- The people pressing these buttons are families, students and staff, so
  the guidance is mostly about usability. Nielsen Norman Group's first
  usability rule is "visibility of system status": people should always see
  that the system has heard them. Their response-time guidance says a
  reaction within about a tenth of a second feels instant, and that people
  lose confidence and press again after about one second with no sign.
- Apple's and Google's design guides both ask for a visible "pressed" state
  on every touch target, because touch screens have no hover.
- WCAG 2.2 (the accessibility standard Australia follows):
  - 2.4.7 and 2.4.13: the keyboard focus must be clearly visible. The new
    ring is about 6:1 against cream and 7:1 against white.
  - 1.4.11: shapes that carry meaning need 3:1 contrast. The loading bar
    is brand bronze, 3.5:1 on the white top bar.
  - 2.3.3: movement should respect a "reduce motion" setting. With it on,
    pressed items darken but do not shrink, the loading bar stays still,
    and spinners turn slowly.
  - 4.1.3: status changes are announced to screen readers ("Loading the
    page", "working on it").
- Education evidence (EEF, AERO, Evidence for Learning) has no finding on
  buttons as such. The broader point from cognitive load research, which
  all three draw on, applies: anything that makes a learner or parent stop
  and wonder whether the tool worked takes attention away from the
  learning. Younger students in particular repeat-tap when nothing happens.

## Legal rules it touches

None directly. Stopping double presses lowers the chance of doubled records
(for example a doubled application or upload), which helps keep records
accurate under the Privacy Act (APP 10, quality of personal information).
Meeting WCAG 2.2 supports CLG's duty not to exclude people with disability
(Disability Discrimination Act 1992; the UK Equality Act 2010 and the EU
Accessibility Act are similar).

## Not covered

- The look of the header is being redesigned in another pull request, so
  the header's own buttons were not restyled here. They still get the new
  pressed look, because it applies to every button.
- No database change, so no migration.
