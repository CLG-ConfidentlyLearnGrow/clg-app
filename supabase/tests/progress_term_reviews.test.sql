-- Term reviews and monthly summaries. Runs after progress_roadmaps.test.sql
-- and reuses its people: owner ...a0 (admin), tutor T1 ...11 (teaches Cara
-- One), tutor T2 ...12, parent P1 ...01 (Cara's parent), parent P2 ...02.

-- The migration is safe to run twice.
\ir ../migrations/20261029500200_progress_term_reviews.sql

select tests.claims(null);
select id as cara from public.students where full_name = 'Cara One' \gset
select (now() at time zone 'Australia/Adelaide')::date as today \gset

-- A school term ending in 10 days, whatever today's date. The real SA terms
-- are put back at the end.
create temp table saved_terms as select * from public.school_terms where state = 'SA';
delete from public.school_terms where state = 'SA';
insert into public.school_terms (state, year, term, starts_on, ends_on)
  values ('SA', extract(year from :'today'::date - 40)::int, 4, :'today'::date - 40, :'today'::date + 10);

-- ===========================================================================
-- Reviews are made three weeks before the term ends
-- ===========================================================================
select private.queue_term_reviews();
select private.queue_term_reviews();
select tests.eq((select count(*) from public.term_reviews where student_id = :'cara'
  and tutor_id = '00000000-0000-0000-0000-000000000011' and status = 'draft'), 1, 'one review per student and tutor');
select id as review from public.term_reviews where student_id = :'cara' \gset
select tests.eq((select count(*) from public.progress_notices where review_id = :'review' and kind = 'review_due'
  and account_id = '00000000-0000-0000-0000-000000000011'), 1, 'tutor told a review is due');
select tests.eq((select count(*) from public.term_reviews where tutor_id = '00000000-0000-0000-0000-000000000012'), 0,
  'no review where there were no sessions this term');
update public.progress_notices set deliver_at = now() - interval '1 minute' where review_id is not null;

-- ===========================================================================
-- The tutor writes it
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.term_reviews where id = :'review'), 1, 'tutor sees the draft');
select tests.eq((select (count(*) > 0)::int from public.term_review_goals(:'review')), 1, 'goals and skills filled in for the tutor');
select tests.fails(format($$select public.save_term_review(%L, 'Good term', null, 'continue', null, true)$$, :'review'), 'sending without a focus for next term');
select public.save_term_review(:'review', 'Cara can now compare fractions on her own.', null, null);
select tests.eq((select count(*) from public.term_reviews where id = :'review' and status = 'draft' and summary like 'Cara can now%'), 1, 'draft saved');
select public.save_term_review(:'review', 'Cara can now compare fractions on her own.', 'Adding fractions with different denominators.', 'continue', null, true);
select tests.fails(format($$select public.save_term_review(%L, 'changed', 'changed', 'continue')$$, :'review'), 'tutor changes it after sending');
select tests.fails(format($$update public.term_reviews set status = 'approved' where id = %L$$, :'review'), 'tutor approves by direct edit');
select tests.fails(format($$select public.check_term_review(%L, true)$$, :'review'), 'tutor approves their own review');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.term_reviews), 0, 'other tutor sees no reviews');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.term_reviews), 0, 'family can''t see it before CLG checks it');
select tests.eq((select count(*) from public.term_review_goals(:'review')), 0, 'or its goals');
select tests.fails(format($$select public.reply_term_review(%L, 'Thanks')$$, :'review'), 'family replies before it''s ready');
reset role;

-- ===========================================================================
-- CLG checks it
-- ===========================================================================
select tests.claims(null);
select tests.eq((select count(*) from public.progress_notices where review_id = :'review' and kind = 'review_to_check'
  and account_id = '00000000-0000-0000-0000-0000000000a0'), 1, 'admin told there''s a review to check');

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.check_term_review(%L, false)$$, :'review'), 'sending back without a reason');
select public.check_term_review(:'review', false, 'Please add one thing to practise over the holidays.');
select tests.eq((select count(*) from public.term_reviews where id = :'review' and status = 'returned'), 1, 'sent back');
reset role;
select tests.claims(null);
update public.progress_notices set deliver_at = now() - interval '1 minute' where review_id is not null;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.progress_notices where review_id = :'review' and kind = 'review_returned'), 1, 'tutor told what to change');
select public.save_term_review(:'review', 'Cara can now compare fractions on her own.', 'Adding fractions. Over the holidays: one fraction puzzle a week.', 'continue', null, true);
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.check_term_review(:'review', true);
select tests.eq((select count(*) from public.term_reviews where id = :'review' and status = 'approved'
  and approved_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'approved');
select tests.fails(format($$select public.check_term_review(%L, true)$$, :'review'), 'approving twice');
reset role;

-- ===========================================================================
-- The family reads and replies
-- ===========================================================================
select tests.claims(null);
update public.progress_notices set deliver_at = now() - interval '1 minute' where review_id is not null;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.term_reviews where id = :'review'), 1, 'family sees the checked review');
select tests.eq((select count(*) from public.progress_notices where review_id = :'review' and kind = 'review_ready'), 1, 'family told it''s ready');
select tests.eq((select (count(*) > 0)::int from public.term_review_goals(:'review')), 1, 'family sees goals with start and end levels');
select public.reply_term_review(:'review', 'Thank you! Can we talk about adding a second session?', true);
select tests.eq((select count(*) from public.term_reviews where id = :'review' and wants_call), 1, 'reply saved with a call request');
reset role;

select tests.claims(null);
select tests.eq((select count(*) from public.progress_notices where review_id = :'review' and kind = 'review_reply'
  and account_id in ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-000000000011')), 2, 'admin and tutor see the reply');

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.term_reviews), 0, 'other parent sees no reviews');
select tests.fails(format($$select public.reply_term_review(%L, 'Hello')$$, :'review'), 'other parent replies');
reset role;

-- ===========================================================================
-- Monthly summary
-- ===========================================================================
select tests.claims(null);
select private.queue_monthly_summaries(current_date);
select private.queue_monthly_summaries(current_date);
select tests.eq((select count(*) from public.progress_notices where kind = 'monthly_summary' and student_id = :'cara'
  and account_id = '00000000-0000-0000-0000-000000000001' and for_date = date_trunc('month', current_date)::date), 1, 'parent gets one summary');
select tests.eq((select count(*) from public.progress_notices where kind = 'monthly_summary' and student_id = :'cara'
  and body like '%Skills moved up a step:%'), 1, 'summary lists skill movement');
select tests.eq((select count(*) from public.progress_notices where kind = 'monthly_summary'
  and account_id = '00000000-0000-0000-0000-000000000002' and student_id = :'cara'), 0, 'other parent gets none');

-- Put the real terms back.
delete from public.school_terms where state = 'SA';
insert into public.school_terms select * from saved_terms;

\echo '  progress term reviews: all checks passed'
