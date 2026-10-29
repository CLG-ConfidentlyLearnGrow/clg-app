-- Admin levels: owner, operations, support, finance, and emergency owner
-- access. Runs after the billing, scheduling and progress tests (file names
-- run in order) so there is data to look at. Reuses owner (...a0),
-- operations admin (...b0), parent P1 (...01) and tutor T1 (...11).
-- Ids used here: support admin ...7c1, finance admin ...7c2.

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000007c1', 'desk@clg.example', now(), '{"signup_as":"parent","full_name":"Dee Desk"}'),
  ('00000000-0000-0000-0000-0000000007c2', 'books@clg.example', now(), '{"signup_as":"parent","full_name":"Bo Books"}');

-- ---------------------------------------------------------------------------
-- Adding admins at a level
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails($$select public.grant_staff_role('desk@clg.example', 'admin', 'support')$$, 'operations adds an admin');
select tests.fails($$select public.create_staff_invite_link('new.admin@clg.example', 'admin', 'finance')$$, 'operations invites an admin');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails($$select public.grant_staff_role('desk@clg.example', 'admin', 'owner')$$, 'owner makes a second owner');
select tests.fails($$select public.grant_staff_role('desk@clg.example', 'admin', 'boss')$$, 'unknown level');
select tests.eq((select public.grant_staff_role('desk@clg.example', 'admin', 'support'))::int, 1, 'owner adds a support admin');
select tests.eq((select public.grant_staff_role('books@clg.example', 'admin', 'finance'))::int, 1, 'owner adds a finance admin');
select tests.eq((select length(public.create_staff_invite_link('new.admin@clg.example', 'admin', 'finance'))), 64, 'owner invites a finance admin');
reset role;
select tests.eq((select count(*) from public.invitations where email = 'new.admin@clg.example' and admin_level = 'finance'), 1, 'invitation carries the level');
select tests.eq((select count(*) from public.admin_profiles where account_id = '00000000-0000-0000-0000-0000000007c1' and level = 'support'), 1, 'support level saved');
select tests.eq((select count(*) from public.admin_profiles where account_id = '00000000-0000-0000-0000-0000000007c2' and level = 'finance'), 1, 'finance level saved');
delete from public.invitations where email = 'new.admin@clg.example';

-- Each person's level, and none without two-step login.
create function tests.level_of(p_user uuid, p_aal text default 'aal2') returns text
language plpgsql as $$
declare v text;
begin
  perform tests.claims(p_user, p_aal);
  execute 'set local role authenticated';
  select public.my_admin_level() into v;
  return v;
end;
$$;
do $$
begin
  if tests.level_of('00000000-0000-0000-0000-0000000000a0') <> 'owner' then raise exception 'FAIL owner level'; end if;
  if tests.level_of('00000000-0000-0000-0000-0000000000b0') <> 'operations' then raise exception 'FAIL operations level'; end if;
  if tests.level_of('00000000-0000-0000-0000-0000000007c1') <> 'support' then raise exception 'FAIL support level'; end if;
  if tests.level_of('00000000-0000-0000-0000-0000000007c2') <> 'finance' then raise exception 'FAIL finance level'; end if;
  if tests.level_of('00000000-0000-0000-0000-0000000007c1', 'aal1') is not null then raise exception 'FAIL level without two-step login'; end if;
  if tests.level_of('00000000-0000-0000-0000-000000000011') is not null then raise exception 'FAIL tutor has an admin level'; end if;
end;
$$;
reset role;

-- A pay setting and an invoice to look at (the billing tests tidy theirs away).
insert into public.billing_staff_pay (account_id, employment, school_rate_cents)
values ('00000000-0000-0000-0000-000000000011', 'casual', 3400) on conflict do nothing;
insert into public.billing_invoices (family_id, family_name, plan, method, period_start, period_end, first_session_on, send_on, due_on, charge_on)
select id, name, 'weekly', 'card', current_date, current_date + 6, current_date, current_date, current_date, current_date
from public.families order by name limit 1;

-- What exists, counted without any rules, to compare against.
create temporary table totals as
select
  (select count(*) from public.students) as students,
  (select count(*) from public.families) as families,
  (select count(*) from public.sessions) as sessions,
  (select count(*) from public.bookings) as bookings,
  (select count(*) from public.tutor_checks) as checks,
  (select count(*) from public.session_notes) as notes,
  (select count(*) from public.billing_invoices) as invoices,
  (select count(*) from public.billing_staff_pay) as pay,
  (select count(*) from public.accounts) as accounts;
grant select on totals to authenticated;
do $$
begin
  if (select least(students, families, sessions, checks, notes, invoices, pay) from totals) = 0 then
    raise exception 'FAIL earlier tests left no data to compare with: %', (select row_to_json(t) from totals t);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Support: families, bookings, login links. No learning records, checks or money.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000007c1', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.students), (select students from totals), 'support sees students');
select tests.eq((select count(*) from public.families), (select families from totals), 'support sees families');
select tests.eq((select count(*) from public.sessions), (select sessions from totals), 'support sees sessions');
select tests.eq((select count(*) from public.bookings), (select bookings from totals), 'support sees bookings');
select tests.eq((select count(*) from public.account_private), (select accounts from totals), 'support sees contact details');
select tests.eq((select count(*) from public.tutor_checks), 0, 'support sees no tutor checks');
select tests.eq((select count(*) from public.session_notes), 0, 'support sees no session notes');
select tests.eq((select count(*) from public.billing_invoices), 0, 'support sees no invoices');
select tests.eq((select count(*) from public.billing_staff_pay), 0, 'support sees no pay');
select tests.eq((select count(*) from public.retention_holds), 0, 'support sees no record holds');
select tests.eq((select count(*) from public.family_pause_status()), (select families from totals), 'support sees whether families are paused');
select tests.eq((select count(*) from public.admin_find_account('p1@example.com')), 1, 'support looks up a family');
select tests.fails($$select * from public.eligible_tutors((select id from public.students limit 1))$$, 'support matches tutors');
select public.admin_add_child('00000000-0000-0000-0000-000000000001', 'Desk Child',
  (current_date - interval '8 years')::date, 'SA', 'Year 3', 'Hill PS',
  '[{"subject": "English", "level": null}]', null, null) as desk_child \gset
select tests.eq((select count(*) from public.students where id = :'desk_child'), 1, 'support sets up a child for a family');
select tests.eq((select count(*) from public.staff_list()), 0, 'support does not see the staff list');
update public.parent_student_links set relationship = 'changed by support';
select tests.eq((select count(*) from public.parent_student_links where relationship = 'changed by support'), 0, 'support cannot change or confirm parent links');
update public.account_private set phone = '0400 000 000' where account_id = '00000000-0000-0000-0000-000000000001';
select tests.eq((select count(*) from public.account_private where phone = '0400 000 000'), 1, 'support corrects a phone number');
select tests.fails($$select public.request_emergency_owner_access('Carla is unreachable this week')$$, 'support asks for emergency access');
select tests.eq((select count(*) from public.audit_log where actor_id <> '00000000-0000-0000-0000-0000000007c1'), 0, 'support reads only their own activity');
reset role;

-- ---------------------------------------------------------------------------
-- Finance: invoices, payments, credits, pay. No students, sessions or notes.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000007c2', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.billing_invoices), (select invoices from totals), 'finance sees invoices');
select tests.eq((select count(*) from public.billing_staff_pay), (select pay from totals), 'finance sees pay');
select tests.eq((select count(*) from public.accounts), (select accounts from totals), 'finance sees names');
select tests.eq((select count(*) from public.account_private), 1, 'finance sees only their own contact details');
select tests.eq((select count(*) from public.students), 0, 'finance sees no student records');
select tests.eq((select count(*) from public.sessions), 0, 'finance sees no sessions');
select tests.eq((select count(*) from public.session_notes), 0, 'finance sees no session notes');
select tests.eq((select count(*) from public.tutor_checks), 0, 'finance sees no tutor checks');
update public.billing_staff_pay set admin_rate_cents = 3500 where account_id = '00000000-0000-0000-0000-000000000011';
select tests.eq((select count(*) from public.billing_staff_pay where admin_rate_cents = 3500), 1, 'finance sets a pay rate');
update public.billing_price_items set description = 'Finance edit';
select tests.eq((select count(*) from public.billing_price_items where description = 'Finance edit'), 0, 'finance cannot change prices');
update public.billing_award_rates set min_rate_cents = 1;
select tests.eq((select count(*) from public.billing_award_rates where min_rate_cents = 1), 0, 'finance cannot change award rates');
select tests.fails($$select * from public.admin_find_account('p1@example.com')$$, 'finance looks up a family');
select tests.fails($$select public.grant_staff_role('someone@example.com', 'tutor')$$, 'finance adds a tutor');
reset role;

-- ---------------------------------------------------------------------------
-- Operations: everything it had, but sees pay without changing it.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.tutor_checks), (select checks from totals), 'operations sees tutor checks');
select tests.eq((select count(*) from public.session_notes), (select notes from totals), 'operations sees session notes');
select tests.eq((select count(*) from public.billing_invoices), (select invoices from totals), 'operations sees invoices');
select tests.eq((select count(*) from public.billing_staff_pay), (select pay from totals), 'operations sees pay');
update public.billing_staff_pay set admin_rate_cents = 1;
select tests.eq((select count(*) from public.billing_staff_pay where admin_rate_cents = 1), 0, 'operations cannot change pay');
select tests.eq((select count(*) from public.staff_list() where admin_level = 'support'), 1, 'operations sees levels in the staff list');
select tests.fails($$select public.set_admin_level('00000000-0000-0000-0000-0000000007c1', 'finance')$$, 'operations changes a level');
select tests.eq((select count(*) from public.audit_log where actor_id <> '00000000-0000-0000-0000-0000000000b0'), 0, 'operations reads only their own activity');
reset role;

-- ---------------------------------------------------------------------------
-- The owner changes levels and sees the staff list
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.staff_list() where admin_level is not null), (select count(*) from public.account_roles where role = 'admin'), 'owner sees every admin with a level');
select tests.eq((select count(*) from public.staff_list() where is_tutor), (select count(*) from public.account_roles where role = 'tutor'), 'owner sees tutors');
select public.set_admin_level('00000000-0000-0000-0000-0000000007c1', 'finance');
select tests.eq((select count(*) from public.admin_profiles where account_id = '00000000-0000-0000-0000-0000000007c1' and level = 'finance'), 1, 'owner changes a level');
select public.set_admin_level('00000000-0000-0000-0000-0000000007c1', 'support');
select tests.fails($$select public.set_admin_level('00000000-0000-0000-0000-0000000000a0', 'operations')$$, 'owner changes own level');
select tests.fails($$select public.set_admin_level('00000000-0000-0000-0000-0000000007c1', 'owner')$$, 'owner makes another owner');
select tests.fails($$select public.set_admin_level('00000000-0000-0000-0000-000000000001', 'support')$$, 'level for someone who is not an admin');
select tests.eq((select (count(*) > 0)::int from public.audit_log where actor_id = '00000000-0000-0000-0000-0000000000b0'), 1, 'owner reads other admins'' activity');
reset role;
select tests.eq((select count(*) from public.audit_log where table_name = 'admin_profiles' and actor_id = '00000000-0000-0000-0000-0000000000a0' and action = 'update'), 2, 'level changes are logged');

-- ---------------------------------------------------------------------------
-- Emergency owner access
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.fails($$select public.request_emergency_owner_access('help')$$, 'reason too short');
select tests.fails($$select public.request_emergency_owner_access(null)$$, 'no reason');
select public.request_emergency_owner_access('Carla is in hospital and a tutor needs to be added today.');
select tests.fails($$select public.request_emergency_owner_access('Asking a second time while waiting.')$$, 'second request while one is waiting');
select tests.eq((select count(*) from public.emergency_owner_access), 1, 'operations sees the request');
-- Waiting: still operations for 48 hours.
select tests.fails($$select public.set_admin_level('00000000-0000-0000-0000-0000000007c1', 'finance')$$, 'owner powers before 48 hours');
reset role;
select tests.eq((select count(*) from public.audit_log where action = 'emergency_access_requested'
  and details ->> 'reason' = 'Carla is in hospital and a tutor needs to be added today.'), 1, 'reason kept in the activity log');
select tests.eq((select count(*) from public.emergency_owner_access
  where starts_at between now() + interval '47 hours 59 minutes' and now() + interval '48 hours 1 minute'
    and ends_at = starts_at + interval '7 days'), 1, 'starts in 48 hours, lasts 7 days');

-- Others can't see or cancel it.
select tests.claims('00000000-0000-0000-0000-0000000007c1', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.emergency_owner_access), 0, 'support does not see requests');
reset role;
select id as request_id from public.emergency_owner_access \gset
select tests.claims('00000000-0000-0000-0000-0000000007c1', 'aal2');
set role authenticated;
select tests.fails(format($$select public.cancel_emergency_owner_access(%L)$$, :'request_id'), 'support cancels');
reset role;

-- The owner cancels it.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.emergency_owner_access), 1, 'owner sees the request');
select tests.eq((select (public.cancel_emergency_owner_access(:'request_id') = '00000000-0000-0000-0000-0000000000b0')::int), 1, 'owner cancels and learns who asked');
reset role;
select tests.eq((select count(*) from public.emergency_owner_access where cancelled_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'owner cancelled it');

-- Asked again and the 48 hours pass (moved by hand here).
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.request_emergency_owner_access('Carla unreachable overseas, invoices need approving.');
reset role;
update public.emergency_owner_access set starts_at = now() - interval '1 minute' where cancelled_at is null;
-- The person who asked is emailed that it has started (once).
select tests.eq((select private.emails_waiting())::int, 1, 'start email wakes the sender');
select tests.eq((select count(*) from public.emergency_access_emails_claim(10) where subject like '%has started' and email = 'staff@clg.example'), 1, 'start email to the person who asked');
select tests.eq((select count(*) from public.emergency_access_emails_claim(10)), 0, 'start email sent once');
select public.emergency_access_emails_release(array(select id from public.emergency_owner_access where cancelled_at is null));
select tests.eq((select count(*) from public.emergency_access_emails_claim(10)), 1, 'start email retried after a failed send');

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select (public.my_admin_level() = 'owner')::int), 1, 'acts as owner once started');
update public.billing_settings set override_by = 'admin';
select tests.eq((select count(*) from public.billing_settings where override_by = 'admin'), 1, 'uses an owner power');
update public.billing_settings set override_by = 'owner';
select public.set_admin_level('00000000-0000-0000-0000-0000000007c1', 'finance');
select public.set_admin_level('00000000-0000-0000-0000-0000000007c1', 'support');
-- The owner's own access can't be touched.
select tests.fails($$select public.set_admin_level('00000000-0000-0000-0000-0000000000a0', 'support')$$, 'emergency owner changes the owner');
update public.admin_profiles set level = 'support' where account_id = '00000000-0000-0000-0000-0000000000a0';
delete from public.admin_profiles where account_id = '00000000-0000-0000-0000-0000000000a0';
delete from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000a0' and role = 'admin';
select tests.fails($$insert into public.admin_profiles (account_id, level) values ('00000000-0000-0000-0000-0000000007c2', 'owner')$$, 'emergency owner makes a new owner');
select tests.fails($$update public.admin_profiles set level = 'owner' where account_id = '00000000-0000-0000-0000-0000000007c2'$$, 'emergency owner promotes to owner');
select tests.fails($$select public.request_emergency_owner_access('Extending my access for longer.')$$, 'asks again while running');
reset role;
select tests.eq((select count(*) from public.admin_profiles where account_id = '00000000-0000-0000-0000-0000000000a0' and level = 'owner'), 1, 'owner level untouched');
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-0000000000a0' and role = 'admin'), 1, 'owner admin role untouched');

-- After 7 days it ends by itself.
update public.emergency_owner_access set starts_at = now() - interval '8 days', ends_at = now() - interval '1 day' where cancelled_at is null;
select tests.eq((select count(*) from public.emergency_access_emails_claim(10) where subject like '%has ended'), 1, 'end email to the person who asked');
select tests.eq((select count(*) from public.emergency_access_emails_claim(10)), 0, 'end email sent once');
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select (public.my_admin_level() = 'operations')::int), 1, 'back to operations after 7 days');
reset role;

-- Moving someone off operations ends their access.
update public.emergency_owner_access set starts_at = now() - interval '1 minute', ends_at = now() + interval '6 days' where cancelled_at is null;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select public.set_admin_level('00000000-0000-0000-0000-0000000000b0', 'support');
select public.set_admin_level('00000000-0000-0000-0000-0000000000b0', 'operations');
reset role;
select tests.eq((select count(*) from public.emergency_owner_access where cancelled_at is null and ends_at > now()), 0, 'level change ends emergency access');
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select (public.my_admin_level() = 'operations')::int), 1, 'still operations');
reset role;

-- Tidy up for the tests that follow.
delete from public.students where full_name = 'Desk Child';
delete from public.billing_invoices;
delete from public.billing_staff_pay;
delete from public.account_roles where account_id in ('00000000-0000-0000-0000-0000000007c1', '00000000-0000-0000-0000-0000000007c2') and role = 'admin';
delete from public.admin_profiles where account_id in ('00000000-0000-0000-0000-0000000007c1', '00000000-0000-0000-0000-0000000007c2');
select tests.claims(null);

\echo '  staff levels: all checks passed'
