-- To-do counts across the app (Carla, 11 Nov 2026): numbers on menus and
-- dashboard tabs. Uses its own parent (...d7) and tutor (...d8), plus the
-- owner admin (...a0). Admin numbers are checked as changes, because other
-- tests leave their own to-dos behind.

create function tests.todo(p_area text, p_section text) returns bigint
language sql as $$
  select coalesce(sum(n), 0)::bigint from public.to_do_counts() where area = p_area and section = p_section
$$;
grant execute on function tests.todo(text, text) to authenticated;

select tests.claims(null);
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000d7', 'todo-parent@example.com', '{"signup_as":"parent","full_name":"Tess Parent"}');
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
insert into public.invitations (email, role, invited_by) values ('todo-tutor@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0');
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000d8', 'todo-tutor@clg.example', '{"full_name":"Toby Tutor"}');
update auth.users set invited_at = now(), email_confirmed_at = now() where email = 'todo-tutor@clg.example';

-- Signed out: no counts at all.
set role anon;
select tests.fails($q$select * from public.to_do_counts()$q$, 'signed-out visitors get no counts');
reset role;

-- Parent: a child without an end goal is a detail to finish.
select tests.claims('00000000-0000-0000-0000-0000000000d7');
set role authenticated;
select public.add_my_child('Tia Parent', (current_date - interval '9 years')::date, 'SA', 'Year 4', 'Bay PS',
  '[{"subject": "Mathematics", "level": "Year 4"}]');
select tests.eq(tests.todo('parent', 'children'), 1, 'parent: one child''s details to finish');
select tests.eq((select count(*) from public.to_do_counts() where area in ('admin', 'billing', 'privacy', 'tutor')), 0,
  'parents get no admin or tutor counts');
reset role;
select tests.claims(null);
update public.students set goals = 'Feel confident with fractions' where full_name = 'Tia Parent';
select tests.claims('00000000-0000-0000-0000-0000000000d7');
set role authenticated;
select tests.eq(tests.todo('parent', 'children'), 0, 'parent: details finished, nothing to do');
reset role;

-- Parent: an unread session notice counts on Sessions.
select tests.claims(null);
insert into public.session_notices (account_id, kind, title, body, deliver_at)
values ('00000000-0000-0000-0000-0000000000d7', 'session_cancelled', 'To-do test', 'Test notice', now() - interval '1 minute');
select tests.claims('00000000-0000-0000-0000-0000000000d7');
set role authenticated;
select tests.eq(tests.todo('sessions', 'notices'), 1, 'unread notice counts on Sessions');
reset role;
select tests.claims(null);
update public.session_notices set read_at = now() where account_id = '00000000-0000-0000-0000-0000000000d7';
select tests.claims('00000000-0000-0000-0000-0000000000d7');
set role authenticated;
select tests.eq(tests.todo('sessions', 'notices'), 0, 'read notice no longer counts');
reset role;

-- Tutor: nothing in "What you teach" yet, and checks missing.
select tests.claims(null);
insert into public.tutor_work_settings (tutor_id, work_state) values ('00000000-0000-0000-0000-0000000000d8', 'SA')
on conflict (tutor_id) do update set work_state = excluded.work_state;
select tests.claims('00000000-0000-0000-0000-0000000000d8', 'aal2');
set role authenticated;
select tests.eq(tests.todo('tutor', 'teaching'), 1, 'new tutor: what you teach to fill in');
select tests.eq((tests.todo('tutor', 'checks') > 0)::int, 1, 'new tutor: checks missing');
select tests.eq((select count(*) from public.to_do_counts() where area in ('admin', 'billing', 'privacy')), 0,
  'tutors get no admin counts');
reset role;
select tests.claims(null);
insert into public.tutor_teaching (tutor_id, subject, from_level, to_level)
values ('00000000-0000-0000-0000-0000000000d8', 'Mathematics', 'Year 3', 'Year 6');
select tests.claims('00000000-0000-0000-0000-0000000000d8', 'aal2');
set role authenticated;
select tests.eq(tests.todo('tutor', 'teaching'), 0, 'tutor: what you teach filled in');
reset role;

-- Admin: a tutor's check waiting to be confirmed, and the tutor's own count
-- going down once it's confirmed.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.todo('admin', 'tutors') as tutors_before \gset
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000d8', 'aal2');
set role authenticated;
select tests.todo('tutor', 'checks') as tutor_checks_before \gset
reset role;
select tests.claims(null);
insert into public.tutor_checks (tutor_id, kind, reference, expires_on, submitted_at)
values ('00000000-0000-0000-0000-0000000000d8', 'wwcc_sa', 'TODO-1', current_date + 365, now())
returning id as todo_check \gset
-- Made here to look like a tutor's own upload, still waiting for CLG.
update public.tutor_checks set verified_at = null, verified_by = null where id = :'todo_check';
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq(tests.todo('admin', 'tutors'), :tutors_before + 1, 'admin: new check to confirm');
update public.tutor_checks set verified_at = now(), verified_by = '00000000-0000-0000-0000-0000000000a0' where id = :'todo_check';
select tests.eq(tests.todo('admin', 'tutors'), :tutors_before, 'admin: confirmed check comes off');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000d8', 'aal2');
set role authenticated;
select tests.eq((tests.todo('tutor', 'checks') < :tutor_checks_before)::int, 1, 'tutor: confirmed check no longer missing');
reset role;

-- Admin: a staff invitation that ran out unused.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.todo('admin', 'staff') as staff_before \gset
reset role;
select tests.claims(null);
insert into public.invitations (email, role, invited_by, expires_at)
values ('todo-late@clg.example', 'tutor', '00000000-0000-0000-0000-0000000000a0', now() - interval '1 day');
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq(tests.todo('admin', 'staff'), :staff_before + 1, 'admin: expired invitation to resend or remove');
-- Owner sees billing and records rows too (they may be 0).
select tests.eq((select count(*) from public.to_do_counts() where area = 'billing'), 3, 'owner gets the three billing counts');
select tests.eq((select count(*) from public.to_do_counts() where area = 'admin' and section = 'records'), 1, 'owner gets the records count');
reset role;

-- Put things back.
select tests.claims(null);
delete from public.invitations where email in ('todo-late@clg.example');
delete from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000d7';

\echo '  to-do counts: all checks passed'
