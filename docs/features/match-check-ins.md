# Check-ins after a new match

Requested by Carla, 16 Nov 2026. Asked whether the app should check in 1 and
2 weeks after a new match, at 6 weeks, or both, Carla answered: "Yes, all of
these."

## 1. What it is for

A new tutor and learner can take a few sessions to settle. If the match is
not working, CLG wants to hear early, from both sides, before the family
loses confidence or the learner loses weeks of learning. Until now the app
had no way to ask.

- When a tutor and a learner start working together, the app asks how it is
  going **1 week, 2 weeks and 6 weeks after their first session**.
- Each person is asked on their own: the **tutor**, each **parent or carer**,
  and the **learner** if they have their own login (16 and over, or an adult
  learner).
- Each check-in is a card at the top of their dashboard with four short
  questions:
  1. How are the sessions going? (1 to 5, from "Not well at all" to "Very
     well")
  2. Is it a good fit? (Yes, Not sure yet, No). For families this is "Would
     you like [learner] to keep working with [tutor]?"; for the tutor, "Do
     you think you are a good fit for [learner]?"
  3. Anything else you would like to tell us? (optional)
  4. A tick box: "Please contact me about this".
- They can also **skip** a check-in.
- An answer is **flagged for follow-up** when it is rated 1 or 2, says it is
  not a good fit, or asks CLG to make contact. The owner and operations
  admins see flagged answers on a new **Check-ins** page (with a number on
  the menu), contact the person, and mark it followed up with a private note.

## 2. What the evidence says

- **One-to-one tutoring works, and the relationship matters.** Evidence for
  Learning's Teaching and Learning Toolkit rates one-to-one tuition at about
  +5 months' progress
  (https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/one-to-one-tuition).
  A large review of tutoring programs (Nickow, Oreopoulos and Quan, 2020,
  NBER Working Paper 27476) found the biggest effects in programs with a
  consistent tutor and a strong tutor-learner relationship. A quick early
  check protects that relationship, or finds a better match early.
- **Monitor early and adjust.** The EEF's guidance on making the best use of
  tutoring (National Tutoring Programme guidance, 2021) and its
  *Putting Evidence to Work* implementation guide (2nd ed., 2024) both stress
  checking early how a new program is landing and acting on what is found,
  rather than waiting until the end of term
  (https://educationendowmentfoundation.org.uk/support-for-schools/school-improvement-planning/a-school-guide-to-implementation).
  Week 1 and week 2 catch problems with fit or logistics; week 6 is about
  half a term in, when learning gains should start to show.
- **Ask families and learners, simply.** AERO's work on student voice and on
  engaging families in learning (2023) finds that asking learners and
  families regularly, in a simple way, improves engagement and gives early
  warning of problems. The EEF's *Working with Parents to Support Children's
  Learning* recommends short, low-effort ways to communicate. That is why
  each check-in is one short card, not a survey.
- **Feedback only helps when it is acted on.** The EEF's *Feedback* guidance
  and *Effective Professional Development* (2021) find feedback improves
  practice when it is specific and followed by action. Flagged answers have a
  clear follow-up step for admins, so the person is contacted and nothing
  sits unread.
- **Ratings need words.** A number alone says little, so every check-in has
  a comment box and a "please contact me" tick box.

## 3. How the design follows the evidence

- **Three short check-ins, timed from the first session**, not from the date
  the match was made, so the first one comes after the learner has actually
  met the tutor (usually just after their second weekly session).
- **Each one stays open until the next one opens** (1-week: days 7 to 14;
  2-week: days 14 to 42; 6-week: days 42 to 56), so a parent who only opens
  the app now and then still sees it. A missed one closes quietly.
- **Everyone is asked separately**, so the learner's own view is heard, and
  the tutor's view is heard too (a tutor may notice a poor fit first).
- **Only new matches are asked.** A match is "new" when its first session is
  on or after 16 Nov 2026 (the start date is a setting in the database).
  Families who have had the same tutor for years are not asked. A tutor
  change (see change-tutor.md) is a new match, so it gets its own check-ins.
- **A match that ends stops its check-ins.**
- **Admins see trends as well as flags**: each new match's check-ins, how many
  people answered, and the average rating.

## 4. How we will know it works

- Most people asked answer or skip each check-in (the Check-ins page shows
  "answered of asked").
- Flagged answers are followed up within 2 working days.
- Fewer families leave or change tutor after the first term than before.

## 5. Legal rules it touches (privacy and child safety)

- **Privacy Act 1988 and the APPs.** Only the minimum is collected: a rating,
  a yes/not sure/no answer, an optional comment, and the contact tick box,
  plus who answered so CLG can follow up (APP 3). The answers are used only to
  look after the match (APP 6). They are kept with the learner's record and
  deleted with it.
- **Who sees the answers (APP 11, security).** Only the owner and operations
  admins, with two-step sign-in. This is a database rule (row level
  security), not just the screen. The tutor never sees what the family said,
  and the family never sees what the tutor said, so both can be honest.
  People do not see their own answers again after sending, because the
  follow-up notes are private to admins.
- **Children's Online Privacy Code (OAIC, in development) and the UK Age
  Appropriate Design Code.** Only learners with their own login (16 and over)
  are asked directly; younger learners are represented by their parents. No
  nudging: a check-in is a single card, never shown during quiet hours (9pm
  to 5am in the person's own time zone), with a clear "Skip this check-in"
  button.
- **Child safety (SA Children and Young People (Safety) Act 2017, Child Safe
  Environments, National Principles for Child Safe Organisations).** Every
  comment goes through the concerning-words check, like other writing in the
  app. The card says in red that worries about a child's safety belong on the
  **Child safety** page, so the right person sees them straight away.
- **Fair Work.** A tutor's answers, and families' comments about a tutor, are
  not a disciplinary record. If anything leads to action, normal procedural
  fairness applies.
- **Spam Act 2003.** Check-ins are shown in the app only. Carla chose app
  notices only on 2 Nov 2026, so no check-in emails are sent. If emails are
  added later, they are service messages (not marketing) and must respect
  quiet hours.
- **UK and EU later.** The same design fits UK GDPR: minimal data, a clear
  purpose (looking after the match), and restricted access.

## 6. How it works (for developers)

- Migration `20261119800100_match_check_ins.sql`. Tests:
  `supabase/tests/match_check_ins.test.sql`.
- This is its own module: it owns `match_check_in_settings` and
  `match_check_ins`, and only reads sessions, assignments, parent links,
  students and accounts.
- `private.check_in_matches()` finds new matches (first non-cancelled
  session on or after the start date, assignment still current).
  `private.check_in_schedule()` gives each check-in's open and close times.
  `public.my_check_ins(role)` lists the ones waiting for the signed-in person
  on a dashboard, held out of quiet hours with
  `private.outside_quiet_hours_for`. `public.answer_check_in(...)` saves an
  answer or skip and sets the follow-up flag. `public.check_in_follow_up(...)`
  and `public.check_in_overview()` are for full admins.
- Screens: `src/components/check-in-prompts.tsx` (the card, shown by the
  dashboard frame on tutor, parent and student pages) and
  `src/app/admin/check-ins/page.tsx` (the admin page).

## 7. Later

- Check-in emails, if Carla turns emails back on for notices.
- Showing check-in results in the term review and the reports page.
