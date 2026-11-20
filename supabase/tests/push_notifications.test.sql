-- Summary: checks pop-up notifications (Carla, 18 Nov 2026): people can turn
-- pop-ups on and off only for their own devices, nobody sees anyone else's
-- device addresses, a shared device moves to whoever turned it on last,
-- only the server can collect pop-ups to send, pop-ups never repeat, wait
-- for quiet hours, skip read notices, and carry no names or details.
-- Reuses access_rules.test.sql people: operations admin Sam Staff (...b0,
-- no state, so Adelaide time), parent P1 (...01), parent P2 (...02).
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the pop-up database change again (checks it can run twice).
\ir ../migrations/20261121500100_push_notifications.sql

\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id: operations admin, Adelaide time)
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
\set p2 '00000000-0000-0000-0000-000000000002'
-- (parent P2's account id)

-- 1. People turn pop-ups on for their own device only.
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select public.push_subscribe('https://push.example.com/device-p1-phone', repeat('k', 87), repeat('a', 22), 'iPhone (Safari)'); -- P1 turns on pop-ups on their phone
select tests.eq((select count(*) from public.push_subscriptions), 1::bigint, 'a parent sees their own device'); -- one device
select public.push_subscribe('https://push.example.com/device-p1-phone', repeat('k', 87), repeat('a', 22), 'iPhone (Safari)'); -- P1 presses it again
select tests.eq((select count(*) from public.push_subscriptions), 1::bigint, 'turning on twice does not add the device twice'); -- still one
select tests.fails($q$select public.push_subscribe('http://push.example.com/not-secure-address', repeat('k', 87), repeat('a', 22), 'x')$q$, 'only secure delivery addresses are saved'); -- refused
select tests.fails($q$select public.push_subscribe('https://push.example.com/device-p1-laptop', 'short', repeat('a', 22), 'x')$q$, 'a device without a proper key is refused'); -- refused
select tests.fails(format($q$insert into public.push_subscriptions (account_id, endpoint, p256dh, auth_secret) values (%L, 'https://push.example.com/direct-insert', %L, %L)$q$, :'p1', repeat('k', 87), repeat('a', 22)), 'nobody adds devices to the table directly'); -- refused
select tests.fails($q$update public.push_subscriptions set device_label = 'changed'$q$, 'nobody changes devices directly'); -- refused
select tests.fails($q$select count(*) from public.push_sent$q$, 'signed-in people cannot see what has been sent'); -- refused
select tests.fails($q$select * from public.push_claim(10)$q$, 'signed-in people cannot collect pop-ups to send'); -- refused
reset role; -- back to the database itself

-- 2. Nobody else sees or removes P1's device.
select tests.claims(:'p2'); -- signs in as parent P2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.push_subscriptions), 0::bigint, 'another parent cannot see P1''s devices'); -- hidden
select public.push_remove_device((select id from public.push_subscriptions limit 1)); -- tries to remove a device it cannot see (nothing to remove)
select public.push_unsubscribe('https://push.example.com/device-p1-phone'); -- tries to turn off P1's phone by its address
reset role; -- back to the database itself
select tests.eq((select count(*) from public.push_subscriptions where account_id = :'p1'), 1::bigint, 'another parent cannot turn off P1''s device'); -- still there
select tests.claims(:'sam', 'aal2'); -- signs in as Sam (an admin)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.push_subscriptions), 0::bigint, 'admins cannot see other people''s devices either'); -- hidden
reset role; -- back to the database itself
select tests.claims(null); -- signed out
set role anon; -- acts as a visitor who is not signed in
select tests.fails($q$select public.push_subscribe('https://push.example.com/device-anon', repeat('k', 87), repeat('a', 22), 'x')$q$, 'signed-out visitors cannot turn on pop-ups'); -- refused
select tests.fails($q$select count(*) from public.push_subscriptions$q$, 'signed-out visitors cannot see devices'); -- refused
reset role; -- back to the database itself

-- 3. A shared device moves to whoever turned pop-ups on last.
select tests.claims(:'p2'); -- signs in as parent P2 on P1's phone (a shared family device)
set role authenticated; -- acts as a signed-in person
select public.push_subscribe('https://push.example.com/device-p1-phone', repeat('k', 87), repeat('a', 22), 'Shared iPad'); -- P2 turns on pop-ups there
select tests.eq((select count(*) from public.push_subscriptions), 1::bigint, 'the shared device now belongs to P2'); -- P2 sees it
reset role; -- back to the database itself
select tests.eq((select count(*) from public.push_subscriptions where account_id = :'p1'), 0::bigint, 'P1''s notices stop going to the shared device'); -- moved away from P1
select tests.claims(:'p2'); -- signs in as P2 again
set role authenticated; -- acts as a signed-in person
select public.push_unsubscribe('https://push.example.com/device-p1-phone'); -- P2 turns pop-ups off on that device
select tests.eq((select count(*) from public.push_subscriptions), 0::bigint, 'a person can turn off their own device'); -- removed
reset role; -- back to the database itself

-- 4. Which pop-ups are due (checked at fixed times yesterday, Adelaide time).
select tests.claims(:'sam', 'aal2'); -- signs in as Sam
set role authenticated; -- acts as a signed-in person
select public.push_subscribe('https://push.example.com/device-sam-laptop', repeat('k', 87), repeat('a', 22), 'Windows (Edge)'); -- Sam turns on pop-ups on a laptop
reset role; -- back to the database itself
insert into public.session_notices (account_id, kind, title, body, deliver_at) values -- adds test notices for Sam, in the past so quiet hours leave them alone:
  (:'sam', 'booking_confirmed', 'Booking confirmed for Mia', 'Mia''s Maths booking is confirmed.', ((current_date - 1) + time '11:50') at time zone 'Australia/Adelaide'), -- one at 11:50am yesterday
  (:'sam', 'booking_confirmed', 'Booking confirmed for Mia', 'Mia''s Maths booking is confirmed.', ((current_date - 1) + time '22:50') at time zone 'Australia/Adelaide'), -- one at 10:50pm yesterday (quiet hours)
  (:'p2', 'booking_confirmed', 'Booking confirmed', 'Booking confirmed.', ((current_date - 1) + time '11:50') at time zone 'Australia/Adelaide'); -- one for P2, who has no device turned on
select tests.eq((select count(*) from private.push_due(((current_date - 1) + time '12:00') at time zone 'Australia/Adelaide')), 1::bigint, 'at noon, only Sam''s notice is due (P2 has no device)'); -- one pop-up
select tests.eq((select count(*) from private.push_due(((current_date - 1) + time '12:00') at time zone 'Australia/Adelaide') d where d.title = 'Booking update' and d.body not like '%Mia%' and d.body not like '%Maths%'), 1::bigint, 'the pop-up has a plain title and no names or subjects'); -- no details
select tests.eq((select count(*) from private.push_due(((current_date - 1) + time '23:00') at time zone 'Australia/Adelaide')), 0::bigint, 'nothing pops up in quiet hours'); -- held
select tests.eq((select count(*) from private.push_due(((current_date - 1) + time '15:00') at time zone 'Australia/Adelaide')), 0::bigint, 'a notice older than 2 hours is not sent as a pop-up'); -- too old
insert into public.push_sent (source, source_id, account_id) -- records Sam's noon notice as already sent:
select 'session', n.id, n.account_id from public.session_notices n where n.account_id = :'sam' and n.title = 'Booking confirmed for Mia' and n.deliver_at = ((current_date - 1) + time '11:50') at time zone 'Australia/Adelaide'; -- (that one notice)
select tests.eq((select count(*) from private.push_due(((current_date - 1) + time '12:00') at time zone 'Australia/Adelaide')), 0::bigint, 'a pop-up is never sent twice'); -- already sent
delete from public.push_sent; -- clears the record again
update public.session_notices set read_at = now() where account_id = :'sam'; -- Sam reads the notices in the app
select tests.eq((select count(*) from private.push_due(((current_date - 1) + time '12:00') at time zone 'Australia/Adelaide')), 0::bigint, 'a notice already read in the app does not pop up'); -- skipped

-- 5. The server collects due pop-ups and records each one it takes.
update public.session_notices set read_at = null, deliver_at = now() - interval '1 minute' where account_id = :'sam'; -- makes Sam's notices fresh again (just arrived)
set role service_role; -- acts as the app's server
create temporary table claimed on commit drop as select * from public.push_claim(50); -- collects what is due now (none if it is quiet hours in Adelaide right now)
select tests.eq((select count(*) from public.push_sent), (select count(*) from pg_temp.claimed), 'every pop-up handed over is recorded as sent'); -- matches
select tests.eq((select count(*) from public.push_claim(50)), 0::bigint, 'collecting again straight away hands over nothing new'); -- no repeats
reset role; -- back to the database itself

-- 6. Devices and sent records go with the account (checked in the table rules).
select tests.eq((select count(*) from pg_constraint c where c.conrelid = 'public.push_subscriptions'::regclass and c.contype = 'f' and c.confdeltype = 'c'), 1::bigint, 'devices are removed with the account'); -- "on delete cascade" to accounts
select tests.eq((select count(*) from pg_constraint c where c.conrelid = 'public.push_sent'::regclass and c.contype = 'f' and c.confdeltype = 'c'), 1::bigint, 'sent records are removed with the account'); -- "on delete cascade" to accounts

-- Undoes everything above.
rollback;

-- Prints that every check in this file passed.
\echo '  pop-up notifications: all checks passed'
