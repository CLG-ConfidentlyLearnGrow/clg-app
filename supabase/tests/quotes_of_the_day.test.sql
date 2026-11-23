-- Summary: tests quote of the day and quote of the month (Carla, 22 Nov
-- 2026). Reuses the owner (...a0), the Operations admin (...b0) and parent
-- P1 (...01). Everything is undone at the end. Checks: the 20 starting
-- quotes, today's quotes for anyone (signed out too), the day going round the
-- list, Carla's choice for the month, and that only the owner changes quotes.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the file again, to check it is safe to run more than once.
\ir ../migrations/20261124711800_quotes.sql

begin; -- Starts a change that is undone at the end, so nothing is left behind.

-- 1. The starting quotes are loaded once.
select tests.eq((select count(*) from public.quotes), 20, 'the 20 starting quotes are loaded once'); -- Checks: loaded, no repeats.

-- 2. Anyone gets today's quotes, signed out too.
set role anon; -- Acts as a signed-out visitor.
select tests.eq((select count(*) from public.quotes_today() where day_body is not null and month_body is not null), 1, 'a signed-out visitor gets both quotes'); -- Checks: loading screen works before sign-in.
select tests.fails($$select count(*) from public.quotes$$, 'a signed-out visitor cannot read the list itself'); -- Checks: list closed.
reset role; -- Back to the all-powerful test user.
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- Signs in as parent P1.
set role authenticated; -- Acts as a signed-in user.
select tests.eq((select count(*) from public.quotes), 0, 'a family does not see the list'); -- Checks: owner only.
select tests.eq((select count(*) from public.quotes_today() where day_body is not null), 1, 'a family gets the quote of the day'); -- Checks: Overview quote.
select tests.fails($$select public.quote_save(null, 'A family quote here', 'Someone', null, true)$$, 'a family cannot add a quote'); -- Checks: owner only.
reset role; -- Back to the test user.

-- 3. The day's quote is the next in the list each day (today's number, counted round the list).
select tests.eq((select count(*) from public.quotes_today() t join public.quotes q on q.body = t.day_body where q.position = 10 * (mod(((now() at time zone 'Australia/Adelaide')::date - date '2026-01-01'), 20) + 1)), 1, 'the day''s quote is today''s turn in the list'); -- Checks: the turn.

-- 4. The owner adds, changes and chooses quotes; Operations cannot.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the Operations admin.
set role authenticated; -- Acts as a signed-in user.
select tests.fails($$select public.quote_save(null, 'An Operations quote', 'Someone', null, true)$$, 'Operations cannot add a quote'); -- Checks: owner only.
reset role; -- Back to the test user.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner.
set role authenticated; -- Acts as a signed-in user.
select public.quote_save(null, 'Confidence comes from preparation.', 'CLG', 'Preparation', true) as mine \gset
select tests.fails_with($$select public.quote_save(null, 'You can''t win if you don''t start.', 'Someone', null, true)$$, 'out in full', 'a short form is refused'); -- Checks: no contractions.
select tests.fails_with($$select public.quote_save(null, 'Discipline equals freedom.', 'Someone else', null, true)$$, 'already in the list', 'a repeat is refused'); -- Checks: no repeats.
select public.quote_set_month((now() at time zone 'Australia/Adelaide')::date, :'mine'); -- Chooses it for this month.
select tests.eq((select count(*) from public.quotes_today() where month_body = 'Confidence comes from preparation.'), 1, 'the chosen quote is the quote of the month'); -- Checks: Carla's choice.
select tests.fails_with($$select public.quote_set_month(date '2020-01-01', null)$$, 'this month or a later one', 'a past month cannot be chosen'); -- Checks: no past months.
select public.quote_remove(:'mine'); -- Removes it.
select tests.eq((select count(*) from public.quotes_today() where month_body = 'Confidence comes from preparation.'), 0, 'removing a quote clears its month'); -- Checks: falls back to the list.
select tests.eq((select count(*) from public.quotes_today() where month_body is not null), 1, 'the month falls back to the list'); -- Checks: still a quote.
reset role; -- Back to the test user.

rollback; -- Undoes everything above.
\echo '  quotes: all checks passed'
