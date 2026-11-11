-- CLG offers another time or place that isn't in the tutor's availability
-- (Matching card, "Another time or place"). Reuses the earlier scheduling
-- tests' people: owner admin (...a0), tutor T4 (...14, General Maths Years
-- 1 to 12) and parent P3 (...03, Sam Three's parent).

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
delete from public.bookings where tutor_id = '00000000-0000-0000-0000-000000000014' and weekday = 7; -- Clears any Sunday bookings for tutor T4.
insert into public.libraries (name, suburb, state, suggested_by) -- Adds a library that CLG hasn't confirmed:
values ('Unconfirmed Test Library', 'Nowhere', 'SA', '00000000-0000-0000-0000-000000000014') -- (suggested by tutor T4)
-- and keeps its id as unconfirmed.
returning id as unconfirmed \gset

-- Families can't use it.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as test account ...03.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.offer_other_time(%L, 'General Maths', '00000000-0000-0000-0000-000000000014', -- Checks families can't offer another time:
  7::smallint, '07:00', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), 'families can''t offer another time'); -- (Sunday 7am online).
-- Nor skip the availability check by setting the switch themselves.
select tests.fails(format($$select set_config('clg.offer_other_time', 'on', false), public.request_booking(%L, 'General Maths', -- Checks the admin switch does nothing for families:
  '00000000-0000-0000-0000-000000000014', 7::smallint, '07:00', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), -- (turning it on, then asking for a Sunday 7am booking),
  'the switch does nothing for families'); -- (the label).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- An admin offers Sunday 7am online, outside the tutor's availability.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000014', -- Checks a normal booking still needs an available time:
  7::smallint, '07:00', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), 'a normal booking still needs an available time'); -- (Sunday 7am isn't in the tutor's availability).
select public.offer_other_time(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000014', -- An admin offers Sunday 7am anyway:
  -- (online, for about two months) and keeps its id as other.
  7::smallint, '07:00', 60, 'online', null, current_date + 7, current_date + 60) as other \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select (status = 'requested' and needs_family_ok and weekday = 7 and start_time = '07:00')::int -- Checks the offer waits for the tutor and family:
  from public.bookings where id = :'other'), 1, 'the offer waits for the tutor and family'); -- (asked for, needs the family's OK, Sunday at 7am).

set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.offer_other_time(%L, 'General Maths', '00000000-0000-0000-0000-000000000014', -- Checks it can't clash with the tutor's other bookings:
  7::smallint, '07:30', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), 'no clash with the tutor''s other bookings'); -- (Sunday 7:30am overlaps).
select tests.fails(format($$select public.offer_other_time(%L, 'General Maths', '00000000-0000-0000-0000-000000000014', -- Checks only confirmed libraries can be used:
  7::smallint, '10:00', 60, 'library', %L, current_date + 7, current_date + 60)$$, :'sam', :'unconfirmed'), 'only confirmed libraries'); -- (the unconfirmed library).
select tests.fails(format($$select public.offer_other_time(%L, 'Japanese', '00000000-0000-0000-0000-000000000014', -- Checks the tutor must teach the subject:
  7::smallint, '10:00', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), 'the tutor must teach the subject'); -- (Japanese).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Not past the tutor's weekly maximum.
select tests.claims(null); -- Signs out, so no one is signed in.
create temp table t4_saved as select max_weekly_hours from public.tutor_work_settings where tutor_id = '00000000-0000-0000-0000-000000000014'; -- Keeps tutor T4's weekly maximum in a short-lived table.
insert into public.tutor_work_settings (tutor_id, max_weekly_hours) values ('00000000-0000-0000-0000-000000000014', 1) -- Sets tutor T4's weekly maximum to 1 hr:
on conflict (tutor_id) do update set max_weekly_hours = 1; -- (or changes it if one is set).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.offer_other_time(%L, 'General Maths', '00000000-0000-0000-0000-000000000014', -- Checks it can't go past the weekly maximum:
  7::smallint, '10:00', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), 'not past the weekly maximum'); -- (another hour on Sunday).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Put things back.
select tests.claims(null); -- Signs out, so no one is signed in.
update public.tutor_work_settings set max_weekly_hours = (select max_weekly_hours from t4_saved) where tutor_id = '00000000-0000-0000-0000-000000000014'; -- Puts tutor T4's weekly maximum back.
drop table t4_saved; -- Removes the short-lived table.
delete from public.bookings where id = :'other'; -- Removes the offer.
delete from public.libraries where id = :'unconfirmed'; -- Removes the unconfirmed library.

-- Prints that every check in this file passed.
\echo '  scheduling offer another time: all checks passed'
