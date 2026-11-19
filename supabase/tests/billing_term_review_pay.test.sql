-- Term review pay: a tutor cannot send a term review until the training
-- needed before term reviews is done; once CLG approves the review, the
-- tutor gets 1 hour of "Term review" pay at their tutor rate, once.
-- Reuses access_rules.test.sql people: owner (...a0), tutor T1 (...11, who
-- teaches Cara One). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the changes this relies on again (an earlier test may have re-run older files), then this one twice.
\ir ../migrations/20261121300200_training_assign_order_jobs.sql
\ir ../migrations/20261122300100_term_review_pay.sql
\ir ../migrations/20261122300100_term_review_pay.sql

-- Acts as the database itself, to set up.
select tests.claims(null);
-- Starts with no training, so only the module below counts.
delete from public.training_assignments; -- removes assignments
delete from public.training_completions; -- removes completions
delete from public.training_modules; -- removes modules
-- One published tutor module needed before term reviews, with no quiz.
insert into public.training_modules (id, title, audience, stage, required, holds_matching, counts_toward_certified, minutes, status, position, in_order, needed_for) values -- the module:
  ('50000000-0000-0000-0000-000000000001', 'Writing term reviews', 'tutor', 'ongoing', true, false, true, 15, 'published', 1, false, 'term_review'); -- needed before term reviews

-- T1 has a $40/hr school rate and a $40/hr tertiary rate.
insert into public.billing_staff_pay (account_id, employment, school_rate_cents, tertiary_rate_cents) values ('00000000-0000-0000-0000-000000000011', 'casual', 4000, 4000) -- T1's details
on conflict (account_id) do update set school_rate_cents = 4000, tertiary_rate_cents = 4000; -- (or update them)

-- A draft term review for T1 about Cara (a made-up term).
select id as cara from public.students where full_name = 'Cara One' \gset
insert into public.term_reviews (id, student_id, tutor_id, term_label, term_starts_on, term_ends_on, due_on) -- makes the draft:
values ('50000000-0000-0000-0000-0000000000a1', :'cara', '00000000-0000-0000-0000-000000000011', 'Term 8 2099', current_date - 60, current_date + 20, current_date + 20); -- (due in 20 days)

-- ---------------------------------------------------------------------------
-- Sending needs the term review training done.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$select public.save_term_review('50000000-0000-0000-0000-0000000000a1', 'A good term.', 'Fractions next.', 'continue', null, true)$$, 'sending before the training is done'); -- refused
select public.save_term_review('50000000-0000-0000-0000-0000000000a1', 'A good term.', 'Fractions next.', 'continue', null, false); -- saving a draft still works
select tests.eq((select count(*) from public.term_reviews where id = '50000000-0000-0000-0000-0000000000a1' and status = 'draft' and summary = 'A good term.'), 1::bigint, 'draft saved before the training'); -- checks the draft
select public.training_finish('50000000-0000-0000-0000-000000000001', '{}'); -- finishes the module (no quiz)
select public.save_term_review('50000000-0000-0000-0000-0000000000a1', 'A good term.', 'Fractions next.', 'continue', null, true); -- now sending works
select tests.eq((select count(*) from public.term_reviews where id = '50000000-0000-0000-0000-0000000000a1' and status = 'submitted'), 1::bigint, 'sent once the training is done'); -- checks it was sent
reset role; -- back to the test runner

-- ---------------------------------------------------------------------------
-- Pay: nothing until approved, then 1 hour at the tutor rate, once.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.eq(public.billing_build_term_review_pay(current_date - 1, current_date + 1), 0, 'not paid before it is approved'); -- nothing yet
select public.check_term_review('50000000-0000-0000-0000-0000000000a1', true); -- approves it
reset role; -- back to the test runner

-- Only the owner, Finance or the daily run can add term review pay.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$select public.billing_build_term_review_pay(current_date - 1, current_date + 1)$$, 'tutor adds term review pay'); -- refused
reset role; -- back to the test runner

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.eq(public.billing_build_term_review_pay(current_date - 1, current_date + 1), 1, 'one term review line waiting'); -- adds it
select tests.eq(public.billing_build_term_review_pay(current_date - 1, current_date + 1), 1, 'working it out again does not double up'); -- still one
reset role; -- back to the test runner
select tests.eq((select count(*) from public.billing_pay_lines where term_review_id = '50000000-0000-0000-0000-0000000000a1' and kind = 'term_review' and account_id = '00000000-0000-0000-0000-000000000011' and minutes = 60 and amount_cents = 4000), 1::bigint, 'one hour at $40/hr for the tutor'); -- checks the line
select tests.eq((select count(*) from public.billing_pay_lines where term_review_id = '50000000-0000-0000-0000-0000000000a1' and note like 'Cara, Term 8 2099%'), 1::bigint, 'the line says which review'); -- checks the note

-- Tutors cannot add or change pay lines themselves.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, minutes, rate_cents, amount_cents) values ('00000000-0000-0000-0000-000000000011', 'T1', current_date, 'term_review', 'school', 60, 4000, 4000)$$, 'tutor writes a pay line'); -- refused
reset role; -- back to the test runner

-- Admins are not stopped by the training check: a second review sent by the owner for T1, with the training removed.
select tests.claims(null); -- acting as the database itself
delete from public.training_completions; -- T1's training is gone again
insert into public.term_reviews (id, student_id, tutor_id, term_label, term_starts_on, term_ends_on, due_on) -- another draft:
values ('50000000-0000-0000-0000-0000000000a2', :'cara', '00000000-0000-0000-0000-000000000011', 'Term 9 2099', current_date - 50, current_date + 30, current_date + 30); -- (due in 30 days)
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select public.save_term_review('50000000-0000-0000-0000-0000000000a2', 'Sent by CLG.', 'Decimals next.', 'continue', null, true); -- the owner can send it
reset role; -- back to the test runner
select tests.eq((select count(*) from public.term_reviews where id = '50000000-0000-0000-0000-0000000000a2' and status = 'submitted'), 1::bigint, 'admin sends without the check'); -- checks it was sent

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  billing term review pay: all checks passed'
