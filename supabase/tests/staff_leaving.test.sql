-- Summary: tests for removing someone from the CLG team when they leave
-- (public.staff_leave), the "Left CLG" rows in the staff directory, and the
-- nightly clean-up keeping former staff accounts for 7 years.
-- Runs after access_rules.test.sql and reuses owner (...a0), operations
-- admin (...b0) and parent P1 (...01).
-- Ids used here: tutor Lou Leaver ...7e1, support admin Ada Away ...7e2
-- (both removed at the end).

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values -- Adds two test sign-ups:
  ('00000000-0000-0000-0000-0000000007e1', 'lou.leaver@clg.example', now(), '{"signup_as":"parent","full_name":"Lou Leaver"}'), -- Lou Leaver,
  ('00000000-0000-0000-0000-0000000007e2', 'ada.away@clg.example', now(), '{"signup_as":"parent","full_name":"Ada Away"}'); -- and Ada Away.
insert into public.account_roles (account_id, role) values -- Gives them staff roles:
  ('00000000-0000-0000-0000-0000000007e1', 'tutor'), -- Lou is a tutor,
  ('00000000-0000-0000-0000-0000000007e2', 'admin') -- Ada is an admin,
on conflict do nothing; -- (unless they already are).
insert into public.tutor_profiles (account_id) values ('00000000-0000-0000-0000-0000000007e1') on conflict do nothing; -- Lou's tutor profile (switched on).
insert into public.admin_profiles (account_id, level) values ('00000000-0000-0000-0000-0000000007e2', 'support') -- Ada is a support admin
on conflict (account_id) do update set level = excluded.level; -- (replacing any level she had).
select id as cara from public.students where full_name = 'Cara One' \gset
-- (Keeps student Cara One's id as cara, above.)
set session_replication_role = replica; -- Skips the usual checks for the next two lines (Lou has no safety checks on file, and this test is about leaving, not matching).
insert into public.tutor_assignments (tutor_id, student_id, subject) values ('00000000-0000-0000-0000-0000000007e1', :'cara', 'English'); -- Matches Lou with Cara for English.
insert into public.bookings (student_id, tutor_id, subject, weekday, start_time, minutes, delivery, first_date, last_date, status) -- Gives Lou a confirmed weekly booking with Cara:
values (:'cara', '00000000-0000-0000-0000-0000000007e1', 'English', 2, '16:00', 60, 'online', current_date, current_date + 28, 'confirmed') -- Tuesdays 4pm online, for four weeks,
returning id as lou_booking \gset
-- (Keeps that booking's id as lou_booking, above.)
set session_replication_role = origin; -- Turns the usual checks back on.
create table if not exists auth.sessions (id uuid primary key default gen_random_uuid(), user_id uuid); -- A stand-in for Supabase's sign-in sessions table (the test database doesn't have one).
insert into auth.sessions (user_id) values ('00000000-0000-0000-0000-0000000007e1'), ('00000000-0000-0000-0000-0000000007e1'); -- Lou is signed in on two devices.
insert into public.tutor_calendar_links (tutor_id, link_hash) values ('00000000-0000-0000-0000-0000000007e1', 'test-hash-lou'); -- Lou has a private calendar link.

-- ---------------------------------------------------------------------------
-- What the directory shows before anyone leaves
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select upcoming_bookings from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007e1'), 1, 'directory shows the tutor''s upcoming booking'); -- Checks: Lou's one booking is counted.
select tests.eq((select current_students from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007e1'), 1, 'directory shows the tutor''s current student'); -- Checks: Lou's one student is counted.
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007e1' and left_on is null), 1, 'current staff have no last day'); -- Checks: Lou shows as current.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Who may do it
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the operations admin.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-0000000007e2', current_date, 'moved', null, 'Ada Away')$$, 'Only the owner', 'operations admin can''t remove staff'); -- Checks: refused for an operations admin.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000007e2', 'aal2'); -- Signs in as Ada (a support admin).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-0000000007e1', current_date, 'moved', null, 'Lou Leaver')$$, 'Only the owner', 'support admin can''t remove staff'); -- Checks: refused for a support admin.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1'); -- Signs in as the owner WITHOUT two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-0000000007e2', current_date, 'moved', null, 'Ada Away')$$, 'Only the owner', 'owner needs two-step sign-in'); -- Checks: refused without two-step sign-in.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- The checks before anything changes
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-0000000007e2', current_date, 'moved', null, 'Ada Someone')$$, 'doesn''t match', 'wrong name typed'); -- Checks: the typed name must match.
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-0000000000a0', current_date, 'moved', null, 'Olive Owner')$$, 'remove yourself', 'owner can''t remove themselves'); -- Checks: the owner can't remove themselves.
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-000000000001', current_date, 'moved', null, (select full_name from public.accounts where id = '00000000-0000-0000-0000-000000000001'))$$, 'isn''t a current tutor or admin', 'a parent isn''t staff'); -- Checks: a parent (not staff) is refused.
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-0000000007e2', current_date + 1, 'moved', null, 'Ada Away')$$, 'can''t be in the future', 'last day in the future'); -- Checks: the last day can't be in the future.
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-0000000007e2', current_date - 400, 'moved', null, 'Ada Away')$$, 'within the past year', 'last day too long ago'); -- Checks: the last day must be within the past year.
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-0000000007e2', current_date, 'bored', null, 'Ada Away')$$, 'Choose why they left', 'unknown reason'); -- Checks: the reason must be on the list.
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-0000000007e1', current_date, 'own_study_or_work', null, 'Lou Leaver')$$, 'booking(s) coming up', 'tutor with bookings is refused'); -- Checks: a tutor with bookings coming up is refused.
select tests.fails($$insert into public.staff_departures (account_id, full_name, left_on, reason) values ('00000000-0000-0000-0000-0000000007e2', 'Ada Away', current_date, 'moved')$$, 'record written directly'); -- Checks: nobody writes the record directly.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000007e1' and role = 'tutor'), 1, 'refused tutor keeps their role'); -- Checks: nothing changed for Lou after the refusal.
select tests.eq((select count(*) from auth.sessions where user_id = '00000000-0000-0000-0000-0000000007e1'), 2, 'refused tutor is still signed in'); -- Checks: Lou is still signed in after the refusal.

-- ---------------------------------------------------------------------------
-- A tutor leaves (after their booking is ended)
-- ---------------------------------------------------------------------------
update public.bookings set status = 'ended', ended_at = now() where id = :'lou_booking'; -- Ends Lou's booking (as Sessions would).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.staff_leave('00000000-0000-0000-0000-0000000007e1', current_date - 2, 'own_study_or_work', '  Started full-time work.  ', ' Lou Leaver '); -- Removes Lou, whose last day was two days ago (name typed with stray spaces).
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007e1' and left_on = current_date - 2 and not is_tutor), 1, 'former tutor shows as left, with their last day'); -- Checks: Lou shows under "Left CLG".
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007e1' and leaving_reason = 'own_study_or_work'), 1, 'owner sees why they left'); -- Checks: the owner sees the reason.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000007e1' and role = 'tutor'), 0, 'tutor role ended'); -- Checks: Lou is no longer a tutor.
select tests.eq((select count(*) from public.tutor_profiles where account_id = '00000000-0000-0000-0000-0000000007e1' and not active and ended_on is not null), 1, 'tutor profile kept, marked finished'); -- Checks: the tutor profile is kept for the keeping period.
select tests.eq((select count(*) from public.tutor_assignments where tutor_id = '00000000-0000-0000-0000-0000000007e1' and (ends_on is null or ends_on > current_date)), 0, 'tutor matches ended'); -- Checks: Lou's match with Cara ended.
select tests.eq((select count(*) from public.bookings where id = :'lou_booking'), 1, 'session history kept'); -- Checks: the booking history is kept.
select tests.eq((select count(*) from auth.sessions where user_id = '00000000-0000-0000-0000-0000000007e1'), 0, 'signed out everywhere'); -- Checks: Lou is signed out on both devices.
select tests.eq((select count(*) from public.tutor_calendar_links where tutor_id = '00000000-0000-0000-0000-0000000007e1'), 0, 'calendar link removed'); -- Checks: Lou's calendar link is gone.
select tests.eq((select count(*) from public.staff_departures where account_id = '00000000-0000-0000-0000-0000000007e1' and full_name = 'Lou Leaver' and details = 'Started full-time work.' and roles_removed = '{tutor}'), 1, 'leaving recorded with tidy note'); -- Checks: the leaving record is written, note tidied.
select tests.eq((select count(*) from public.leaving_records where tutor_id = '00000000-0000-0000-0000-0000000007e1' and reason = 'own_study_or_work' and left_on = current_date - 2), 1, 'shared why-people-leave record written'); -- Checks: the shared leaving record has a line for Lou.
select tests.eq((select count(*) from public.audit_log where action = 'staff_left' and record_id = '00000000-0000-0000-0000-0000000007e1'), 1, 'leaving logged'); -- Checks: it's in the activity log.

-- Who can see the record.
select tests.claims('00000000-0000-0000-0000-0000000007e2', 'aal2'); -- Signs in as Ada (a support admin).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007e1' and left_on is not null and leaving_reason is null), 1, 'support admin sees they left, not why'); -- Checks: support admins see the last day but not the reason.
select tests.eq((select count(*) from public.staff_departures), 0, 'support admin can''t read the leaving records'); -- Checks: the table itself is hidden from support admins.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.staff_directory()), 0, 'parents see no directory'); -- Checks: parents see nobody.
select tests.eq((select count(*) from public.staff_departures), 0, 'parents see no leaving records'); -- Checks: parents see no leaving records.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- An admin leaves, and nothing can happen twice
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.staff_leave('00000000-0000-0000-0000-0000000007e2', current_date, 'clg_ended', null, 'Ada Away'); -- Removes Ada (CLG ended her employment).
select tests.fails_with($$select public.staff_leave('00000000-0000-0000-0000-0000000007e2', current_date, 'moved', null, 'Ada Away')$$, 'isn''t a current tutor or admin', 'can''t remove someone twice'); -- Checks: someone already gone can't be removed again.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000007e2' and role = 'admin'), 0, 'admin role ended'); -- Checks: Ada is no longer an admin.
select tests.eq((select count(*) from public.staff_departures where account_id = '00000000-0000-0000-0000-0000000007e2' and roles_removed = '{admin}' and details is null), 1, 'admin leaving recorded'); -- Checks: Ada's leaving is written down.
select tests.eq((select count(*) from public.leaving_records where tutor_id = '00000000-0000-0000-0000-0000000007e2'), 0, 'no tutor leaving line for a non-tutor'); -- Checks: no shared tutor line for an admin.

-- ---------------------------------------------------------------------------
-- Bringing someone back
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_add_role('00000000-0000-0000-0000-0000000007e1', 'tutor'); -- Lou rejoins as a tutor.
select tests.eq((select count(*) from public.staff_directory() where account_id = '00000000-0000-0000-0000-0000000007e1' and is_tutor and left_on is null), 1, 'rejoined tutor shows as current'); -- Checks: Lou shows as current again.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.tutor_calendar_links where tutor_id = '00000000-0000-0000-0000-0000000007e1'), 0, 'old calendar link doesn''t come back'); -- Checks: the old calendar link stays gone.
select tests.eq((select count(*) from public.staff_departures where account_id = '00000000-0000-0000-0000-0000000007e1'), 1, 'leaving history kept after rejoining'); -- Checks: the earlier leaving record stays.

-- ---------------------------------------------------------------------------
-- The nightly clean-up keeps former staff accounts for 7 years
-- ---------------------------------------------------------------------------
update auth.users set last_sign_in_at = now() - interval '2 years', created_at = now() - interval '3 years' where id = '00000000-0000-0000-0000-0000000007e2'; -- Pretends Ada hasn't signed in for 2 years.
update public.accounts set created_at = now() - interval '3 years' where id = '00000000-0000-0000-0000-0000000007e2'; -- (and that her account is 3 years old).
select tests.eq((select count(*) from private.retention_due(now()) where record_id = '00000000-0000-0000-0000-0000000007e2'), 0, 'former staff account not deleted inside 7 years'); -- Checks: Ada's account isn't due, though unused for 2 years.
select tests.eq((select count(*) from private.retention_due(now() + interval '7 years 1 day') where kind = 'account' and record_id = '00000000-0000-0000-0000-0000000007e2'), 1, 'former staff account due after 7 years'); -- Checks: it is due once the 7 years have passed.

-- ---------------------------------------------------------------------------
-- Tidy up
-- ---------------------------------------------------------------------------
select tests.claims(null); -- Signs out, so no one is signed in.
delete from public.bookings where id = :'lou_booking'; -- Removes Lou's test booking.
delete from public.leaving_records where tutor_id = '00000000-0000-0000-0000-0000000007e1'; -- Removes Lou's shared leaving line.
delete from auth.users where id in ('00000000-0000-0000-0000-0000000007e1', '00000000-0000-0000-0000-0000000007e2'); -- Removes both test people (their records go with them).
drop table auth.sessions; -- Removes the stand-in sessions table.
