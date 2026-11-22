-- Summary: checks the reminder changes of 22 Nov 2026 (Carla): the first
-- session reminder is 24 hours before for everyone, and a family on hold
-- for an overdue payment gets a notice 48 hours before each session, with
-- the session cancelled 2 hours before if it is still not paid. Reuses the
-- earlier scheduling tests' people: parent Paula (...03) and her son Sam
-- Three, tutor T3 (...13) and the owner admin (...a0).

select tests.claims(null); -- acts as the database itself while setting up
select id as sam, family_id as fam from public.students where full_name = 'Sam Three' \gset
-- Paula pays for the family (set up here if the billing tests have not).
insert into public.billing_accounts (family_id, bill_payer_id) values (:'fam', '00000000-0000-0000-0000-000000000003')
on conflict (family_id) do update set bill_payer_id = excluded.bill_payer_id; -- names Paula as the bill payer
-- Two new sessions for Sam with tutor T3: one in 30 hours, one in 90 minutes.
insert into public.sessions (booking_id, student_id, tutor_id, family_id, subject, level_kind, delivery, library_id, starts_at, ends_at) -- adds the two sessions:
select x.booking_id, x.student_id, '00000000-0000-0000-0000-000000000013', x.family_id, x.subject, x.level_kind, 'online', null, -- copied from one of Sam's sessions, online with T3,
       date_trunc('minute', now()) + t.at, date_trunc('minute', now()) + t.at + interval '1 hour' -- at the two times
from (select * from public.sessions where student_id = :'sam' order by starts_at desc limit 1) x -- (one of Sam's sessions)
cross join (values (interval '30 hours'), (interval '90 minutes')) as t(at); -- the two times
select id as s30 from public.sessions where student_id = :'sam' and starts_at = date_trunc('minute', now()) + interval '30 hours' \gset
select id as s90 from public.sessions where student_id = :'sam' and starts_at = date_trunc('minute', now()) + interval '90 minutes' \gset

-- ---------------------------------------------------------------------------
-- The first reminder is 24 hours before, for everyone
-- ---------------------------------------------------------------------------
-- Paula had asked for her first reminder 72 hours before; it now comes at 24 hours anyway.
insert into public.notice_settings (account_id, first_reminder_hours) values ('00000000-0000-0000-0000-000000000003', 72)
on conflict (account_id) do update set first_reminder_hours = 72; -- her old setting
select private.queue_reminders(); -- queues the reminders
select tests.eq((select count(*) from public.session_notices where session_id = :'s30' and account_id = '00000000-0000-0000-0000-000000000003'
  and kind = 'reminder_first' and deliver_at >= date_trunc('minute', now()) + interval '6 hours' - interval '1 minute'), 1::bigint, 'the first reminder comes 24 hours before, whatever the old setting'); -- (30 hours away, so 6 hours from now, or later for quiet hours)
select tests.eq((select count(*) from public.session_notices where session_id = :'s30' and kind = 'reminder_final'
  and account_id = '00000000-0000-0000-0000-000000000003'), 1::bigint, 'the final reminder is still queued'); -- the 1-hour reminder

-- ---------------------------------------------------------------------------
-- Not on hold: nothing happens
-- ---------------------------------------------------------------------------
update public.billing_accounts set paused = false where family_id = :'fam'; -- the family is not on hold
select tests.eq(private.queue_unpaid_holds()::bigint, 0::bigint, 'no payment notices when the family is not on hold'); -- nothing

-- ---------------------------------------------------------------------------
-- On hold: the 48-hour notice to the person who pays
-- ---------------------------------------------------------------------------
update public.billing_accounts set paused = true, paused_since = now() where family_id = :'fam'; -- the family goes on hold
select private.queue_unpaid_holds(); -- runs the job
select tests.eq((select count(*) from public.session_notices where session_id = :'s30' and kind = 'unpaid_hold'
  and account_id = '00000000-0000-0000-0000-000000000003' and body like '%at least 2 hours before%' and body not like '%''t %'), 1::bigint, 'the person who pays is told 48 hours before'); -- Paula's notice
select tests.eq((select count(*) from public.session_notices where session_id = :'s30' and kind = 'unpaid_hold'
  and account_id = '00000000-0000-0000-0000-000000000013'), 0::bigint, 'the tutor is not told about the payment'); -- no notice to T3
select tests.eq((select count(*) from public.session_notices where session_id = :'s90' and kind = 'unpaid_hold'), 0::bigint, 'no notice when it is already under 2 hours away'); -- too late to warn
select private.queue_unpaid_holds(); -- runs the job again
select tests.eq((select count(*) from public.session_notices where session_id = :'s30' and kind = 'unpaid_hold'), 1::bigint, 'the notice is sent once'); -- still one
select tests.eq((select count(*) from public.sessions where id in (:'s30', :'s90') and status = 'cancelled'), 0::bigint, 'nothing is cancelled without a warning first'); -- the 90-minute one had no warning

-- ---------------------------------------------------------------------------
-- Still on hold 2 hours before: the session is cancelled and admins set up a meeting
-- ---------------------------------------------------------------------------
update public.sessions set starts_at = date_trunc('minute', now()) + interval '100 minutes', ends_at = date_trunc('minute', now()) + interval '160 minutes' where id = :'s30'; -- the warned session is now under 2 hours away
select private.queue_unpaid_holds(); -- runs the job
select tests.eq((select count(*) from public.sessions where id = :'s30' and status = 'cancelled' and cancelled_by_role = 'admin'
  and cancel_reason like 'Cancelled because the overdue payment%'), 1::bigint, 'the session is cancelled by CLG (full credit)'); -- cancelled
select tests.eq((select count(*) from public.session_notices where session_id = :'s30' and kind = 'unpaid_cancelled'
  and account_id = '00000000-0000-0000-0000-000000000003' and body like '%overdue payment%'), 1::bigint, 'the family is told why'); -- Paula's notice
select tests.eq((select count(*) from public.session_notices where session_id = :'s30' and kind = 'unpaid_cancelled'
  and account_id = '00000000-0000-0000-0000-000000000013' and body not like '%payment%'), 1::bigint, 'the tutor is told, with no money details'); -- T3's notice
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and kind = 'staff_alert'
  and title = 'Session cancelled for no payment' and body like '%meeting between Carla and%'), 1::bigint, 'admins are asked to set up a meeting with Carla'); -- the owner's notice
select tests.eq((select count(*) from public.sessions where id = :'s90' and status = 'scheduled'), 1::bigint, 'a session with no warning goes ahead'); -- the other one is untouched

-- ---------------------------------------------------------------------------
-- Clean up, so later tests start as before
-- ---------------------------------------------------------------------------
update public.billing_accounts set paused = false, paused_since = null where family_id = :'fam'; -- off hold
delete from public.sessions where id in (:'s30', :'s90'); -- removes the two test sessions
delete from public.notice_settings where account_id = '00000000-0000-0000-0000-000000000003'; -- removes the old setting
