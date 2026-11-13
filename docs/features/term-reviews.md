# Term reviews and monthly summaries

Part 4 of progress tracking (phase 2 of the research brief: https://claude.ai/artifact/UvGuihmTC7xyH9XHrjLbLt).

## What it's for

The brief calls the term review "the moment parents decide to stay or leave". CLG already asks families about next term two weeks before it ends (four weeks for terms 1 and 3). The term review gives that question substance: what the student can do now that they couldn't at the start of term, and what comes next. The monthly summary keeps families in the picture between reviews, with no extra tutor time.

## What the evidence says

- **Feedback** (+6 months, EEF Toolkit): useful feedback says where the learner is going, how they are going and where to next (Hattie and Timperley, cited from memory). The review has exactly those parts: the goals with skills at the start of term and now, how the term went, and the focus for next term.
- **Parental engagement** (+4 months, EEF): personalised messages about progress and next steps work; generic reports don't. The review is written by the student's own tutor to the family, and includes one thing to practise over the holidays.
- **One to one tuition** (+5 months, EEF): works best when it is monitored and adjusted. The tutor's recommendation (continue, change focus, more or fewer sessions, a break) turns the review into a decision point.
- **Stanford NSSA high-impact tutoring**: oversight of tutor quality. Every review is checked by CLG before the family sees it.
- **Tutor workload** (EEF warns feedback's cost is staff time): the app fills in each goal's skills at the start of term and now, so the tutor writes only three short parts. The monthly summary is written by the app.

## How the design follows the evidence

- **When**: three weeks before a term ends, a draft review is made for each student with a current tutor who had a session note that term. The tutor is told and asked to send it two weeks before the term ends.
- **Written by the tutor**: how the term went, the focus for next term, a recommendation and why.
- **Checked by CLG**: an admin approves it or sends it back with what to change.
- **Read by the family**: on the progress page, with the goals table. They can reply and tick "I'd like a call"; the reply goes to CLG's admins and the tutor together (no private tutor and family chats).
- **Monthly summary**: on the 1st, families get last month's sessions, skills moved up, goals reached, roadmap steps done, and what the student is working on now. Nothing is sent for a month with no sessions.

## How we'll know it works

- share of reviews sent by the tutor before the deadline, and sent back by CLG
- share of families who reply, and who ask for a call
- re-enrolment for next term (from scheduling's "same again" answers)

## Privacy and child safety

- `term_reviews` hangs off `students`, so the shared access rules and automatic deletion apply. Families see a review only once CLG has approved it. Tutors see their own reviews while they still teach the student; other tutors see none.
- All changes go through database functions; every change is in the audit log.
- No free-text fields invite health or diagnosis details; the form asks about learning only.
- The progress module reads scheduling's school terms and sessions but never writes them.
- Migration `20261029500200_progress_term_reviews.sql`; tests in `supabase/tests/progress_term_reviews.test.sql`.

## Changes, 2 Nov 2026

See [app-changes-2-nov-2026.md](app-changes-2-nov-2026.md) for the full brief.

- Term reviews are now an opt-in paid add-on (`term_reviews`), starting
  "off" until Carla sets a price. Only students with the add-on get a draft.
- Reviews follow each student's own study dates.
- The tutor writes the review. The form and the notice say not to put any
  student information into AI tools.
- Monthly summaries are removed (no new ones are made).

## Changes, 12 Nov 2026: paid reviews, offered to each family

Carla: no monthly summaries, and term reviews only when the family pays
for one. The offer comes towards the end of each term (end of semester for
tertiary students), or towards the end of the booked sessions when those
don't line up with term dates.

### How it works

- **Price**: a "Term review" item in Admin > Billing > Prices (charged once
  per review). It starts off at $0. Nothing is offered until the owner sets
  a price and ticks "in use". The old "Term reviews" add-on is removed
  (only if no student had been given it).
- **When**: the daily job offers a review 4 weeks before the end of the
  student's term, private school term or tertiary study period, if their
  bookings reach to at least 2 weeks before that end. If their last booked
  session isn't within 2 weeks of any term's end, the offer comes 4 weeks
  before that last session instead. Only students with a current tutor who
  has written a session note in the period are offered one, and not while
  the family is on hold for an unpaid invoice.
- **Who answers**: the parent who manages the student, or a student who
  manages their own account. They see the price (including GST if it
  applies) on the progress page and choose yes or no. No answer means no
  review and no charge. A "no" can change to "yes" until the end date.
- **CLG can answer for them** in Admin > Progress > Paid term review
  offers. Owner, operations and finance admins can give a review at no
  charge (for example on hardship).
- **On yes**: billing makes an invoice with one line ("Term review, Term 4
  2026, Cara") at the price the family saw, using any credit first. If the
  family has no billing account yet, admins are told to bill it by hand.
  The student's tutor gets a draft (the tutor with the most notes in the
  period, if there are several), due 2 weeks before the end, or 5 days
  after the yes if that's later. Checking and replying work as before.
- **Monthly summaries**: none are made, and old ones no longer show on the
  family dashboard.

### What the evidence says

- **Feedback** (EEF Teaching and Learning Toolkit, +6 months) and
  **parental engagement** (EEF, +4 months, strongest when personalised):
  the review keeps both, written by the student's own tutor. Asking first
  means reviews go to families who want them, which suits the EEF's
  caution that feedback costs staff time.
- **One to one tuition** (EEF, +5 months) works best when monitored and
  adjusted; timing the review to the student's real end (term or booking)
  keeps it a decision point at the moment the family decides what next.
- **Equity**: EEF guidance on the disadvantage gap warns that paid extras
  can widen gaps, so finance admins can give a review at no charge.
- Monthly summaries were app-written statistics, which the parental
  engagement evidence rates as less useful than personal messages; session
  updates after each note still go to families.

### Legal rules it touches

- **Australian Consumer Law**: the price shown is the total price
  including any GST (s 48), the family opts in themselves (nothing is
  pre-ticked, and silence is a "no"), and the invoice uses the price they
  were shown even if the price changes later. Add paid term reviews to the
  Client Terms before turning the price on.
- **Children's Online Privacy Code** (draft) and the APPs: offers and
  prices go only to the paying adult (a managing parent, or a student who
  manages their own account), never to a child who is managed by a parent,
  and never to tutors (Carla's 12 Nov rule that tutors see no financial
  information). No new personal information is collected.
- **Records**: offers are deleted with the student under the retention
  rules; the invoice stays for 7 years for tax, like session invoices.
  Every change is in the audit log.
- Keep in mind for later: UK and EU cooling-off rules for services bought
  online (14 days) before offering this outside Australia.

### Files

- Migration `supabase/migrations/20261113900100_paid_term_reviews.sql`.
- Tests `supabase/tests/progress_term_review_offers.test.sql` (and updates
  to the term review, study plan add-on and billing tests).
