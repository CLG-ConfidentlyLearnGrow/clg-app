-- Summary: checks feedback from everyone (Carla, 15 Nov 2026): anyone signed
-- in can give it, feedback about a person is read only by the Child Safety
-- Officer (or the deputy when it's about the officer) and never by the person
-- it's about, other feedback is read by full admins, the giver sees their own
-- without the admins' note, and only the owner changes the areas. Reuses
-- access_rules.test.sql people: owner Olive (...a0, officer), operations
-- admin Sam Staff (...b0, deputy), tutor T1 (...11, teaches Cara), tutor T2
-- (...12), parent P1 (...01, Cara's parent). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the feedback database change again (checks it can run twice).
\ir ../migrations/20261117200100_feedback.sql

select tests.claims(null); -- acts as the database itself while setting up
update public.child_safety_contacts set officer_id = '00000000-0000-0000-0000-0000000000a0', deputy_id = '00000000-0000-0000-0000-0000000000b0' where id; -- Olive is officer, Sam Staff is deputy
\set olive '00000000-0000-0000-0000-0000000000a0'
-- (Olive's account id: owner and officer)
\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id: operations admin and deputy)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id)
\set t2 '00000000-0000-0000-0000-000000000012'
-- (tutor T2's account id)
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)

-- 1. Giving feedback.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select public.give_feedback('app_billing', 'idea', 4::smallint, 'It would help to see all invoices on one page.') as f_app \gset
-- (P1 gives an idea about billing in the app; keeps its id as f_app)
select public.give_feedback('service_tutoring', 'praise', 5::smallint, 'Cara loves her sessions.') as f_service \gset
-- (P1 praises the tutoring; keeps its id as f_service)
select public.give_feedback('people_person', 'worry', null, 'The tutor is often a few minutes late.', :'t1') as f_tutor \gset
-- (P1 gives a worry about tutor T1; keeps its id as f_tutor)
select public.give_feedback('people_person', 'worry', 2::smallint, 'Hard to get a reply from the owner.', :'olive') as f_owner \gset
-- (P1 gives a worry about Olive, the officer; keeps its id as f_owner)
select tests.fails($q$select public.give_feedback('nowhere', 'idea', null, 'Not a real area.')$q$, 'the area must be on the list'); -- refused
select tests.fails($q$select public.give_feedback('app_other', 'rant', null, 'Not a real kind.')$q$, 'the kind must be praise, idea or worry'); -- refused
select tests.fails($q$select public.give_feedback('app_other', 'idea', 9::smallint, 'Rating too high.')$q$, 'ratings go from 1 to 5'); -- refused
select tests.fails($q$select public.give_feedback('app_other', 'idea', null, 'x')$q$, 'a few words are needed'); -- refused
select tests.fails(format($q$select public.give_feedback('people_person', 'worry', null, 'About a tutor I have never had.', %L)$q$, :'t2'), 'a parent can''t give feedback about someone not on their list'); -- refused
select tests.fails($q$select public.give_feedback('people_person', 'worry', null, 'No person chosen.')$q$, 'feedback about a person needs a person'); -- refused
select tests.fails(format($q$select public.give_feedback('app_other', 'idea', null, 'A person on an app area.', %L)$q$, :'t1'), 'a person can only go with "A person at CLG"'); -- refused
select tests.fails(format($q$insert into public.feedback (given_by_name, area_id, kind, comment) values ('x', 'app_other', 'idea', 'Direct insert')$q$), 'nobody adds feedback directly'); -- refused
select tests.eq((select count(*) from public.my_feedback()), 4::bigint, 'the giver sees their own feedback'); -- all four
select tests.eq((select count(*) from public.feedback), 0::bigint, 'a parent can''t read the feedback table'); -- not a reviewer
reset role; -- back to the database itself
select tests.eq((select count(*) from public.feedback where id = :'f_tutor' and reader_id = :'olive'), 1::bigint, 'feedback about a tutor goes to the officer'); -- routed to Olive
select tests.eq((select count(*) from public.feedback where id = :'f_owner' and reader_id = :'sam'), 1::bigint, 'feedback about the officer goes to the deputy'); -- routed to Sam

-- 2. Staff can give feedback about a colleague, but not about themselves.
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select public.give_feedback('people_person', 'praise', null, 'T2 shared great worksheets with me.', :'t2') as f_colleague \gset
-- (T1 praises colleague T2; keeps its id as f_colleague)
select tests.fails(format($q$select public.give_feedback('people_person', 'praise', null, 'I am great.', %L)$q$, :'t1'), 'nobody gives feedback about themselves'); -- refused

-- 3. The person feedback is about never sees it.
select tests.eq((select count(*) from public.feedback where about_account = :'t1'), 0::bigint, 'the tutor can''t see feedback about them'); -- hidden
reset role; -- back to the database itself
select tests.claims(:'olive', 'aal2'); -- signs in as Olive (owner and officer)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.feedback where id = :'f_owner'), 0::bigint, 'the officer, even as owner, can''t see feedback about herself'); -- hidden
select tests.eq((select count(*) from public.feedback where id in (:'f_tutor', :'f_colleague')), 2::bigint, 'the officer reads feedback about other people'); -- visible
select tests.eq((select count(*) from public.feedback where id in (:'f_app', :'f_service')), 2::bigint, 'the owner reads app and service feedback'); -- visible
select tests.fails(format($q$select public.feedback_update(%L, 'done', 'Spoke to her.')$q$, :'f_owner'), 'the officer can''t update feedback about herself'); -- refused
select public.feedback_update(:'f_tutor', 'acting', 'Spoke to the tutor about being on time.'); -- the officer records what was done
reset role; -- back to the database itself
select tests.claims(:'sam', 'aal2'); -- signs in as Sam (operations admin and deputy)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.feedback where id = :'f_owner'), 1::bigint, 'the deputy reads feedback about the officer'); -- visible
select tests.eq((select count(*) from public.feedback where id in (:'f_tutor', :'f_colleague')), 0::bigint, 'the deputy (an admin) can''t read other feedback about people'); -- hidden: only the officer
select tests.eq((select count(*) from public.feedback where id in (:'f_app', :'f_service')), 2::bigint, 'operations admins read app and service feedback'); -- visible
reset role; -- back to the database itself
select tests.claims(:'sam', 'aal1'); -- Sam WITHOUT two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.feedback), 0::bigint, 'without two-step sign-in nothing is visible'); -- hidden
reset role; -- back to the database itself
select tests.claims(:'t2', 'aal2'); -- signs in as tutor T2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.feedback), 0::bigint, 'a tutor reads no one''s feedback'); -- hidden
select tests.fails(format($q$select public.feedback_update(%L, 'done', null)$q$, :'f_app'), 'a tutor can''t update feedback'); -- refused
reset role; -- back to the database itself

-- 4. The giver sees where it's up to, but not the admins' note.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_feedback() where id = :'f_tutor' and status = 'acting'), 1::bigint, 'the giver sees that it''s being acted on'); -- status visible
reset role; -- back to the database itself

-- 5. Only the owner changes the areas.
select tests.claims(:'sam', 'aal2'); -- signs in as Sam (operations)
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select public.set_feedback_area('app_new', 'app', 'New area', true)$q$, 'only the owner adds areas'); -- refused
reset role; -- back to the database itself
select tests.claims(:'olive', 'aal2'); -- signs in as the owner
set role authenticated; -- acts as a signed-in person
select public.set_feedback_area('app_messages', 'app', 'Messages', true); -- adds an area
select public.set_feedback_area('app_other', 'app', 'Something else in the app', false); -- hides one
select tests.fails($q$select public.set_feedback_area('people_extra', 'people', 'Another person area', true)$q$, 'the person area can''t be added to'); -- refused
reset role; -- back to the database itself
select tests.eq((select count(*) from public.feedback_areas where id = 'app_messages' and active), 1::bigint, 'the new area is there'); -- added
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.fails($q$select public.give_feedback('app_other', 'idea', null, 'A hidden area.')$q$, 'a hidden area can''t be picked'); -- refused
reset role; -- back to the database itself

-- 6. Concerning words: checked for app feedback, not for feedback about a person.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select public.give_feedback('app_ease', 'worry', null, 'My child said they want to kill myself, in those words.') as f_words \gset
-- (P1 gives app feedback with concerning words; keeps its id as f_words)
select public.give_feedback('people_person', 'worry', null, 'My child said they want to kill myself, in those words after the session.', :'olive') as f_words_person \gset
-- (and feedback about Olive with the same words; keeps its id as f_words_person)
reset role; -- back to the database itself
select tests.eq((select count(*) from public.safety_word_flags where source_table = 'feedback' and source_id = :'f_words'), 1::bigint, 'app feedback with concerning words is flagged'); -- flagged
select tests.eq((select count(*) from public.safety_word_flags where source_table = 'feedback' and source_id = :'f_words_person'), 0::bigint, 'feedback about a person isn''t flagged (that would show it to them)'); -- not flagged

-- 7. The activity log has ids only.
select tests.eq((select count(*) from public.audit_log where details::text like '%late%' or details::text like '%invoices%'), 0::bigint, 'no feedback words in the activity log'); -- nothing leaked

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  feedback: all checks passed'
