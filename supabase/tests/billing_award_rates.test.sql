-- Yearly award rates: uploading them, raising rates that fall under the
-- new minimum, and paying earlier work at the old rate. Reuses people from
-- access_rules.test.sql: owner (...a0), operations admin (...b0), tutor
-- T1 (...11). Everything is rolled back at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this feature's database change (also checks it can run twice).
\ir ../migrations/20261113230100_billing_award_rates.sql

-- T1 is a casual tutor paid $33/hr for school tutoring and $70/hr tertiary.
insert into public.billing_staff_pay (account_id, employment, school_rate_cents, tertiary_rate_cents) values ('00000000-0000-0000-0000-000000000011', 'casual', 3300, 7000) -- T1's pay details
on conflict (account_id) do update set employment = 'casual', school_rate_cents = 3300, tertiary_rate_cents = 7000, admin_rate_cents = null; -- or update them
-- Keeps today's date and a date in the future.
select private.billing_today() as today, private.billing_today() + 30 as later \gset

-- Only the owner or Finance can upload.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.fails($$select public.billing_upload_award_rates(current_date, '[{"work_kind":"school","employment":"casual","rate_cents":3500}]')$$, 'operations uploads award rates'); -- checks this is refused
reset role; -- back to the test runner

-- Bad uploads are refused with a plain message.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.billing_upload_award_rates(%L, '[]')$$, :'later'), 'empty upload'); -- checks an empty file is refused
select tests.fails(format($$select public.billing_upload_award_rates(%L, '[{"work_kind":"maths","employment":"casual","rate_cents":3500}]')$$, :'later'), 'unknown kind of work'); -- checks a wrong work kind is refused
select tests.fails(format($$select public.billing_upload_award_rates(%L, '[{"work_kind":"school","employment":"casual","rate_cents":5}]')$$, :'later'), 'silly amount'); -- checks a tiny rate is refused

-- Rates for a future date are saved but don't change anyone yet.
select tests.eq(public.billing_upload_award_rates(:'later', '[{"work_kind":"school","employment":"casual","rate_cents":3500,"award":"Misc Award L1 casual"},{"work_kind":"tertiary","employment":"casual","rate_cents":6500}]'), 0, 'future rates: nobody changed yet'); -- uploads next year's rates
reset role; -- back to the test runner
select tests.claims(null); -- clears who is signed in
select tests.eq((select count(*) from public.billing_award_rates where effective_from = :'later'), 2, 'future rates saved'); -- checks both rows were saved
select tests.eq((select school_rate_cents from public.billing_staff_pay where account_id = '00000000-0000-0000-0000-000000000011'), 3300, 'rate unchanged before the start date'); -- checks T1 wasn't raised early

-- Pretend the start date has come: move the uploaded rates to yesterday.
update public.billing_award_rates set effective_from = :'today'::date - 1 where effective_from = :'later'; -- the new rates started yesterday
select tests.eq(public.billing_apply_award_rates(), 1, 'one rate raised'); -- runs the update as the daily run would
select tests.eq((select school_rate_cents from public.billing_staff_pay where account_id = '00000000-0000-0000-0000-000000000011'), 3500, 'school rate raised to the new minimum'); -- checks the raise
select tests.eq((select tertiary_rate_cents from public.billing_staff_pay where account_id = '00000000-0000-0000-0000-000000000011'), 7000, 'rate already above the minimum left alone'); -- checks the higher rate wasn't touched
select tests.eq((select count(*) from public.billing_staff_rate_changes where account_id = '00000000-0000-0000-0000-000000000011' and old_cents = 3300 and new_cents = 3500), 1, 'change logged'); -- checks the log
select tests.eq(public.billing_apply_award_rates(), 0, 'running again changes nothing'); -- checks it is safe to repeat

-- Work before the start date is paid at the old rate; work after at the new one.
select tests.eq(private.billing_pay_rate_on('00000000-0000-0000-0000-000000000011', 'school', :'today'::date - 2), 3300, 'old rate for work before the change'); -- the day before the start
select tests.eq(private.billing_pay_rate_on('00000000-0000-0000-0000-000000000011', 'school', :'today'::date - 1), 3500, 'new rate from the start date'); -- the start date

-- T1 can see their own change; nobody can write the log by hand.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.billing_staff_rate_changes), 1, 'tutor sees own rate change'); -- checks T1 can read it
select tests.fails($$insert into public.billing_staff_rate_changes (account_id, work_kind, old_cents, new_cents, effective_from, reason) values (auth.uid(), 'school', 1, 9999, current_date, 'x')$$, 'tutor writes the log'); -- checks this is refused
select tests.fails($$select public.billing_apply_award_rates()$$, 'tutor applies award rates'); -- checks this is refused
reset role; -- back to the test runner

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  billing award rates: all checks passed'
