-- Summary: checks the feedback asked when a match ends (Carla, 16 Nov 2026):
-- once a tutor and learner stop working together, the tutor and the parents
-- are each asked how it went and how well the ending was handled; the 1, 2
-- and 6-week check-ins stop; a poorly handled ending is flagged; matches that
-- ended long ago, or are still running, are not asked. Reuses
-- access_rules.test.sql people: owner Olive (...a0), tutor T1 (...11, teaches
-- Cara), tutor T2 (...12), parent P1 (...01, Cara's parent), parent P2
-- (...02). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the check-ins change and then this change again (checks both can run twice, in order).
\ir ../migrations/20261119800100_match_check_ins.sql
-- (the end-of-match change must come after it)
\ir ../migrations/20261119800200_match_end_feedback.sql

select tests.claims(null); -- acts as the database itself while setting up
\set olive '00000000-0000-0000-0000-0000000000a0'
-- (Olive's account id: owner)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id)
\set t2 '00000000-0000-0000-0000-000000000012'
-- (tutor T2's account id)
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
\set p2 '00000000-0000-0000-0000-000000000002'
-- (parent P2's account id)
select id as cara, family_id as fam1 from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara and her family as fam1)

update public.match_check_in_settings set starts_from = current_date - 100 where id; -- counts matches from 100 days ago, for these tests
delete from public.match_check_ins; -- starts with no answers
delete from public.sessions where tutor_id = :'t1' and student_id = :'cara'; -- clears any sessions other tests left for this match
insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at, status) values -- adds a session:
  (:'cara', :'t1', :'fam1', 'General Maths', 'school', 'online', now() - interval '30 days 1 hour', now() - interval '30 days', 'completed'); -- Cara with T1, 30 days ago
update public.tutor_assignments set starts_on = current_date - 40, ends_on = current_date - 2 where tutor_id = :'t1' and student_id = :'cara'; -- the match ended 2 days ago

-- 1. Who is asked when a match ends.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.my_check_ins('parent') where student_id = :'cara' and stage = 0), 1::bigint, 'the parent is asked for end-of-match feedback'); -- asked
select tests.eq((select count(*) from public.my_check_ins('parent') where student_id = :'cara' and stage <> 0), 0::bigint, 'weekly check-ins stop when a match ends'); -- none of the others
reset role; -- back to the database itself
select tests.claims(:'t1'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_check_ins('tutor') where student_id = :'cara' and stage = 0), 1::bigint, 'the tutor is asked for end-of-match feedback'); -- asked
reset role; -- back to the database itself
select tests.claims(:'p2'); -- signs in as parent P2 (not Cara's parent)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_check_ins('parent') where student_id = :'cara'), 0::bigint, 'another family is not asked'); -- not theirs
reset role; -- back to the database itself
select tests.claims(:'t2'); -- signs in as tutor T2
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.answer_check_in(%L, %L, 0::smallint, 5::smallint, null, false, null, false, 5::smallint)$q$, :'t1', :'cara'), 'another tutor cannot answer'); -- refused
reset role; -- back to the database itself

-- 2. Answering.
select tests.claims(:'t1'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.answer_check_in(%L, %L, 0::smallint, 4::smallint, 'yes', false, null)$q$, :'t1', :'cara'), 'the ending question must be answered'); -- refused
select tests.fails(format($q$select public.answer_check_in(%L, %L, 0::smallint, 4::smallint, null, false, null, false, 7::smallint)$q$, :'t1', :'cara'), 'the ending rating goes from 1 to 5'); -- refused
select public.answer_check_in(:'t1', :'cara', 0::smallint, 4::smallint, null, false, null, false, 5::smallint) as a_tutor \gset
-- (T1 says it went well and the ending was handled well; keeps its id as a_tutor)
select tests.eq((select count(*) from public.my_check_ins('tutor')), 0::bigint, 'an answered end-of-match request is no longer shown'); -- gone
reset role; -- back to the database itself
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select public.answer_check_in(:'t1', :'cara', 0::smallint, 4::smallint, null, false, 'We were not told why the tutor changed.', false, 1::smallint) as a_parent \gset
-- (P1 says the sessions went well but the ending was handled very poorly; keeps its id as a_parent)
select tests.eq((select count(*) from public.match_check_ins), 0::bigint, 'a parent cannot read answers'); -- hidden
reset role; -- back to the database itself

-- 3. Flags.
select tests.eq((select count(*) from public.match_check_ins where id = :'a_parent' and follow_up = 'open' and ending_rating = 1 and fit is null), 1::bigint, 'a poorly handled ending is flagged'); -- flagged
select tests.eq((select count(*) from public.match_check_ins where id = :'a_tutor' and follow_up = 'none'), 1::bigint, 'a good ending is not flagged'); -- not flagged

-- 4. Full admins read them and see them in the overview.
select tests.claims(:'olive', 'aal2'); -- signs in as Olive (owner) with two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.match_check_ins where stage = 0), 2::bigint, 'the owner reads end-of-match answers'); -- visible
select tests.eq((select answered from public.check_in_overview() where student_id = :'cara' and stage = 0), 2, 'the overview counts end-of-match answers'); -- P1 and T1
reset role; -- back to the database itself

-- 5. Matches that ended long ago, or are still running, are not asked.
delete from public.match_check_ins; -- clears the answers, so the request would show again
update public.match_check_in_settings set starts_from = current_date where id; -- now only matches ending from yesterday count
select tests.eq((select count(*) from private.check_in_schedule() where stage = 0 and student_id = :'cara'), 0::bigint, 'a match that ended before the start date is not asked'); -- none
update public.match_check_in_settings set starts_from = current_date - 100 where id; -- back to counting it
update public.tutor_assignments set ends_on = null where tutor_id = :'t1' and student_id = :'cara'; -- the match is running again (no end date)
select tests.eq((select count(*) from private.check_in_schedule() where stage = 0 and student_id = :'cara'), 0::bigint, 'a running match gets no end-of-match request'); -- none

-- Undoes everything above.
rollback;
