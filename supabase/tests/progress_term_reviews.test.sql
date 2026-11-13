-- Summary: term reviews and monthly summaries. Runs after progress_roadmaps.test.sql
-- and reuses its people: owner ...a0 (admin), tutor T1 ...11 (teaches Cara
-- One), tutor T2 ...12, parent P1 ...01 (Cara's parent), parent P2 ...02.

-- The migration is safe to run twice.
-- Runs the database change 20261029500200_progress_term_reviews.sql first, as this test needs it.
\ir ../migrations/20261029500200_progress_term_reviews.sql
-- Re-running it resets the review rules, so apply the 2 Nov 2026 change
-- (paid opt-in, no monthly summaries) again.
-- Runs the database change 20261103000800_progress_term_review_add_on.sql first, as this test needs it.
\ir ../migrations/20261103000800_progress_term_review_add_on.sql
-- Then the 12 Nov 2026 change (reviews only when the family says yes to a paid offer).
-- Runs the database change 20261113700100_paid_term_reviews.sql first, as this test needs it.
\ir ../migrations/20261113700100_paid_term_reviews.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset
-- Keeps today's date in Adelaide as today.
select (now() at time zone 'Australia/Adelaide')::date as today \gset

-- A school term ending in 10 days, whatever today's date. The real SA terms
-- are put back at the end.
create temp table saved_terms as select * from public.school_terms where state = 'SA'; -- Keeps a copy of the SA term dates in a short-lived table.
delete from public.school_terms where state = 'SA'; -- Clears the SA term dates.
insert into public.school_terms (state, year, term, starts_on, ends_on) -- Adds a test term ending in 10 days:
  values ('SA', extract(year from :'today'::date - 40)::int, 4, :'today'::date - 40, :'today'::date + 10); -- (started 40 days ago).

-- ===========================================================================
-- Reviews are made three weeks before the term ends
-- ===========================================================================
-- Only when the family says yes to a paid offer (12 Nov 2026).
select tests.eq((select count(*) from public.term_reviews where student_id = :'cara'), 0, 'no review without a yes'); -- Checks: nothing is made until the family says yes.
insert into public.term_review_offers (id, student_id, period_kind, period_label, period_starts_on, period_ends_on, price_cents) -- Adds an offer for Cara's term:
  values ('00000000-0000-0000-0000-0000000f0101', :'cara', 'term', 'Term 4', :'today'::date - 40, :'today'::date + 10, 4000); -- ending in 10 days, at $40.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as parent P1 (Cara's parent).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.answer_term_review_offer('00000000-0000-0000-0000-0000000f0101', true); -- The parent says yes.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
select private.queue_term_reviews(); -- Runs the daily job (should not repeat the draft).
select tests.eq((select count(*) from public.progress_notices where kind = 'review_due' and body like '%AI tools%'), 1, 'tutor reminded not to use AI tools'); -- Checks: tutor reminded not to use AI tools.
select tests.eq((select count(*) from public.term_reviews where student_id = :'cara' -- Checks there's one review for the paid offer:
  and tutor_id = '00000000-0000-0000-0000-000000000011' and status = 'draft'), 1, 'one review per paid offer'); -- (a draft for tutor T1).
-- Keeps the review's id as review.
select id as review from public.term_reviews where student_id = :'cara' \gset
select tests.eq((select count(*) from public.progress_notices where review_id = :'review' and kind = 'review_due' -- Checks the tutor is told a review is due:
  and account_id = '00000000-0000-0000-0000-000000000011'), 1, 'tutor told a review is due'); -- (one notice).
select tests.eq((select count(*) from public.term_reviews where tutor_id = '00000000-0000-0000-0000-000000000012'), 0, -- Checks the other tutor gets no review:
  'no review for a tutor who doesn''t write it'); -- (none for tutor T2).
update public.progress_notices set deliver_at = now() - interval '1 minute' where review_id is not null; -- Makes the review notices due now.

-- ===========================================================================
-- The tutor writes it
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.term_reviews where id = :'review'), 1, 'tutor sees the draft'); -- Checks: tutor sees the draft.
select tests.eq((select (count(*) > 0)::int from public.term_review_goals(:'review')), 1, 'goals and skills filled in for the tutor'); -- Checks: goals and skills filled in for the tutor.
select tests.fails(format($$select public.save_term_review(%L, 'Good term', null, 'continue', null, true)$$, :'review'), 'sending without a focus for next term'); -- Checks this is refused: sending without a focus for next term.
select public.save_term_review(:'review', 'Cara can now compare fractions on her own.', null, null); -- The tutor saves a draft with just the summary.
select tests.eq((select count(*) from public.term_reviews where id = :'review' and status = 'draft' and summary like 'Cara can now%'), 1, 'draft saved'); -- Checks: draft saved.
select public.save_term_review(:'review', 'Cara can now compare fractions on her own.', 'Adding fractions with different denominators.', 'continue', null, true); -- The tutor saves it in full and sends it to CLG.
select tests.fails(format($$select public.save_term_review(%L, 'changed', 'changed', 'continue')$$, :'review'), 'tutor changes it after sending'); -- Checks this is refused: tutor changes it after sending.
select tests.fails(format($$update public.term_reviews set status = 'approved' where id = %L$$, :'review'), 'tutor approves by direct edit'); -- Checks this is refused: tutor approves by direct edit.
select tests.fails(format($$select public.check_term_review(%L, true)$$, :'review'), 'tutor approves their own review'); -- Checks this is refused: tutor approves their own review.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- Signs in as test account ...12 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.term_reviews), 0, 'other tutor sees no reviews'); -- Checks: other tutor sees no reviews.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.term_reviews), 0, 'family can''t see it before CLG checks it'); -- Checks: family can't see it before CLG checks it.
select tests.eq((select count(*) from public.term_review_goals(:'review')), 0, 'or its goals'); -- Checks: or its goals.
select tests.fails(format($$select public.reply_term_review(%L, 'Thanks')$$, :'review'), 'family replies before it''s ready'); -- Checks this is refused: family replies before it's ready.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- CLG checks it
-- ===========================================================================
select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.progress_notices where review_id = :'review' and kind = 'review_to_check' -- Checks the admin is told there's a review to check:
  and account_id = '00000000-0000-0000-0000-0000000000a0'), 1, 'admin told there''s a review to check'); -- (one notice for the owner).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.check_term_review(%L, false)$$, :'review'), 'sending back without a reason'); -- Checks this is refused: sending back without a reason.
select public.check_term_review(:'review', false, 'Please add one thing to practise over the holidays.'); -- The admin sends it back, asking for a holiday practice idea.
select tests.eq((select count(*) from public.term_reviews where id = :'review' and status = 'returned'), 1, 'sent back'); -- Checks: sent back.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.
update public.progress_notices set deliver_at = now() - interval '1 minute' where review_id is not null; -- Makes the review notices due now.

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.progress_notices where review_id = :'review' and kind = 'review_returned'), 1, 'tutor told what to change'); -- Checks: tutor told what to change.
select public.save_term_review(:'review', 'Cara can now compare fractions on her own.', 'Adding fractions. Over the holidays: one fraction puzzle a week.', 'continue', null, true); -- The tutor fixes it and sends it again.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.check_term_review(:'review', true); -- The admin approves it.
select tests.eq((select count(*) from public.term_reviews where id = :'review' and status = 'approved' -- Checks it's approved:
  and approved_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'approved'); -- (by the owner).
select tests.fails(format($$select public.check_term_review(%L, true)$$, :'review'), 'approving twice'); -- Checks this is refused: approving twice.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- The family reads and replies
-- ===========================================================================
select tests.claims(null); -- Signs out, so no one is signed in.
update public.progress_notices set deliver_at = now() - interval '1 minute' where review_id is not null; -- Makes the review notices due now.

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.term_reviews where id = :'review'), 1, 'family sees the checked review'); -- Checks: family sees the checked review.
select tests.eq((select count(*) from public.progress_notices where review_id = :'review' and kind = 'review_ready'), 1, 'family told it''s ready'); -- Checks: family told it's ready.
select tests.eq((select (count(*) > 0)::int from public.term_review_goals(:'review')), 1, 'family sees goals with start and end levels'); -- Checks: family sees goals with start and end levels.
select public.reply_term_review(:'review', 'Thank you! Can we talk about adding a second session?', true); -- The parent replies and asks for a call.
select tests.eq((select count(*) from public.term_reviews where id = :'review' and wants_call), 1, 'reply saved with a call request'); -- Checks: reply saved with a call request.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select count(*) from public.progress_notices where review_id = :'review' and kind = 'review_reply' -- Checks the admin and tutor see the reply:
  and account_id in ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-000000000011')), 2, 'admin and tutor see the reply'); -- (one notice each).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.term_reviews), 0, 'other parent sees no reviews'); -- Checks: other parent sees no reviews.
select tests.fails(format($$select public.reply_term_review(%L, 'Hello')$$, :'review'), 'other parent replies'); -- Checks this is refused: other parent replies.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Monthly summary
-- ===========================================================================
select tests.claims(null); -- Signs out, so no one is signed in.
-- No longer sent (2 Nov 2026).
select tests.eq(private.queue_monthly_summaries(current_date), 0, 'monthly summaries are no longer made'); -- Checks: monthly summaries are no longer made.
select tests.eq((select count(*) from public.progress_notices where kind = 'monthly_summary'), 0, 'no monthly summary sent'); -- Checks: no monthly summary sent.

-- Put the real terms back, and the add-on as it was.
delete from public.term_reviews where offer_id = '00000000-0000-0000-0000-0000000f0101'; -- Clears the test review.
delete from public.term_review_offers where id = '00000000-0000-0000-0000-0000000f0101'; -- Clears the test offer.
delete from public.school_terms where state = 'SA'; -- Clears the test term.
insert into public.school_terms select * from saved_terms; -- Puts the SA term dates back.

-- Prints that every check in this file passed.
\echo '  progress term reviews: all checks passed'
