-- Progress tracking part 2: notes for booked sessions, the family update,
-- note reminders, and the tutor and admin lists. Runs after progress.test.sql
-- and reuses its people: owner ...a0 (admin), tutor T1 ...11 (teaches Cara
-- One), tutor T2 ...12 (teaches Vic Two), parent P1 ...01 (Cara's parent),
-- parent P2 ...02 (Vic's parent).

-- The migration is safe to run twice.
\ir ../migrations/20261029100100_progress_follow_up.sql

select tests.claims(null);
select id as cara from public.students where full_name = 'Cara One' \gset
select id as vic from public.students where full_name = 'Vic Two' \gset
-- Move the earlier test notes out of the way, so they don't count as notes
-- for the sessions below.
update public.session_notes set session_date = current_date - 20 where student_id = :'cara';

insert into public.sessions (id, student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status, completed_at, cancelled_at, cancelled_by_role) values
  ('00000000-0000-0000-0000-0000000e0001', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online',
   now() - interval '31 hours', now() - interval '30 hours', 'completed', now() - interval '30 hours', null, null),
  ('00000000-0000-0000-0000-0000000e0003', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online',
   now() - interval '73 hours', now() - interval '72 hours', 'completed', now() - interval '72 hours', null, null),
  ('00000000-0000-0000-0000-0000000e00f0', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online',
   now() + interval '2 days', now() + interval '2 days 1 hour', 'scheduled', null, null, null),
  ('00000000-0000-0000-0000-0000000e00c0', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online',
   now() - interval '97 hours', now() - interval '96 hours', 'cancelled', null, now() - interval '5 days', 'family'),
  ('00000000-0000-0000-0000-0000000e00a0', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online',
   now() - interval '121 hours', now() - interval '120 hours', 'no_show', null, null, null),
  ('00000000-0000-0000-0000-0000000e00b0', :'vic', '00000000-0000-0000-0000-000000000012', 'General Maths', 'school', 'online',
   now() - interval '73 hours', now() - interval '72 hours', 'completed', now() - interval '72 hours', null, null);

-- ===========================================================================
-- Reminders: tutor at 24 hr, admins at 48 hr
-- ===========================================================================
select private.queue_note_reminders();
select tests.eq((select count(*) from public.progress_notices where kind = 'note_reminder'
  and account_id = '00000000-0000-0000-0000-000000000011'
  and session_id in ('00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-0000000e0003')), 2, 'tutor reminded after 24 hr');
select tests.eq((select count(*) from public.progress_notices where kind = 'note_overdue'
  and account_id = '00000000-0000-0000-0000-0000000000a0'
  and session_id in ('00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-0000000e0003')), 1, 'admin told only after 48 hr');
select tests.eq((select count(*) from public.progress_notices where session_id in
  ('00000000-0000-0000-0000-0000000e00f0', '00000000-0000-0000-0000-0000000e00c0', '00000000-0000-0000-0000-0000000e00a0')), 0,
  'no reminders for future, cancelled or no-show sessions');
select tests.eq((select count(*) from public.progress_notices where kind = 'note_overdue'
  and account_id = '00000000-0000-0000-0000-000000000011'), 0, 'tutors don''t get admin notices');
select private.queue_note_reminders();
select tests.eq((select count(*) from public.progress_notices where session_id in
  ('00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-0000000e0003')
  and account_id in ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000a0')), 3, 'reminders queued only once');
-- Make them visible now, whatever the time of day the test runs.
update public.progress_notices set deliver_at = now() - interval '1 minute';

-- ===========================================================================
-- Notes due
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.list_notes_due() where session_id::text like '00000000-0000-0000-0000-0000000e%'), 2, 'tutor sees own sessions needing a note');
select tests.eq((select count(*) from public.list_notes_due() where student_id = :'vic'), 0, 'tutor doesn''t see other tutors'' sessions');
select tests.eq((select count(*) from public.progress_notices where account_id <> '00000000-0000-0000-0000-000000000011'), 0, 'tutor sees only own notices');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1');
set role authenticated;
select tests.eq((select count(*) from public.list_notes_due()), 0, 'tutor without two-step sees nothing due');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.list_notes_due()), 0, 'parent sees no notes due');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.list_notes_due() where session_id::text like '00000000-0000-0000-0000-0000000e%'), 3, 'admin sees everyone''s');
reset role;

-- ===========================================================================
-- A note for a booked session
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select public.save_session_note(
  p_student => :'cara', p_session_date => current_date, p_minutes => 60, p_attendance => 'attended',
  p_went_well => 'You explained your working clearly.', p_next_step => 'Practise comparing fractions with drawings.',
  p_session => '00000000-0000-0000-0000-0000000e0003', p_home_tip => 'Ask Cara to explain one fraction at dinner.',
  p_writing_seconds => 140) as linked \gset
select tests.eq((select count(*) from public.session_notes where id = :'linked'
  and session_date = ((now() - interval '73 hours') at time zone 'Australia/Adelaide')::date), 1, 'date comes from the session');
select tests.fails(format($$select public.save_session_note(p_student => %L, p_session_date => current_date, p_minutes => 60,
  p_attendance => 'attended', p_went_well => 'ok', p_next_step => 'next', p_session => '00000000-0000-0000-0000-0000000e0003')$$, :'cara'),
  'second note for the same session');
select tests.fails(format($$select public.save_session_note(p_student => %L, p_session_date => current_date, p_minutes => 60,
  p_attendance => 'attended', p_went_well => 'ok', p_next_step => 'next', p_session => '00000000-0000-0000-0000-0000000e00b0')$$, :'cara'),
  'note for another student''s session');
select tests.fails(format($$select public.save_session_note(p_student => %L, p_session_date => current_date, p_minutes => 60,
  p_attendance => 'attended', p_went_well => 'ok', p_next_step => 'next', p_session => '00000000-0000-0000-0000-0000000e00c0')$$, :'cara'),
  'note for a cancelled session');
select tests.fails(format($$select public.save_session_note(p_student => %L, p_session_date => current_date, p_minutes => 60,
  p_attendance => 'attended', p_went_well => 'ok', p_next_step => 'next', p_session => '00000000-0000-0000-0000-0000000e00f0')$$, :'cara'),
  'note for a session that hasn''t happened');
select tests.eq((select count(*) from public.session_note_stats), 0, 'tutor can''t read writing times');
select tests.fails($$insert into public.session_note_stats (note_id, writing_seconds) select id, 1 from public.session_notes limit 1$$, 'tutor writes stats directly');
select tests.fails($$insert into public.progress_notices (account_id, student_id, kind, title, body, deliver_at) values ('00000000-0000-0000-0000-000000000001', (select id from public.students limit 1), 'session_update', 'x', 'x', now())$$, 'tutor writes notices directly');
update public.session_notes set home_tip = 'Ask Cara to explain one fraction to you.' where id = :'linked';
select tests.eq((select count(*) from public.session_notes where home_tip like 'Ask Cara to explain one fraction to you%'), 1, 'tutor corrects the tip');
select tests.fails(format($$update public.session_notes set session_id = null where id = %L$$, :'linked'), 'note moved off its session');
select tests.eq((select count(*) from public.list_notes_due() where session_id::text like '00000000-0000-0000-0000-0000000e%'), 1, 'noted session no longer due');
-- An older-style note (no session) for the same day also counts.
select public.save_session_note(:'cara', ((now() - interval '31 hours') at time zone 'Australia/Adelaide')::date, 60, 'attended', 'Good focus.', 'Learn the 7 times table.');
select tests.eq((select count(*) from public.list_notes_due() where session_id::text like '00000000-0000-0000-0000-0000000e%'), 0, 'same-day note counts for the session');
reset role;

select tests.claims(null);
select tests.eq((select writing_seconds from public.session_note_stats where note_id = :'linked'), 140, 'writing time saved');
select tests.eq((select count(*) from public.progress_notices where note_id = :'linked' and kind = 'session_update'
  and account_id = '00000000-0000-0000-0000-000000000001' and body like '%Try at home: Ask Cara%'), 1, 'parent gets the update with the tip');
select tests.eq((select count(*) from public.progress_notices where note_id = :'linked'
  and account_id = '00000000-0000-0000-0000-000000000011'), 0, 'the writer isn''t told about their own note');
update public.progress_notices set deliver_at = now() - interval '1 minute' where note_id is not null;

-- ===========================================================================
-- What the family sees
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.session_notes where home_tip is not null), 1, 'parent sees the tip');
update public.session_notes set home_tip = 'changed' where id = :'linked';
select tests.eq((select count(*) from public.session_notes where home_tip = 'changed'), 0, 'parent cannot change the tip');
select tests.eq((select count(*) from public.session_note_stats), 0, 'parent can''t read writing times');
-- Three: the two notes above, plus the first note in progress.test.sql.
select tests.eq((select count(*) from public.progress_notices where kind = 'session_update' and read_at is null), 3, 'parent sees updates');
select tests.eq((select count(*) from public.progress_notices where kind <> 'session_update'), 0, 'parent sees no tutor or admin reminders');
select tests.fails($$update public.progress_notices set read_at = now()$$, 'parent edits notices directly');
select public.mark_progress_notices_read(:'cara');
select tests.eq((select count(*) from public.progress_notices where read_at is null), 0, 'parent marks updates read');
select tests.eq((select count(*) from public.progress_students_to_check()), 0, 'parent gets no staff list');
select tests.fails($$select * from public.progress_measures(current_date - 10, current_date)$$, 'parent reads measures');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.progress_notices), 0, 'other parent sees no updates');
reset role;

-- ===========================================================================
-- Tutor and admin lists
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.progress_students_to_check() where student_id = :'cara'), 1, 'tutor sees own student');
select tests.eq((select count(*) from public.progress_students_to_check() where student_id = :'vic'), 0, 'tutor doesn''t see other students');
-- Two attended notes since a skill last moved.
select tests.eq((select notes_since_movement from public.progress_students_to_check() where student_id = :'cara'), 2, 'sessions since a skill moved');
select tests.eq((select active_goals from public.progress_students_to_check() where student_id = :'cara'), 3, 'active goals counted');
select tests.fails($$select * from public.progress_measures(current_date - 10, current_date)$$, 'tutor reads measures');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.progress_students_to_check() where student_id in (:'cara', :'vic')), 2, 'admin sees every student with a tutor');
select tests.eq((select writing_seconds from public.session_note_stats where note_id = :'linked'), 140, 'admin reads writing times');
select tests.eq((select median_writing_seconds from public.progress_measures(current_date - 10, current_date + 1)
  where tutor_id = '00000000-0000-0000-0000-000000000011'), 140, 'measures: median writing time');
select tests.eq((select (sessions_noted >= 2 and noted_within_24_hr <= sessions_noted and sessions_noted <= sessions_held)::int
  from public.progress_measures(current_date - 10, current_date + 1)
  where tutor_id = '00000000-0000-0000-0000-000000000011'), 1, 'measures: sessions held and noted');
select tests.eq((select sessions_noted - noted_within_24_hr from public.progress_measures(current_date - 10, current_date + 1)
  where tutor_id = '00000000-0000-0000-0000-000000000012'), 0, 'measures: tutor with no notes');
reset role;

-- Tidy up so later tests see the same data as before.
select tests.claims(null);
delete from public.sessions where id::text like '00000000-0000-0000-0000-0000000e%';
update public.session_notes set session_date = current_date where student_id = :'cara' and session_date = current_date - 20;

\echo '  progress follow-up: all checks passed'
