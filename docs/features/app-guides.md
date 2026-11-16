# App guides (a handbook for each profile)

Asked for by Carla, 16 Nov 2026: "Will need an app handbook for each
profile (and each type of admin role), with the appropriate handbook/s
available to the appropriate accounts. It takes through what can be
achieved and how things can be done. It should be simple and easy to
follow."

No database change. New page `/guide`, words in `src/lib/app-guides/`.

## What it's for

Trial families start on 30 Nov 2026, and full use starts in 2027. Most
families will use the app on a phone, between other things, and won't read
a manual front to back. When they get stuck ("how do I cancel?", "where do
I pay?") they need the steps for that one task, in words that match the
screen. The same is true for new tutors and for office staff CLG adds as
it grows. Today the only help is CLG on the phone, which doesn't scale to
20+ tutors and 100+ sessions a week.

The tutor **Handbook** (Training, PR #127) is CLG's policy and "what to do
if" guide for staff. This is different: a "how to use the app" guide for
every account, including parents and students, so it is its own tab
(**App guide**) rather than more Handbook pages.

## What the evidence says

- **Parental engagement works when it is specific and easy to act on.**
  The EEF's guidance report *Working with Parents to Support Children's
  Learning* recommends simple, low-effort, specific communication with
  parents, and warns that unclear or effortful systems put off the families
  who most need support
  (https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/supporting-parents).
  Evidence for Learning rates parental engagement at about +4 months
  (https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/parental-engagement).
  A family that can approve a time, add away dates or read the next step
  without ringing CLG is more engaged in the learning.
- **Explicit, step-by-step instruction and low cognitive load.** AERO's
  guidance on explicit instruction and cognitive load theory: break a task
  into small steps, show them in order, and remove anything that isn't
  needed for the task at hand
  (https://www.edresearch.edu.au/research/practice-guides/explicit-instruction;
  https://www.edresearch.edu.au/research/research-reports/cognitive-load-theory-research-teachers-need-understand).
  The same applies to adults learning a new system: numbered steps, one task
  at a time, with the exact button names, and the rest folded away.
- **Worked examples** (EEF and AERO on worked examples): seeing each step of
  a finished example is faster to follow than a description of the rules.
  Each task is written as the actual clicks in order.
- **Plain language.** The Australian Government Style Manual: short
  sentences, common words, the reader's task first, and headings that say
  what the section helps you do
  (https://www.stylemanual.gov.au/writing-and-designing-content/clear-language-and-writing-style/plain-language-and-word-choice).
  Task headings are verbs ("Cancel one session", "Pay an invoice now").
- **Need to know.** Each admin level only sees its own tools (admin levels,
  PR #50). Showing a Support admin steps for screens they can't open adds
  load and confusion, and describes tools they shouldn't use.

## How the design follows the evidence

- **One guide per profile**: parents and carers; students 16+ (including
  adult learners who pay for themselves); tutors; and one per admin level
  (Owner, Operations, Support, Finance). An Operations admin using emergency
  owner access is at owner level, so they see the owner guide.
- **Only your guide(s).** The **App guide** tab in each dashboard opens the
  guide for that dashboard (for admins, their level). Someone with several
  roles finds each guide in each dashboard. Admins who help families and
  tutors (Owner, Operations, Support) can also open the parent, student and
  tutor guides, to talk people through the app; Operations can open the
  Support guide (to train office help); the owner can open every guide.
  Finance admins see only their own. Changing the address can't open a
  guide that isn't allowed: the page checks `guidesFor` on the server.
- **Short parts, then tasks.** Each guide has a contents list of a few
  parts (for example Sessions, Billing). Each part lists tasks as fold-outs;
  opening one shows numbered steps with the button names in bold, plus a
  tip where it helps.
- **Search.** A search box shows only the tasks containing every word,
  already opened.
- **Built from the app as it is now.** Every step was checked against the
  screens in the code on 16 Nov 2026 (for example: families approve times
  CLG offers rather than booking themselves; cancelling needs a reason and
  two make-up times).
- **Kept current.** The words live in `src/lib/app-guides/` next to the
  code, so a pull request that changes a screen updates its guide at the
  same time (rule added to CLAUDE.md). The old markdown guides in
  `docs/guides/` had fallen behind and were replaced.

## How we'll know it works

- Fewer "how do I" calls and emails to CLG during the trial (Carla and
  Lauren's sense of it, and Feedback items in "The app" area).
- App issue reports that turn out to be "couldn't find it" rather than a
  fault should drop.
- Later, if useful: count opens of each guide and the most common search
  words, to find screens that need to be simpler.

## Privacy, child safety and the law

- **No personal information.** The guides are fixed text about the app.
  They hold nothing about any person, so there is no table and no database
  rule: who sees which guide is decided on the server from the person's
  roles and admin level, which the database already controls.
- **Transparency (Privacy Act 1988, APP 1 and APP 5; Children's Online
  Privacy Code).** The guides tell families and students where to see,
  download, correct or delete their information (**Your privacy**), and
  what is shared with whom (for example the calendar link shows first
  names only; block reasons are seen only by CLG). The student guide is
  written for 16 and 17 year olds, in plain words, as the Children's Online
  Privacy Code expects for information aimed at young people.
- **Child safety (SA Child Safe Environments; National Principles for Child
  Safe Organisations, Principle 6 on complaints and Principle 7 on staff
  knowledge).** Every guide explains the **Child safety** button: 000 first,
  the child protection line, then telling CLG, kept confidential. The
  student guide gives Kids Helpline and Lifeline. The owner, Operations and
  Support guides explain the officer and deputy steps.
- **Accessibility (Disability Discrimination Act 1992; WCAG 2.2).** Real
  headings, numbered lists, a labelled search box, and fold-outs that work
  with a keyboard and screen reader. Text is never treated as HTML.
- **UK and EU later.** UK GDPR and GDPR Articles 12 to 14 ask for the same
  concise, plain information, so the approach carries over.
