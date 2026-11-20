# Keeping the app fast

Carla, 18 Nov 2026: "The app is getting a bit slow, how do I keep the app load speed fast?"

## Why speed matters for learning

- Families, students and tutors use the app on phones between other things. Research on web use (Google's Core Web Vitals work) finds people start leaving a page after about 3 seconds of waiting. For CLG, a slow page means a summary written late, a booking not answered, or a parent who stops checking progress.
- Evidence for Learning and the EEF both rank feedback and parental engagement as high-impact, low-cost approaches. Both depend on the app being quick enough that people actually open progress notes, summaries and messages. A fast app supports the parts of CLG's model that the research says matter most.
- Cognitive load research (Sweller; AERO's "Cognitive load theory in practice") shows waiting and uncertainty take attention away from the task. Quick, predictable pages keep the learner and the tutor focused on the learning.

## What was measured (18 Nov 2026)

| Check | Result |
| --- | --- |
| Where the app runs | Vercel, Sydney (`syd1`), same city as Supabase. Good, no change needed. |
| Login page from Adelaide | About 90 milliseconds to answer, 150 KB of code to download. Good. |
| Map page code | The map library only loads on the Travel map page. Good. |
| Access rules (row level security) | **Main cause.** On a test copy with 20,000 sessions, a parent counting their sessions took about 10 seconds; an owner about 6 seconds; a tutor about 12 seconds. |
| To-do numbers in the menus (worked out on every page) | About 1 second for an owner or tutor on the same test copy, almost all from the "summaries still to write" list. |
| Missing look-up lists (indexes) | About 30 columns that pages and access rules search by had none. |

### Why the access rules were slow

Each access rule asks questions such as "is this person an admin?" (`private.is_admin()`) or "who is signed in?" (`auth.uid()`). The database asked these again for every row it looked at, and "is this person an admin?" itself takes several look-ups. So the time grew with the number of sessions, notes and invoices in the whole table, which is why the app was getting slower each week.

## What was changed

Update file `supabase/migrations/20261122100100_faster_access_rules.sql`:

1. Every access rule now asks "same for every row" questions once per request, by wrapping them in `(select ...)`. This is Supabase's own advice. The answer cannot change partway through one request, so who can see or change what is exactly the same. All existing access tests still pass.
2. The "summaries still to write" list (used by the to-do numbers on every page) got the same change.
3. Indexes were added for the columns the busiest pages and rules search by.

Measured on the same test copy afterwards:

| Who | Before | After |
| --- | --- | --- |
| Parent, list of sessions | 10 seconds | 0.15 seconds |
| Owner, list of sessions | 6 seconds | 0.002 seconds |
| Tutor, list of sessions | 12 seconds | 1.8 seconds (with 10,000 sessions for one tutor; a real tutor has far fewer) |
| Owner, to-do numbers | 0.9 seconds | 0.04 seconds |
| Tutor, to-do numbers | 1.3 seconds | 0.25 seconds |

`supabase/tests/fast_access_rules.test.sql` fails if a new access rule is ever written the slow way, naming the rule, so this does not creep back.

## Legal rules this touches

None change. The update keeps every access rule's meaning exactly as it was (Privacy Act APP 11: security of personal information; Children's Online Privacy Code), and the existing access rule tests prove it. No personal information is collected, moved or shown to anyone new.

## Later, if it is needed

- Tutor rules still check "is this tutor cleared for this student?" once per row. If tutors ever have thousands of sessions each, that check can be reworked.
- Re-run the update file after re-running any older update file, because older files put their rules back in the slow form.
