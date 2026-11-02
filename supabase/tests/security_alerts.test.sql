-- Security alerts. Runs after access_rules.test.sql and reuses its people:
-- owner Olive (...a0), staff admin (...b0) and parent P3 (...03).

select tests.claims(null);

-- Start clean: alerts from earlier tests count as already sent.
update public.security_alerts set sent_at = now() where sent_at is null;
select tests.eq(private.security_alerts_waiting()::int, 0, 'no alerts waiting');

-- Giving tutor or admin access raises an alert; removing admin does too.
insert into public.account_roles (account_id, role, granted_by)
  values ('00000000-0000-0000-0000-000000000003', 'tutor', '00000000-0000-0000-0000-0000000000a0');
insert into public.account_roles (account_id, role, granted_by)
  values ('00000000-0000-0000-0000-000000000003', 'admin', '00000000-0000-0000-0000-0000000000a0');
delete from public.account_roles where account_id = '00000000-0000-0000-0000-000000000003' and role in ('admin', 'tutor');
select tests.eq((select count(*) from public.security_alerts where kind = 'role_given' and sent_at is null), 2, 'tutor and admin access given');
select tests.eq((select count(*) from public.security_alerts where kind = 'role_removed' and sent_at is null), 1, 'admin access removed (tutor removal is not an alert)');

-- A locked account raises one alert.
select public.record_login_attempt('locked.alert@example.com', false) from generate_series(1, 5);
select tests.eq((select count(*) from public.security_alerts where kind = 'account_locked' and email = 'locked.alert@example.com'), 1, 'lock raises an alert');

-- Many wrong passwords across accounts: one alert, not one per attempt.
select public.record_login_attempt('spray' || g || '@example.com', false) from generate_series(1, 40) g;
select tests.eq((select count(*) from public.security_alerts where kind = 'many_failed_logins'), 1, 'one alert for many failed sign-ins');

select tests.eq(private.security_alerts_waiting()::int, 1, 'alerts waiting');
select tests.eq(private.emails_waiting()::int, 1, 'email sender is woken for alerts');

-- Only the owner can read alerts; nobody can add, change or send them.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.security_alerts), 0, 'staff admin reads no alerts');
select tests.fails($$insert into public.security_alerts (kind) values ('account_locked')$$, 'staff admin adds an alert');
select tests.fails($$select * from public.security_alert_emails_claim()$$, 'staff admin takes alert emails');
reset role;
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.security_alerts where sent_at is null), 5, 'owner reads alerts');
select tests.fails($$update public.security_alerts set sent_at = now()$$, 'owner marks alerts sent');
select tests.fails($$delete from public.security_alerts$$, 'owner deletes alerts');
reset role;

-- The app's sender: one email to the owner listing all five.
select tests.claims(null);
set role service_role;
create temp table claimed as select * from public.security_alert_emails_claim();
reset role;
select tests.eq((select count(*) from claimed), 1, 'one email per owner');
select tests.eq((select count(*) from claimed where email = 'owner@clg.example' and subject = 'CLG app security alerts (5)'), 1, 'sent to the owner with a count');
select tests.eq((select count(*) from claimed where body like '%locked.alert@example.com was locked%' and body like '%given tutor access by Olive Owner%'), 1, 'plain sentences in the email');
select tests.eq(private.security_alerts_waiting()::int, 0, 'nothing waiting after sending');

-- If sending fails, the alerts go back to wait for the next run.
set role service_role;
select public.security_alert_emails_release(array(select id from claimed));
reset role;
select tests.eq((select count(*) from public.security_alerts where sent_at is null), 5, 'alerts put back');

-- Leave everything sent for the tests that follow.
update public.security_alerts set sent_at = now() where sent_at is null;
drop table claimed;
