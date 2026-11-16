-- Summary: checks the check-ins after a new match (Carla, 16 Nov 2026): the
-- tutor, the parents and a learner with their own login are each asked at
-- 1, 2 and 6 weeks after the first session; only a waiting check-in can be
-- answered, and only once; a poor answer is flagged; only full admins read
-- the answers (the tutor never sees the family's, and the family never sees
-- the tutor's); old matches and ended matches are not asked; quiet hours are
-- kept. Reuses access_rules.test.sql people: owner Olive (...a0), operations
-- admin Sam Staff (...b0), tutor T1 (...11, teaches Cara and Ada), tutor T2
-- (...12), parent P1 (...01, Cara's parent), parent P2 (...02). Everything
-- is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the check-ins database change again (checks it can run twice).
\ir ../migrations/20261119800100_match_check_ins.sql

select tests.claims(null); -- acts as the database itself while setting up
\set olive '00000000-0000-0000-0000-0000000000a0'
-- (Olive's account id: owner)
\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id: operations admin)
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
select id as ada, account_id as ada_login from public.students where full_name = 'Ada Learner' \gset
-- (keeps Ada's student id as ada and her own login as ada_login)

update public.match_check_in_settings set starts_from = current_date - 100 where id; -- counts matches from 100 days ago as new, for these tests
delete from public.sessions where tutor_id = :'t1' and student_id in (:'cara', :'ada'); -- clears any sessions other tests left for these matches
insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at, status) values -- adds first sessions:
  (:'cara', :'t1', :'fam1', 'General Maths', 'school', 'online', now() - interval '8 days 1 hour', now() - interval '8 days', 'completed'), -- Cara with T1, 8 days ago (so the 1-week check-in is open),
  (:'ada', :'t1', null, 'English', 'tertiary', 'online', now() - interval '15 days 1 hour', now() - interval '15 days', 'completed'); -- Ada with T1, 15 days ago (so the 2-week check-in is open)

-- 1. Quiet hours: a check-in opening at 10pm Adelaide waits until 5am.
select tests.eq( -- checks the time it may be shown:
  (private.check_in_due_at(:'p1', timestamptz '2026-11-20 22:00 Australia/Adelaide') -- opening at 10pm for P1 (an SA parent)
    = timestamptz '2026-11-21 05:00 Australia/Adelaide')::int, -- is shown from 5am the next morning (1 means yes)
  1, 'a check-in is held until quiet hours end'); -- expects yes, with the label
select tests.eq( -- checks a daytime check-in:
  (private.check_in_due_at(:'p1', timestamptz '2026-11-20 16:00 Australia/Adelaide') -- opening at 4pm
    = timestamptz '2026-11-20 16:00 Australia/Adelaide')::int, -- is shown straight away (1 means yes)
  1, 'a daytime check-in is not held'); -- expects yes, with the label

-- 2. Who is asked.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.my_check_ins('parent') where student_id = :'cara' and stage = 1), 1::bigint, 'the parent is asked the 1-week check-in'); -- asked
select tests.eq((select count(*) from public.my_check_ins('parent') where student_id = :'cara' and tutor_first_name = 'Tess'), 1::bigint, 'the question uses the tutor first name'); -- first name only (Tess Tutor)
select tests.eq((select count(*) from public.my_check_ins('tutor')), 0::bigint, 'a parent has no tutor check-ins'); -- none
reset role; -- back to the database itself
select tests.claims(:'t1'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_check_ins('tutor') where student_id = :'cara' and stage = 1), 1::bigint, 'the tutor is asked about Cara at 1 week'); -- asked
select tests.eq((select count(*) from public.my_check_ins('tutor') where student_id = :'ada' and stage = 2), 1::bigint, 'the tutor is asked about Ada at 2 weeks'); -- asked
select tests.eq((select count(*) from public.my_check_ins('tutor') where student_id = :'ada' and stage = 1), 0::bigint, 'a closed check-in is not shown'); -- the 1-week one closed at day 14
reset role; -- back to the database itself
select tests.claims(:'ada_login'); -- signs in as Ada (an adult learner with her own login)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_check_ins('student') where student_id = :'ada' and stage = 2), 1::bigint, 'a learner with their own login is asked'); -- asked
reset role; -- back to the database itself
select tests.claims(:'p2'); -- signs in as parent P2 (not Cara's parent)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_check_ins('parent') where student_id = :'cara'), 0::bigint, 'another family is not asked about Cara'); -- not theirs
select tests.fails(format($q$select public.answer_check_in(%L, %L, 1::smallint, 5::smallint, 'yes', false, null)$q$, :'t1', :'cara'), 'another family cannot answer for Cara'); -- refused
reset role; -- back to the database itself
select tests.claims(:'t2'); -- signs in as tutor T2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_check_ins('tutor')), 0::bigint, 'another tutor is not asked'); -- none for T2
select tests.fails(format($q$select public.answer_check_in(%L, %L, 1::smallint, 5::smallint, 'yes', false, null)$q$, :'t1', :'cara'), 'another tutor cannot answer for T1'); -- refused
reset role; -- back to the database itself

-- 3. Answering.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.answer_check_in(%L, %L, 1::smallint, 9::smallint, 'yes', false, null)$q$, :'t1', :'cara'), 'ratings go from 1 to 5'); -- refused
select tests.fails(format($q$select public.answer_check_in(%L, %L, 1::smallint, 4::smallint, 'maybe', false, null)$q$, :'t1', :'cara'), 'the fit must be yes, not sure or no'); -- refused
select tests.fails(format($q$select public.answer_check_in(%L, %L, 2::smallint, 4::smallint, 'yes', false, null)$q$, :'t1', :'cara'), 'a check-in that is not open yet cannot be answered'); -- the 2-week one is not open
select tests.fails(format($q$insert into public.match_check_ins (tutor_id, student_id, stage, respondent_kind, respondent_name, tutor_name, student_name, skipped) values (%L, %L, 1, 'parent', 'x', 'x', 'x', true)$q$, :'t1', :'cara'), 'nobody adds answers directly'); -- refused
select public.answer_check_in(:'t1', :'cara', 1::smallint, 2::smallint, 'unsure', false, 'Cara seems a bit shy with her tutor.') as a_parent \gset
-- (P1 answers with a poor rating; keeps its id as a_parent)
select tests.eq((select count(*) from public.my_check_ins('parent')), 0::bigint, 'an answered check-in is no longer shown'); -- gone
select tests.fails(format($q$select public.answer_check_in(%L, %L, 1::smallint, 5::smallint, 'yes', false, null)$q$, :'t1', :'cara'), 'each check-in is answered once'); -- refused
select tests.eq((select count(*) from public.match_check_ins), 0::bigint, 'a parent cannot read answers, even their own'); -- hidden
reset role; -- back to the database itself
select tests.claims(:'t1'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.match_check_ins), 0::bigint, 'the tutor cannot read the family answer'); -- hidden
select public.answer_check_in(:'t1', :'cara', 1::smallint, 5::smallint, 'yes', false, null) as a_tutor \gset
-- (T1 answers well; keeps its id as a_tutor)
select public.answer_check_in(:'t1', :'ada', 2::smallint, null, null, false, null, true) as a_skip \gset
-- (T1 skips the 2-week check-in for Ada; keeps its id as a_skip)
select tests.eq((select count(*) from public.my_check_ins('tutor')), 0::bigint, 'a skipped check-in is no longer shown'); -- gone
reset role; -- back to the database itself
select tests.claims(:'ada_login'); -- signs in as Ada
set role authenticated; -- acts as a signed-in person
select public.answer_check_in(:'t1', :'ada', 2::smallint, 4::smallint, 'yes', true, null) as a_contact \gset
-- (Ada answers well but asks CLG to contact her; keeps its id as a_contact)
reset role; -- back to the database itself

-- 4. Flags for follow-up.
select tests.eq((select count(*) from public.match_check_ins where id = :'a_parent' and follow_up = 'open'), 1::bigint, 'a rating of 2 is flagged'); -- flagged
select tests.eq((select count(*) from public.match_check_ins where id = :'a_tutor' and follow_up = 'none'), 1::bigint, 'a good answer is not flagged'); -- not flagged
select tests.eq((select count(*) from public.match_check_ins where id = :'a_skip' and follow_up = 'none'), 1::bigint, 'a skip is not flagged'); -- not flagged
select tests.eq((select count(*) from public.match_check_ins where id = :'a_contact' and follow_up = 'open'), 1::bigint, 'asking CLG to make contact is flagged'); -- flagged
select tests.eq((select count(*) from public.match_check_ins where id = :'a_contact' and respondent_kind = 'student'), 1::bigint, 'the learner answer is marked as the learner'); -- recorded role

-- 5. Full admins read answers and follow up.
select tests.claims(:'olive', 'aal2'); -- signs in as Olive (owner) with two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.match_check_ins where id in (:'a_parent', :'a_tutor', :'a_skip', :'a_contact')), 4::bigint, 'the owner reads every answer'); -- visible
select tests.eq((select answered from public.check_in_overview() where student_id = :'cara' and stage = 1), 2, 'the overview counts answers'); -- P1 and T1
select tests.eq((select skipped from public.check_in_overview() where student_id = :'ada' and stage = 2), 1, 'the overview counts skips'); -- T1 skipped
select tests.eq((select asked from public.check_in_overview() where student_id = :'ada' and stage = 2), 2, 'the overview counts who was asked'); -- T1 and Ada
select public.check_in_follow_up(:'a_parent', true, 'Rang P1. Cara is settling in.'); -- marks it followed up
select tests.eq((select count(*) from public.match_check_ins where id = :'a_parent' and follow_up = 'done'), 1::bigint, 'a flag can be marked followed up'); -- done
reset role; -- back to the database itself
select tests.claims(:'sam', 'aal2'); -- signs in as Sam (operations) with two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.match_check_ins where id = :'a_contact'), 1::bigint, 'operations admins read answers'); -- visible
select public.check_in_follow_up(:'a_parent', false, null); -- opens it again
select tests.eq((select count(*) from public.match_check_ins where id = :'a_parent' and follow_up = 'open'), 1::bigint, 'a flag can be opened again'); -- open
reset role; -- back to the database itself
select tests.claims(:'sam', 'aal1'); -- Sam WITHOUT two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.match_check_ins), 0::bigint, 'no answers without two-step sign-in'); -- hidden
select tests.eq((select count(*) from public.check_in_overview()), 0::bigint, 'no overview without two-step sign-in'); -- hidden
select tests.fails(format($q$select public.check_in_follow_up(%L, true, null)$q$, :'a_contact'), 'no follow-up without two-step sign-in'); -- refused
reset role; -- back to the database itself
select tests.claims(:'t1', 'aal2'); -- tutor T1 with two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.check_in_overview()), 0::bigint, 'a tutor gets no overview'); -- hidden
select tests.fails(format($q$select public.check_in_follow_up(%L, true, null)$q$, :'a_contact'), 'a tutor cannot follow up'); -- refused
reset role; -- back to the database itself

-- 6. Old and ended matches are not asked.
update public.match_check_in_settings set starts_from = current_date where id; -- now only matches starting today count as new
select tests.eq((select count(*) from private.check_in_schedule()), 0::bigint, 'matches that started before the start date get no check-ins'); -- none (checked as the database itself, because the schedule is private)
update public.match_check_in_settings set starts_from = current_date - 100 where id; -- back to counting them
delete from public.match_check_ins where tutor_id = :'t1' and student_id = :'cara'; -- clears Cara's answers so her check-in would be open again
update public.tutor_assignments set starts_on = current_date - 30, ends_on = current_date - 1 where tutor_id = :'t1' and student_id = :'cara'; -- ends the match yesterday
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_check_ins('parent')), 0::bigint, 'an ended match gets no check-ins'); -- none
reset role; -- back to the database itself

-- 7. Comments are checked for concerning words.
select tests.eq((select count(*) from pg_catalog.pg_trigger where tgname = 'watch_words_scan' and tgrelid = 'public.match_check_ins'::regclass), 1::bigint, 'check-in comments are checked for concerning words'); -- the check is on

-- Undoes everything above.
rollback;
