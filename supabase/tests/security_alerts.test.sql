-- Security alerts. Runs after access_rules.test.sql and reuses its people:
-- owner Olive (...a0), staff admin (...b0) and parent P3 (...03).

select tests.claims(null); -- Signs out, so no one is signed in.

-- Start clean: alerts from earlier tests count as already sent.
update public.security_alerts set sent_at = now() where sent_at is null; -- Marks any earlier alerts as sent, so only new ones count.
select tests.eq(private.security_alerts_waiting()::int, 0, 'no alerts waiting'); -- Checks: no alerts waiting.

-- Giving tutor or admin access raises an alert; removing admin does too.
insert into public.account_roles (account_id, role, granted_by) -- Gives account ...03 the tutor role:
  values ('00000000-0000-0000-0000-000000000003', 'tutor', '00000000-0000-0000-0000-0000000000a0'); -- (granted by the owner).
insert into public.account_roles (account_id, role, granted_by) -- Gives the same account the admin role:
  values ('00000000-0000-0000-0000-000000000003', 'admin', '00000000-0000-0000-0000-0000000000a0'); -- (granted by the owner).
delete from public.account_roles where account_id = '00000000-0000-0000-0000-000000000003' and role in ('admin', 'tutor'); -- Takes both roles away again.
select tests.eq((select count(*) from public.security_alerts where kind = 'role_given' and sent_at is null), 2, 'tutor and admin access given'); -- Checks: tutor and admin access given.
select tests.eq((select count(*) from public.security_alerts where kind = 'role_removed' and sent_at is null), 1, 'admin access removed (tutor removal is not an alert)'); -- Checks: admin access removed (tutor removal is not an alert).

-- A locked account raises one alert.
select public.record_login_attempt('locked.alert@example.com', false) from generate_series(1, 5); -- Five wrong passwords in a row for one email.
select tests.eq((select count(*) from public.security_alerts where kind = 'account_locked' and email = 'locked.alert@example.com'), 1, 'lock raises an alert'); -- Checks: lock raises an alert.

-- Many wrong passwords across accounts: one alert, not one per attempt.
select public.record_login_attempt('spray' || g || '@example.com', false) from generate_series(1, 40) g; -- Wrong passwords for 40 different emails (a "password spray").
select tests.eq((select count(*) from public.security_alerts where kind = 'many_failed_logins'), 1, 'one alert for many failed sign-ins'); -- Checks: one alert for many failed sign-ins.

select tests.eq(private.security_alerts_waiting()::int, 1, 'alerts waiting'); -- Checks: alerts waiting.
select tests.eq(private.emails_waiting()::int, 1, 'email sender is woken for alerts'); -- Checks: email sender is woken for alerts.

-- Only the owner can read alerts; nobody can add, change or send them.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.security_alerts), 0, 'staff admin reads no alerts'); -- Checks: staff admin reads no alerts.
select tests.fails($$insert into public.security_alerts (kind) values ('account_locked')$$, 'staff admin adds an alert'); -- Checks this is refused: staff admin adds an alert.
select tests.fails($$select * from public.security_alert_emails_claim()$$, 'staff admin takes alert emails'); -- Checks this is refused: staff admin takes alert emails.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.security_alerts where sent_at is null), 5, 'owner reads alerts'); -- Checks: owner reads alerts.
select tests.fails($$update public.security_alerts set sent_at = now()$$, 'owner marks alerts sent'); -- Checks this is refused: owner marks alerts sent.
select tests.fails($$delete from public.security_alerts$$, 'owner deletes alerts'); -- Checks this is refused: owner deletes alerts.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The app's sender: one email to the owner listing all five.
select tests.claims(null); -- Signs out, so no one is signed in.
set role service_role; -- Acts as the server's own key.
create temp table claimed as select * from public.security_alert_emails_claim(); -- Claims the alerts waiting to be emailed, keeping them in a short-lived table.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from claimed), 1, 'one email per owner'); -- Checks: one email per owner.
select tests.eq((select count(*) from claimed where email = 'owner@clg.example' and subject = 'CLG app security alerts (5)'), 1, 'sent to the owner with a count'); -- Checks: sent to the owner with a count.
select tests.eq((select count(*) from claimed where body like '%locked.alert@example.com was locked%' and body like '%given tutor access by Olive Owner%'), 1, 'plain sentences in the email'); -- Checks: plain sentences in the email.
select tests.eq(private.security_alerts_waiting()::int, 0, 'nothing waiting after sending'); -- Checks: nothing waiting after sending.

-- If sending fails, the alerts go back to wait for the next run.
set role service_role; -- Acts as the server's own key.
select public.security_alert_emails_release(array(select id from claimed)); -- Hands the claimed alerts back as not sent.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.security_alerts where sent_at is null), 5, 'alerts put back'); -- Checks: alerts put back.

-- Leave everything sent for the tests that follow.
update public.security_alerts set sent_at = now() where sent_at is null; -- Marks every alert as sent, to tidy up.
drop table claimed; -- Removes the short-lived table.
