-- Summary: tests end-of-day updates from admin staff (Carla, 22 Nov 2026).
-- Reuses the owner (...a0), the Operations admin (...b0) and tutor T1
-- (...11). Everything is undone at the end.
-- Checks: who can send, the date and wording rules, correcting an update,
-- who can see them, the missing-day reminder, and the owner's unread number.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the file again, to check it is safe to run more than once.
\ir ../migrations/20261124711400_admin_end_of_day_updates.sql

begin; -- Starts a change that is undone at the end, so nothing is left behind.
select ((now() at time zone 'Australia/Adelaide')::date) as today \gset

-- Office admin hours the Operations admin logged yesterday and two days ago (written straight in).
insert into public.billing_hour_logs (account_id, work_date, minutes, note, work_type, source) values -- Adds the hours:
  ('00000000-0000-0000-0000-0000000000b0', :'today'::date - 1, 120, 'Office admin', 'admin', 'staff'), -- yesterday,
  ('00000000-0000-0000-0000-0000000000b0', :'today'::date - 2, 60, 'Office admin', 'admin', 'staff'); -- two days ago.

-- 1. The Operations admin sends updates.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the Operations admin.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.my_missing_day_updates()), 2, 'two days with admin hours and no update'); -- Checks: both missing.
select public.admin_day_update_save(:'today'::date - 1, E'Answered 6 family emails\nBooked 2 trial sessions', 'Quick replies', 'Xero was slow'); -- Sends yesterday's update.
select tests.eq((select count(*) from public.my_missing_day_updates()), 1, 'one day still missing after sending yesterday'); -- Checks: one left.
select public.admin_day_update_save(:'today'::date - 1, E'Answered 7 family emails\nBooked 2 trial sessions', 'Quick replies', null); -- Corrects it.
select tests.eq((select count(*) from public.admin_day_updates where work_date = :'today'::date - 1 and did like 'Answered 7%' and not_well is null), 1, 'an update can be corrected (still one for the day)'); -- Checks: replaced, not doubled.
select tests.fails_with(format($$select public.admin_day_update_save(%L::date + 1, 'Tomorrow', null, null)$$, :'today'), 'today or a day in the last 7 days', 'a future day is refused'); -- Checks: plain refusal.
select tests.fails_with(format($$select public.admin_day_update_save(%L::date - 8, 'Old', null, null)$$, :'today'), 'today or a day in the last 7 days', 'a day over a week ago is refused'); -- Checks: plain refusal.
select tests.fails_with(format($$select public.admin_day_update_save(%L, ' ', null, null)$$, :'today'), 'Please write what you did', 'an empty update is refused'); -- Checks: plain refusal.
select tests.fails($$insert into public.admin_day_updates (account_id, work_date, did) values (auth.uid(), current_date, 'Direct')$$, 'updates cannot be written straight into the table'); -- Checks: only through the function.
select tests.eq(public.day_updates_unread_count(), 0, 'only the owner gets an unread number'); -- Checks: none for Operations.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- 2. A tutor cannot send one or see them.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1.
set role authenticated; -- Acts as a signed-in user.
select tests.fails_with(format($$select public.admin_day_update_save(%L, 'Tutoring', null, null)$$, :'today'), 'Only CLG admin staff', 'a tutor cannot send one'); -- Checks: admin staff only.
select tests.eq((select count(*) from public.admin_day_updates), 0, 'a tutor cannot see them'); -- Checks: hidden.
reset role; -- Back to the test user.

-- 3. The owner reads them.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.admin_day_updates where account_id = '00000000-0000-0000-0000-0000000000b0'), 1, 'the owner can see the update'); -- Checks: visible.
select tests.eq(public.day_updates_unread_count(), 1, 'the owner has one unread update'); -- Checks: the number.
select public.admin_day_updates_mark_read(array(select id from public.admin_day_updates)); -- Marks it read.
select tests.eq(public.day_updates_unread_count(), 0, 'none unread after marking read'); -- Checks: cleared.
reset role; -- Back to the test user.

-- 4. Others cannot mark updates read.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the Operations admin.
set role authenticated; -- Acts as a signed-in user.
select tests.fails($$select public.admin_day_updates_mark_read(array(select id from public.admin_day_updates))$$, 'only the owner marks updates read'); -- Checks: owner only.
reset role; -- Back to the test user.

rollback; -- Undoes everything this test added.
\echo '  end-of-day updates: all checks passed'
