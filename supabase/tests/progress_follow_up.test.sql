-- Progress tracking part 2: notes for booked sessions, the family update,
-- note reminders, and the tutor and admin lists. Runs after progress.test.sql
-- and reuses its people: owner ...a0 (admin), tutor T1 ...11 (teaches Cara
-- One), tutor T2 ...12 (teaches Vic Two), parent P1 ...01 (Cara's parent),
-- parent P2 ...02 (Vic's parent).

-- The migration is safe to run twice.
-- Runs the database change 20261029100100_progress_follow_up.sql first, as this test needs it.
\ir ../migrations/20261029100100_progress_follow_up.sql

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Cara's student id as cara.
select id as cara from public.students where full_name = 'Cara One' \gset
-- Keeps Vic's student id as vic.
select id as vic from public.students where full_name = 'Vic Two' \gset
-- Move the earlier test notes out of the way, so they don't count as notes
-- for the sessions below.
update public.session_notes set session_date = current_date - 20 where student_id = :'cara'; -- Moves Cara's existing notes 20 days back.

insert into public.sessions (id, student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status, completed_at, cancelled_at, cancelled_by_role) values -- Adds six test sessions:
  ('00000000-0000-0000-0000-0000000e0001', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', -- Cara with tutor T1,
   now() - interval '31 hours', now() - interval '30 hours', 'completed', now() - interval '30 hours', null, null), -- finished 30 hr ago;
  ('00000000-0000-0000-0000-0000000e0003', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', -- Cara with tutor T1,
   now() - interval '73 hours', now() - interval '72 hours', 'completed', now() - interval '72 hours', null, null), -- finished 72 hr ago;
  ('00000000-0000-0000-0000-0000000e00f0', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', -- Cara with tutor T1,
   now() + interval '2 days', now() + interval '2 days 1 hour', 'scheduled', null, null, null), -- in two days;
  ('00000000-0000-0000-0000-0000000e00c0', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', -- Cara with tutor T1,
   now() - interval '97 hours', now() - interval '96 hours', 'cancelled', null, now() - interval '5 days', 'family'), -- cancelled by the family;
  ('00000000-0000-0000-0000-0000000e00a0', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', -- Cara with tutor T1,
   now() - interval '121 hours', now() - interval '120 hours', 'no_show', null, null, null), -- a no-show;
  ('00000000-0000-0000-0000-0000000e00b0', :'vic', '00000000-0000-0000-0000-000000000012', 'General Maths', 'school', 'online', -- Vic with tutor T2,
   now() - interval '73 hours', now() - interval '72 hours', 'completed', now() - interval '72 hours', null, null); -- finished 72 hr ago.

-- ===========================================================================
-- Reminders: tutor at 24 hr, admins at 48 hr
-- ===========================================================================
select private.queue_note_reminders(); -- Queues reminders to write notes.
select tests.eq((select count(*) from public.progress_notices where kind = 'note_reminder' -- Checks the tutor is reminded after 24 hr:
  and account_id = '00000000-0000-0000-0000-000000000011' -- (tutor T1)
  and session_id in ('00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-0000000e0003')), 2, 'tutor reminded after 24 hr'); -- (for both finished sessions).
select tests.eq((select count(*) from public.progress_notices where kind = 'note_overdue' -- Checks the admin is told only after 48 hr:
  and account_id = '00000000-0000-0000-0000-0000000000a0' -- (the owner)
  and session_id in ('00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-0000000e0003')), 1, 'admin told only after 48 hr'); -- (for just the 72-hr-old session).
select tests.eq((select count(*) from public.progress_notices where session_id in -- Checks there are no reminders for future, cancelled or no-show sessions:
  ('00000000-0000-0000-0000-0000000e00f0', '00000000-0000-0000-0000-0000000e00c0', '00000000-0000-0000-0000-0000000e00a0')), 0, -- (those three sessions),
  'no reminders for future, cancelled or no-show sessions'); -- (the label).
select tests.eq((select count(*) from public.progress_notices where kind = 'note_overdue' -- Checks tutors don't get admin notices:
  and account_id = '00000000-0000-0000-0000-000000000011'), 0, 'tutors don''t get admin notices'); -- (none for tutor T1).
select private.queue_note_reminders(); -- Queues the reminders again (should not repeat).
select tests.eq((select count(*) from public.progress_notices where session_id in -- Checks reminders are queued only once:
  ('00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-0000000e0003') -- (for the two finished sessions)
  and account_id in ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000a0')), 3, 'reminders queued only once'); -- (three in total).
-- Make them visible now, whatever the time of day the test runs.
update public.progress_notices set deliver_at = now() - interval '1 minute'; -- Makes all the notices due now.

-- ===========================================================================
-- Notes due
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_notes_due() where session_id::text like '00000000-0000-0000-0000-0000000e%'), 2, 'tutor sees own sessions needing a note'); -- Checks: tutor sees own sessions needing a note.
select tests.eq((select count(*) from public.list_notes_due() where student_id = :'vic'), 0, 'tutor doesn''t see other tutors'' sessions'); -- Checks: tutor doesn't see other tutors' sessions.
select tests.eq((select count(*) from public.progress_notices where account_id <> '00000000-0000-0000-0000-000000000011'), 0, 'tutor sees only own notices'); -- Checks: tutor sees only own notices.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- Signs in as test account ...11.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_notes_due()), 0, 'tutor without two-step sees nothing due'); -- Checks: tutor without two-step sees nothing due.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_notes_due()), 0, 'parent sees no notes due'); -- Checks: parent sees no notes due.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_notes_due() where session_id::text like '00000000-0000-0000-0000-0000000e%'), 3, 'admin sees everyone''s'); -- Checks: admin sees everyone's.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- A note for a booked session
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.save_session_note( -- The tutor saves a note linked to the 72-hr-old session:
  p_student => :'cara', p_session_date => current_date, p_minutes => 60, p_attendance => 'attended', -- (for Cara, an hour, attended),
  p_went_well => 'You explained your working clearly.', p_next_step => 'Practise comparing fractions with drawings.', -- what went well and the next step,
  p_session => '00000000-0000-0000-0000-0000000e0003', p_home_tip => 'Ask Cara to explain one fraction at dinner.', -- the session and a tip for home,
  -- written in 140 seconds; keeps its id as linked.
  p_writing_seconds => 140) as linked \gset
select tests.eq((select count(*) from public.session_notes where id = :'linked' -- Checks the date comes from the session:
  and session_date = ((now() - interval '73 hours') at time zone 'Australia/Adelaide')::date), 1, 'date comes from the session'); -- (not the date typed).
select tests.fails(format($$select public.save_session_note(p_student => %L, p_session_date => current_date, p_minutes => 60, -- Checks a second note for the same session is refused:
  p_attendance => 'attended', p_went_well => 'ok', p_next_step => 'next', p_session => '00000000-0000-0000-0000-0000000e0003')$$, :'cara'), -- (the same session),
  'second note for the same session'); -- (the label).
select tests.fails(format($$select public.save_session_note(p_student => %L, p_session_date => current_date, p_minutes => 60, -- Checks a note for another student's session is refused:
  p_attendance => 'attended', p_went_well => 'ok', p_next_step => 'next', p_session => '00000000-0000-0000-0000-0000000e00b0')$$, :'cara'), -- (Vic's session),
  'note for another student''s session'); -- (the label).
select tests.fails(format($$select public.save_session_note(p_student => %L, p_session_date => current_date, p_minutes => 60, -- Checks a note for a cancelled session is refused:
  p_attendance => 'attended', p_went_well => 'ok', p_next_step => 'next', p_session => '00000000-0000-0000-0000-0000000e00c0')$$, :'cara'), -- (the cancelled one),
  'note for a cancelled session'); -- (the label).
select tests.fails(format($$select public.save_session_note(p_student => %L, p_session_date => current_date, p_minutes => 60, -- Checks a note for a session that hasn't happened is refused:
  p_attendance => 'attended', p_went_well => 'ok', p_next_step => 'next', p_session => '00000000-0000-0000-0000-0000000e00f0')$$, :'cara'), -- (the future one),
  'note for a session that hasn''t happened'); -- (the label).
select tests.eq((select count(*) from public.session_note_stats), 0, 'tutor can''t read writing times'); -- Checks: tutor can't read writing times.
select tests.fails($$insert into public.session_note_stats (note_id, writing_seconds) select id, 1 from public.session_notes limit 1$$, 'tutor writes stats directly'); -- Checks this is refused: tutor writes stats directly.
select tests.fails($$insert into public.progress_notices (account_id, student_id, kind, title, body, deliver_at) values ('00000000-0000-0000-0000-000000000001', (select id from public.students limit 1), 'session_update', 'x', 'x', now())$$, 'tutor writes notices directly'); -- Checks this is refused: tutor writes notices directly.
update public.session_notes set home_tip = 'Ask Cara to explain one fraction to you.' where id = :'linked'; -- Tries to change the home tip.
select tests.eq((select count(*) from public.session_notes where home_tip like 'Ask Cara to explain one fraction to you%'), 1, 'tutor corrects the tip'); -- Checks: tutor corrects the tip.
select tests.fails(format($$update public.session_notes set session_id = null where id = %L$$, :'linked'), 'note moved off its session'); -- Checks this is refused: note moved off its session.
select tests.eq((select count(*) from public.list_notes_due() where session_id::text like '00000000-0000-0000-0000-0000000e%'), 1, 'noted session no longer due'); -- Checks: noted session no longer due.
-- An older-style note (no session) for the same day also counts.
select public.save_session_note(:'cara', ((now() - interval '31 hours') at time zone 'Australia/Adelaide')::date, 60, 'attended', 'Good focus.', 'Learn the 7 times table.'); -- Saves a note for the 30-hr-old session (not linked).
select tests.eq((select count(*) from public.list_notes_due() where session_id::text like '00000000-0000-0000-0000-0000000e%'), 0, 'same-day note counts for the session'); -- Checks: same-day note counts for the session.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(null); -- Signs out, so no one is signed in.
select tests.eq((select writing_seconds from public.session_note_stats where note_id = :'linked'), 140, 'writing time saved'); -- Checks: writing time saved.
select tests.eq((select count(*) from public.progress_notices where note_id = :'linked' and kind = 'session_update' -- Checks the parent gets the update with the tip:
  and account_id = '00000000-0000-0000-0000-000000000001' and body like '%Try at home: Ask Cara%'), 1, 'parent gets the update with the tip'); -- (one notice mentioning "Try at home").
select tests.eq((select count(*) from public.progress_notices where note_id = :'linked' -- Checks the writer isn't told about their own note:
  and account_id = '00000000-0000-0000-0000-000000000011'), 0, 'the writer isn''t told about their own note'); -- (none for tutor T1).
update public.progress_notices set deliver_at = now() - interval '1 minute' where note_id is not null; -- Makes the note notices due now.

-- ===========================================================================
-- What the family sees
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.session_notes where home_tip is not null), 1, 'parent sees the tip'); -- Checks: parent sees the tip.
update public.session_notes set home_tip = 'changed' where id = :'linked'; -- Tries to change the home tip.
select tests.eq((select count(*) from public.session_notes where home_tip = 'changed'), 0, 'parent cannot change the tip'); -- Checks: parent cannot change the tip.
select tests.eq((select count(*) from public.session_note_stats), 0, 'parent can''t read writing times'); -- Checks: parent can't read writing times.
-- Three: the two notes above, plus the first note in progress.test.sql.
select tests.eq((select count(*) from public.progress_notices where kind = 'session_update' and read_at is null), 3, 'parent sees updates'); -- Checks: parent sees updates.
select tests.eq((select count(*) from public.progress_notices where kind <> 'session_update'), 0, 'parent sees no tutor or admin reminders'); -- Checks: parent sees no tutor or admin reminders.
select tests.fails($$update public.progress_notices set read_at = now()$$, 'parent edits notices directly'); -- Checks this is refused: parent edits notices directly.
select public.mark_progress_notices_read(:'cara'); -- Marks Cara's progress notices as read.
select tests.eq((select count(*) from public.progress_notices where read_at is null), 0, 'parent marks updates read'); -- Checks: parent marks updates read.
select tests.eq((select count(*) from public.progress_students_to_check()), 0, 'parent gets no staff list'); -- Checks: parent gets no staff list.
select tests.fails($$select * from public.progress_measures(current_date - 10, current_date)$$, 'parent reads measures'); -- Checks this is refused: parent reads measures.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.progress_notices), 0, 'other parent sees no updates'); -- Checks: other parent sees no updates.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ===========================================================================
-- Tutor and admin lists
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.progress_students_to_check() where student_id = :'cara'), 1, 'tutor sees own student'); -- Checks: tutor sees own student.
select tests.eq((select count(*) from public.progress_students_to_check() where student_id = :'vic'), 0, 'tutor doesn''t see other students'); -- Checks: tutor doesn't see other students.
-- Two attended notes since a skill last moved.
select tests.eq((select notes_since_movement from public.progress_students_to_check() where student_id = :'cara'), 2, 'sessions since a skill moved'); -- Checks: sessions since a skill moved.
select tests.eq((select active_goals from public.progress_students_to_check() where student_id = :'cara'), 3, 'active goals counted'); -- Checks: active goals counted.
select tests.fails($$select * from public.progress_measures(current_date - 10, current_date)$$, 'tutor reads measures'); -- Checks this is refused: tutor reads measures.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.progress_students_to_check() where student_id in (:'cara', :'vic')), 2, 'admin sees every student with a tutor'); -- Checks: admin sees every student with a tutor.
select tests.eq((select writing_seconds from public.session_note_stats where note_id = :'linked'), 140, 'admin reads writing times'); -- Checks: admin reads writing times.
select tests.eq((select median_writing_seconds from public.progress_measures(current_date - 10, current_date + 1) -- Checks the measures show the median writing time:
  where tutor_id = '00000000-0000-0000-0000-000000000011'), 140, 'measures: median writing time'); -- (140 seconds for tutor T1).
select tests.eq((select (sessions_noted >= 2 and noted_within_24_hr <= sessions_noted and sessions_noted <= sessions_held)::int -- Checks the measures show sessions held and noted:
  from public.progress_measures(current_date - 10, current_date + 1) -- (over the last 10 days)
  where tutor_id = '00000000-0000-0000-0000-000000000011'), 1, 'measures: sessions held and noted'); -- (for tutor T1).
select tests.eq((select sessions_noted - noted_within_24_hr from public.progress_measures(current_date - 10, current_date + 1) -- Checks a tutor with no notes shows none late:
  where tutor_id = '00000000-0000-0000-0000-000000000012'), 0, 'measures: tutor with no notes'); -- (tutor T2).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Tidy up so later tests see the same data as before.
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.sessions where id::text like '00000000-0000-0000-0000-0000000e%'; -- Removes the test sessions.
update public.session_notes set session_date = current_date where student_id = :'cara' and session_date = current_date - 20; -- Moves Cara's notes back to today.

-- Prints that every check in this file passed.
\echo '  progress follow-up: all checks passed'
