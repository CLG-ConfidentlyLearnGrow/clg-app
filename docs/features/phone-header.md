# Phone top bar and logo (16 Nov 2026)

## What Carla asked for

On a phone, the open-book logo looked squashed, and the top links (Home,
Child safety, Feedback, Your privacy, Report app issue) wrapped into two
uneven rows with "Signed in as" and Sign out squeezed underneath. Carla
asked for a clean, easy-to-tap top bar.

## What changed

- **Logo.** The logo now keeps its true shape (about 1.8 times wider than
  it is tall) at every screen size. Before, the links took the space and
  the browser squeezed the logo narrower.
- **Phone and small tablet (under 1024 pixels wide).** The top bar holds
  three things: the logo on the left, the red **Child safety** button, and a
  **Menu** button on the right. **Menu** opens a panel under the bar with
  Home, Feedback, Your privacy and Report app issue, each on its own row,
  then the signed-in name and **Sign out**. The panel closes when a link is
  tapped, when the person taps outside it, presses Escape, or moves page.
- **Computer (1024 pixels and wider).** The same as before.

There is no database change.

## Research it rests on

- **Keep safety reporting one tap away.** The National Principles for Child
  Safe Organisations (Principle 6) and the Office of the Children's Guardian
  guidance ask that children, young people and families can raise a concern
  easily. **Child safety** therefore stays visible in the top bar on every
  screen and is never hidden inside the menu.
- **Large tap targets.** WCAG 2.2 (success criterion 2.5.8) sets a 24 pixel
  minimum and Apple and Google recommend about 44 to 48 pixels. Every phone
  menu row is at least 48 pixels tall and the buttons at least 44 pixels.
- **Label the menu button with a word.** Nielsen Norman Group testing found
  that a menu icon with the word "Menu" is found more readily than an icon
  alone, especially by less frequent users. The button shows the word
  "Menu" (or "Close" when open) beside the icon, except on very narrow
  phones (under 360 pixels), where the word is kept for screen readers only.
- **Less clutter, less effort.** Cognitive load research used in education
  (Sweller; summarised by AERO and Evidence for Learning) shows that removing
  unneeded detail helps people focus on the task. A calm top bar leaves the
  page itself as the focus for parents and learners.

## Legal rules it touches

- **Child safety (SA Children and Young People (Safety) Act 2017, National
  Principles).** The concern button stays visible and one tap away.
- **Accessibility (Disability Discrimination Act 1992, WCAG 2.2 AA as the
  usual standard).** Tap sizes, keyboard support (Escape closes the menu),
  and screen reader labels (the button says whether the menu is open).
- **Privacy.** No change to what anyone can see. The signed-in name is
  shown only to the person signed in, as before.
