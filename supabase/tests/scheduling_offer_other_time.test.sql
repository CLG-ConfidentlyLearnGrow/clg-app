-- CLG offers another time or place that isn't in the tutor's availability
-- (Matching card, "Another time or place"). Reuses the earlier scheduling
-- tests' people: owner admin (...a0), tutor T4 (...14, General Maths Years
-- 1 to 12) and parent P3 (...03, Sam Three's parent).

select tests.claims(null);
select id as sam from public.students where full_name = 'Sam Three' \gset
delete from public.bookings where tutor_id = '00000000-0000-0000-0000-000000000014' and weekday = 7;
insert into public.libraries (name, suburb, state, suggested_by)
values ('Unconfirmed Test Library', 'Nowhere', 'SA', '00000000-0000-0000-0000-000000000014')
returning id as unconfirmed \gset

-- Families can't use it.
select tests.claims('00000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.fails(format($$select public.offer_other_time(%L, 'General Maths', '00000000-0000-0000-0000-000000000014',
  7::smallint, '07:00', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), 'families can''t offer another time');
-- Nor skip the availability check by setting the switch themselves.
select tests.fails(format($$select set_config('clg.offer_other_time', 'on', false), public.request_booking(%L, 'General Maths',
  '00000000-0000-0000-0000-000000000014', 7::smallint, '07:00', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'),
  'the switch does nothing for families');
reset role;

-- An admin offers Sunday 7am online, outside the tutor's availability.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.request_booking(%L, 'General Maths', '00000000-0000-0000-0000-000000000014',
  7::smallint, '07:00', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), 'a normal booking still needs an available time');
select public.offer_other_time(:'sam', 'General Maths', '00000000-0000-0000-0000-000000000014',
  7::smallint, '07:00', 60, 'online', null, current_date + 7, current_date + 60) as other \gset
reset role;
select tests.eq((select (status = 'requested' and needs_family_ok and weekday = 7 and start_time = '07:00')::int
  from public.bookings where id = :'other'), 1, 'the offer waits for the tutor and family');

set role authenticated;
select tests.fails(format($$select public.offer_other_time(%L, 'General Maths', '00000000-0000-0000-0000-000000000014',
  7::smallint, '07:30', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), 'no clash with the tutor''s other bookings');
select tests.fails(format($$select public.offer_other_time(%L, 'General Maths', '00000000-0000-0000-0000-000000000014',
  7::smallint, '10:00', 60, 'library', %L, current_date + 7, current_date + 60)$$, :'sam', :'unconfirmed'), 'only confirmed libraries');
select tests.fails(format($$select public.offer_other_time(%L, 'Japanese', '00000000-0000-0000-0000-000000000014',
  7::smallint, '10:00', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), 'the tutor must teach the subject');
reset role;

-- Not past the tutor's weekly maximum.
select tests.claims(null);
create temp table t4_saved as select max_weekly_hours from public.tutor_work_settings where tutor_id = '00000000-0000-0000-0000-000000000014';
insert into public.tutor_work_settings (tutor_id, max_weekly_hours) values ('00000000-0000-0000-0000-000000000014', 1)
on conflict (tutor_id) do update set max_weekly_hours = 1;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails(format($$select public.offer_other_time(%L, 'General Maths', '00000000-0000-0000-0000-000000000014',
  7::smallint, '10:00', 60, 'online', null, current_date + 7, current_date + 60)$$, :'sam'), 'not past the weekly maximum');
reset role;

-- Put things back.
select tests.claims(null);
update public.tutor_work_settings set max_weekly_hours = (select max_weekly_hours from t4_saved) where tutor_id = '00000000-0000-0000-0000-000000000014';
drop table t4_saved;
delete from public.bookings where id = :'other';
delete from public.libraries where id = :'unconfirmed';

\echo '  scheduling offer another time: all checks passed'
