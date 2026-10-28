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
