-- Training: who can see modules, lessons, quiz answers and completions;
-- marking quizzes; certification; the matching hold; and the handbook.
-- Reuses access_rules.test.sql people: owner (...a0), operations admin
-- (...b0), tutor T1 (...11), tutor T2 (...12), parent P1 (...01).
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the training database change again (checks it can run twice).
\ir ../migrations/20261116300100_training.sql
-- Runs the automatic safety-hours change again too (the training file above replaced its step).
\ir ../migrations/20261118400100_training_safety_hours_auto.sql

-- A test helper: checks a statement is refused with a message containing certain words.
create or replace function tests.fails_with(p_sql text, p_words text, p_label text) returns void -- takes the statement, the words and a label
language plpgsql as $f$ -- (written in PL/pgSQL)
begin -- starts the helper
  execute p_sql; -- runs the statement
  raise exception 'Expected failure but it succeeded: %', p_label; -- if it worked, that's a failure
exception when others then -- if it was refused:
  if sqlerrm like 'Expected failure%' then raise; end if; -- passes on the "it worked" failure from above
  if position(p_words in sqlerrm) = 0 then -- the message doesn't contain the words:
    raise exception 'FAIL %: wrong error: %', p_label, sqlerrm; -- says the wrong error came back
  end if; -- end of the words check
end; -- end of the helper
$f$; -- end of the helper's code

-- Starts with no training modules or handbook pages (in case any were added).
delete from public.training_completions; -- removes completions
delete from public.training_modules; -- removes modules (lessons and questions go with them)
delete from public.handbook_pages; -- removes handbook pages

-- ---------------------------------------------------------------------------
-- Admins write modules; tutors can't.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails($$insert into public.training_modules (title) values ('Tutor-made module')$$, 'tutor adds a module'); -- checks a tutor can't add a module
reset role; -- back to the test runner

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1'); -- acting as the operations admin, without two-step login
set role authenticated; -- as a signed-in person
select tests.fails($$insert into public.training_modules (title) values ('No two-step')$$, 'admin adds a module without two-step login'); -- checks two-step login is needed
reset role; -- back to the test runner

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin, with two-step login
set role authenticated; -- as a signed-in person
insert into public.training_modules (id, title, audience, stage, required, holds_matching, counts_toward_certified, minutes, renew_months, status, position) values -- adds four modules:
  ('10000000-0000-0000-0000-000000000001', 'Child safety and reporting', 'everyone', 'starting', true, true, false, 45, 12, 'published', 1), -- a compulsory safety module for everyone, redone yearly
  ('10000000-0000-0000-0000-000000000002', 'Running a great session', 'tutor', 'starting', true, false, true, 60, null, 'published', 2), -- a compulsory tutor module
  ('10000000-0000-0000-0000-000000000003', 'Office systems', 'admin', 'ongoing', false, false, true, 30, null, 'published', 3), -- an optional admin module
  ('10000000-0000-0000-0000-000000000004', 'Draft module', 'tutor', 'ongoing', false, false, true, 30, null, 'draft', 4); -- a draft
insert into public.training_lessons (module_id, position, title, body) values -- adds a lesson to two modules:
  ('10000000-0000-0000-0000-000000000001', 1, 'Call 000 first', 'If a child is in danger, call 000.'), -- the safety lesson
  ('10000000-0000-0000-0000-000000000004', 1, 'Draft lesson', 'Not ready yet.'); -- the draft lesson
insert into public.training_questions (module_id, position, prompt, options, correct_option) values -- adds two quiz questions to the safety module:
  ('10000000-0000-0000-0000-000000000001', 1, 'A child is in danger right now. What first?', array['Email CLG', 'Call 000', 'Wait'], 2), -- right answer: 2
  ('10000000-0000-0000-0000-000000000001', 2, 'Where do you tell CLG?', array['Child safety page', 'Facebook'], 1); -- right answer: 1
select tests.fails($$insert into public.training_questions (module_id, prompt, options, correct_option) values ('10000000-0000-0000-0000-000000000001', 'Bad', array['a', 'b'], 3)$$, 'right answer outside the choices'); -- checks the right answer must be one of the choices
select tests.eq((select count(*) from public.training_questions_for_admin('10000000-0000-0000-0000-000000000001') where correct_option is not null), 2, 'admin sees the answers'); -- checks admins can read the answers
select tests.fails($$update public.training_modules set version = 5 where id = '10000000-0000-0000-0000-000000000001'$$, 'admin changes version directly'); -- checks the version only changes through "ask everyone to redo"
reset role; -- back to the test runner
select tests.eq((select count(*) from public.training_modules where required_since = private.training_today()), 3, 'published modules start their time allowed today'); -- checks the compulsory date is set on publishing
-- Safety modules never count towards the quarter's hours, whatever is sent (set automatically).
update public.training_modules set counts_toward_certified = true where id = '10000000-0000-0000-0000-000000000001'; -- tries to make the safety module count
select tests.eq((select count(*) from public.training_modules where id = '10000000-0000-0000-0000-000000000001' and not counts_toward_certified), 1, 'safety module never counts towards quarter hours'); -- checks it still doesn't count
update public.training_modules set counts_toward_certified = false where id = '10000000-0000-0000-0000-000000000002'; -- tries to stop an ordinary module counting
select tests.eq((select count(*) from public.training_modules where id = '10000000-0000-0000-0000-000000000002' and counts_toward_certified), 1, 'other modules always count towards quarter hours'); -- checks it still counts

-- ---------------------------------------------------------------------------
-- What tutors can see.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- acting as T1 without two-step login
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_modules), 0, 'no modules without two-step login'); -- checks two-step login is needed to see training
reset role; -- back to the test runner

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as T1 with two-step login
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_modules), 2, 'tutor sees published modules for tutors and everyone'); -- checks T1 sees 2 (not the admin module or the draft)
select tests.eq((select count(*) from public.training_lessons), 1, 'tutor sees lessons of those modules only'); -- checks the draft lesson is hidden
select tests.eq((select count(*) from public.training_questions), 2, 'tutor sees the questions'); -- checks the questions show
select tests.fails($$select correct_option from public.training_questions$$, 'tutor reads the right answers'); -- checks the right answers are hidden
select tests.fails($$select * from public.training_questions_for_admin('10000000-0000-0000-0000-000000000001')$$, 'tutor uses the admin answers list'); -- checks the admin list is refused
select tests.fails($$insert into public.training_completions (account_id, module_id, module_version, module_title, audience, minutes, paid, counts_toward_certified, completed_on, certificate_no) values (auth.uid(), '10000000-0000-0000-0000-000000000001', 1, 'x', 'tutor', 5, true, false, current_date, 'FAKE')$$, 'tutor adds a completion directly'); -- checks completions can't be faked
select tests.fails_with($$select public.training_finish('10000000-0000-0000-0000-000000000003', '{}')$$, 'isn''t available', 'tutor finishes an admin module'); -- checks admin modules are refused
select tests.fails_with($$select public.training_finish('10000000-0000-0000-0000-000000000001', '{2}')$$, 'answer every question', 'quiz with a missing answer'); -- checks every question must be answered

-- Marking: one wrong answer fails (100% needed); all right passes.
select tests.eq((public.training_finish('10000000-0000-0000-0000-000000000001', '{2,2}') ->> 'passed')::boolean::int, 0, 'one wrong answer does not pass'); -- checks 100% is needed
select tests.eq((select count(*) from public.training_attempts where module_id = '10000000-0000-0000-0000-000000000001'), 1, 'the try is kept'); -- checks the attempt was saved
select tests.eq((select wrong_positions[1] from public.training_attempts where module_id = '10000000-0000-0000-0000-000000000001'), 2, 'says question 2 was wrong'); -- checks the wrong question number is kept
select tests.eq((public.training_finish('10000000-0000-0000-0000-000000000001', '{2,1}') ->> 'passed')::boolean::int, 1, 'all right passes'); -- checks a full score passes
select tests.eq((select count(*) from public.training_completions), 1, 'one completion recorded'); -- checks the completion was saved
select tests.eq((select count(*) from public.training_completions where paid and not counts_toward_certified and expires_on = (private.training_today() + interval '12 months')::date), 1, 'paid, not counted for certification, redo in 12 months'); -- checks the completion's details
select tests.eq((public.training_finish('10000000-0000-0000-0000-000000000001', '{2,1}') ->> 'already')::boolean::int, 1, 'finishing again is not recorded twice'); -- checks there's no second (paid) completion
select tests.eq((select count(*) from public.training_completions), 1, 'still one completion'); -- checks the count
select tests.eq((public.training_finish('10000000-0000-0000-0000-000000000002', '{}') ->> 'passed')::boolean::int, 1, 'a module without a quiz is finished'); -- checks a module with no quiz can be finished
select tests.eq((select count(*) from public.training_my_modules() where state = 'done'), 2, 'both tutor modules show as done'); -- checks the status list
reset role; -- back to the test runner

-- Others can't see T1's training; full admins can.
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- acting as tutor T2
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_completions), 0, 'another tutor sees no completions'); -- checks T2 can't see T1's completions
select tests.eq((select count(*) from public.training_attempts), 0, 'another tutor sees no attempts'); -- checks T2 can't see T1's attempts
select tests.fails($$select * from public.training_certification('00000000-0000-0000-0000-000000000011')$$, 'tutor reads another tutor''s certification'); -- checks certification is private
select tests.fails($$select * from public.training_progress()$$, 'tutor reads the progress table'); -- checks the admin table is refused
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- acting as parent P1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_modules), 0, 'a parent sees no training'); -- checks parents see nothing
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.training_completions where account_id = '00000000-0000-0000-0000-000000000011'), 2, 'owner sees T1''s completions'); -- checks the owner sees them
select tests.eq((select count(*) from public.training_progress() where account_id = '00000000-0000-0000-0000-000000000011'), 2, 'progress table lists T1''s two compulsory modules'); -- checks the progress table
reset role; -- back to the test runner

-- ---------------------------------------------------------------------------
-- Certification: in training until compulsory modules are done; then
-- certified; lapsed when a full quarter ends short of hours.
-- ---------------------------------------------------------------------------
select tests.eq((select count(*) from private.training_cert('00000000-0000-0000-0000-000000000012') where state = 'in_training'), 1, 'T2 is still in training'); -- checks T2 (nothing done) isn't certified
select tests.eq((select count(*) from private.training_cert('00000000-0000-0000-0000-000000000011') where state = 'certified'), 1, 'T1 is certified'); -- checks T1 is certified
update public.training_completions set completed_on = completed_on - 400 -- pretend T1 finished more than a year ago,
  where account_id = '00000000-0000-0000-0000-000000000011'; -- (both modules)
update public.training_completions set expires_on = null where account_id = '00000000-0000-0000-0000-000000000011'; -- (and the safety one doesn't run out, for this check)
select tests.eq((select count(*) from private.training_cert('00000000-0000-0000-0000-000000000011') where state = 'lapsed'), 1, 'no hours last quarter: lapsed'); -- checks a short quarter lapses
insert into public.training_completions (account_id, module_id, module_version, module_title, audience, minutes, paid, counts_toward_certified, completed_on, certificate_no) -- T1 does 3 hr of counted training this quarter
values ('00000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000002', 1, 'Extra', 'tutor', 180, false, true, private.training_today(), 'CLG-TEST-1'); -- (180 minutes today)
select tests.eq((select count(*) from private.training_cert('00000000-0000-0000-0000-000000000011') where state = 'certified'), 1, 'caught up this quarter: certified again'); -- checks catching up restores it

-- ---------------------------------------------------------------------------
-- Matching hold: an overdue safety module refuses NEW matches only.
-- ---------------------------------------------------------------------------
select tests.eq(private.training_matching_ok('00000000-0000-0000-0000-000000000012')::int, 1, 'inside the 4 weeks: not held'); -- checks T2 isn't held yet
update public.training_modules set required_since = private.training_today() - 60 where id = '10000000-0000-0000-0000-000000000001'; -- the safety module became compulsory 60 days ago
update public.account_roles set granted_at = now() - interval '90 days' where account_id = '00000000-0000-0000-0000-000000000012'; -- T2 joined 90 days ago
select tests.eq(private.training_matching_ok('00000000-0000-0000-0000-000000000012')::int, 0, 'past the 4 weeks: T2 held'); -- checks T2 is now held
select tests.eq(private.training_matching_ok('00000000-0000-0000-0000-000000000011')::int, 1, 'T1 finished it: not held'); -- checks T1 isn't held

-- T1's safety module ran out: T1 is held too.
update public.account_roles set granted_at = now() - interval '90 days' where account_id = '00000000-0000-0000-0000-000000000011'; -- T1 joined 90 days ago
update public.training_completions set expires_on = private.training_today() - 1 -- T1's safety completion ran out yesterday
  where account_id = '00000000-0000-0000-0000-000000000011' and module_id = '10000000-0000-0000-0000-000000000001'; -- (the safety module)
select tests.eq(private.training_matching_ok('00000000-0000-0000-0000-000000000011')::int, 0, 'expired safety module: T1 held'); -- checks an expired module holds matches

-- A new match for T1 is refused; existing matches stay.
delete from public.tutor_assignments where tutor_id = '00000000-0000-0000-0000-000000000011' -- removes T1's match with Ada (so it's a new match)
  and student_id = (select id from public.students where full_name = 'Ada Learner'); -- (Ada)
-- Keeps how many matches T1 has now as t1_matches.
select count(*) as t1_matches from public.tutor_assignments where tutor_id = '00000000-0000-0000-0000-000000000011' \gset
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.fails_with($$insert into public.tutor_assignments (tutor_id, student_id, subject) select '00000000-0000-0000-0000-000000000011', id, 'English' from public.students where full_name = 'Ada Learner'$$, -- tries to match T1 with Ada again
  'compulsory child safety training', 'new match refused while training overdue'); -- checks it's refused with the training reason
select tests.eq((select count(*) from public.training_matching_holds() where tutor_id = '00000000-0000-0000-0000-000000000011'), 1, 'Matching page lists T1 as held'); -- checks the Matching page list
reset role; -- back to the test runner
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = '00000000-0000-0000-0000-000000000011'), :t1_matches, 'existing students stay'); -- checks T1's other matches are untouched by the hold

-- T1 redoes it: the match is allowed again.
delete from public.training_completions where account_id = '00000000-0000-0000-0000-000000000011' and module_id = '10000000-0000-0000-0000-000000000001'; -- clears the old completion
insert into public.training_completions (account_id, module_id, module_version, module_title, audience, minutes, paid, counts_toward_certified, completed_on, expires_on, certificate_no) -- T1 redoes the safety module today
values ('00000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000001', 1, 'Child safety', 'everyone', 45, true, false, private.training_today(), private.training_today() + 365, 'CLG-TEST-2'); -- (in date for a year)
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
insert into public.tutor_assignments (tutor_id, student_id, subject) select '00000000-0000-0000-0000-000000000011', id, 'English' from public.students where full_name = 'Ada Learner'; -- matches T1 with Ada (works now)
reset role; -- back to the test runner
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = '00000000-0000-0000-0000-000000000011' and student_id = (select id from public.students where full_name = 'Ada Learner')), 1, 'match allowed once training is done'); -- checks the match was added

-- ---------------------------------------------------------------------------
-- Reminders: each goes once.
-- ---------------------------------------------------------------------------
-- Runs the daily reminders once (keeping the count as first_run).
select private.queue_training_reminders() as first_run \gset
select tests.eq((select count(*) from public.training_reminders where account_id = '00000000-0000-0000-0000-000000000012' and kind = 'overdue'), 1, 'T2 reminded that training is overdue'); -- checks T2's overdue reminder
select tests.eq(private.queue_training_reminders(), 0, 'reminders are not sent twice'); -- checks a second run sends nothing new

-- "Ask everyone to redo" makes the module due again with fresh time allowed.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select public.training_ask_redo('10000000-0000-0000-0000-000000000001'); -- asks everyone to redo the safety module
reset role; -- back to the test runner
select tests.eq((select count(*) from private.training_state('00000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000001') where state = 'to_do'), 1, 'redo: T1 has it to do again'); -- checks T1 needs to redo it
select tests.eq(private.training_matching_ok('00000000-0000-0000-0000-000000000011')::int, 1, 'redo: inside the fresh 4 weeks, not held'); -- checks they aren't held straight away

-- ---------------------------------------------------------------------------
-- Handbook.
-- ---------------------------------------------------------------------------
insert into public.handbook_pages (title, body, urgent, audience, status) values -- adds three pages:
  ('Something''s happened', 'Call 000 first.', true, 'everyone', 'published'), -- a published urgent page for everyone
  ('Admin only page', 'For admins.', false, 'admin', 'published'), -- a published admin page
  ('Draft page', 'Not ready.', false, 'everyone', 'draft'); -- a draft
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.handbook_pages), 1, 'tutor sees only the published page for them'); -- checks T1 sees 1 page
select tests.fails($$insert into public.handbook_pages (title) values ('Tutor page')$$, 'tutor adds a handbook page'); -- checks tutors can't write pages
reset role; -- back to the test runner
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- acting as parent P1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.handbook_pages), 0, 'a parent sees no handbook'); -- checks parents see nothing
reset role; -- back to the test runner
select tests.claims(null); -- clears who is signed in

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  training: all checks passed'
